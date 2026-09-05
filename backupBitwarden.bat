@echo off
setlocal
:: To run this batch file install the following executables...
:: 1) Bitwarden CLI. https://bitwarden.com/help/cli/
::    (put the bw.exe file on your system path)
::    Use bw config server command if self-hosted or EU account.
:: 2) json parser. Download from https://jqlang.github.io/jq/
::    (rename to jq.exe and put on your system path)
::    (developed with jq - commandline JSON processor [version 1.7.1])
:: 3) Store this batch file somewhere on your VeraCrypt volume.
:: 4) Copy/rename config-template.bat -> config.bat.
:: 5) Configure config.bat as shown in comments.
@title Bitwarden Backup
rem Determine script directory
set "SCRIPT_DIR=%~dp0"
rem Config file location (same directory as script)
set "CONFIG_FILE=%SCRIPT_DIR%config.bat"
if not exist "%CONFIG_FILE%" (
    echo ERROR: config.bat not found.
    echo Expected at: %CONFIG_FILE%
    echo Copy config-template.bat to config.bat and edit it.
    goto terminate
)
call "%CONFIG_FILE%"
rem ============================================================
rem Configuration Sanity Checks
rem ============================================================

set "CONFIG_ERROR=0"
rem ---- Global required variables ----
if not defined B_OUTPUT_PARENT (
    echo ERROR: B_OUTPUT_PARENT not set in config.bat
    set "CONFIG_ERROR=1"
)
if not defined B_VAULTS (
    echo ERROR: B_VAULTS not set in config.bat
    set "CONFIG_ERROR=1"
)
rem ---- Per-vault required variables ----
for %%V in (%B_VAULTS%) do (
    if not defined %%V_NAME (
        echo ERROR: %%V_NAME not set in config.bat
        set "CONFIG_ERROR=1"
    )
    if not defined %%V_CLIENTID (
        echo ERROR: %%V_CLIENTID not set in config.bat
        set "CONFIG_ERROR=1"
    )
    if not defined %%V_CLIENTSECRET (
        echo ERROR: %%V_CLIENTSECRET not set in config.bat
        set "CONFIG_ERROR=1"
    )
    if not defined %%V_MASTER_PW (
        echo ERROR: %%V_MASTER_PW not set in config.bat
        set "CONFIG_ERROR=1"
    )
)
rem ---- Abort if any errors ----
if "%CONFIG_ERROR%"=="1" (
    @echo(
	echo Configuration errors detected. Aborting.
    goto terminate
)
echo(
:: Generate timestamp directory with YYYYMMDD_HHMM format
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"`) do set "B_TIMESTAMP=%%T"
if not defined B_TIMESTAMP (
    echo ERROR: could not determine timestamp.
    goto terminate
)
set "B_TIMESTAMP_DIR=%B_OUTPUT_PARENT%\exp_%B_TIMESTAMP%"
@echo This script saves unencrypted json exports of the Bitwarden vaults.
@echo (target only encrypted media such as VeraCrypt volume)
@echo Exports will be written to a new...
@echo %B_TIMESTAMP_DIR%
pause

@echo Checking for pending updates to the CLI...
rem Keep CLI state private to this script - never disturb the user's bw config
if defined BITWARDENCLI_APPDATA_DIR @echo Note: ignoring your BITWARDENCLI_APPDATA_DIR for this run.
if exist "%B_OUTPUT_PARENT%\_cli_appdata" rd /s /q "%B_OUTPUT_PARENT%\_cli_appdata"
set "BITWARDENCLI_APPDATA_DIR=%B_OUTPUT_PARENT%\_cli_appdata"
@echo BITWARDENCLI_APPDATA_DIR=%BITWARDENCLI_APPDATA_DIR%
if not exist "%BITWARDENCLI_APPDATA_DIR%" mkdir "%BITWARDENCLI_APPDATA_DIR%" || goto error-exit
rem override default bitwarden.com if necessary
if defined BW_SERVER_URL (
    @echo Setting bitwarden server: %BW_SERVER_URL%
    bw config server %BW_SERVER_URL% >nul 2>&1
    if errorlevel 1 goto error-exit
)
rem Show the configured server endpoint (helps avoid wrong .com/.edu/etc)
for /f "usebackq delims=" %%S in (`bw config server 2^>nul`) do set "BW_SERVER_DISPLAY=%%S"
if defined BW_SERVER_DISPLAY (
    @echo Confirm Bitwarden server: %BW_SERVER_DISPLAY%
) else (
    @echo Bitwarden server: (unable to determine)
)
bw update
@echo(
@echo If an update is pending, answer N, apply it, and re-run.
@echo https://bitwarden.com/help/cli/
choice /c YN /n /m "Continue with the current CLI version? [Y/N] "
if errorlevel 2 goto abort-preflight
bw logout >nul 2>&1
@echo(
:: Loop thru each vault to export
setlocal enabledelayedexpansion
set "count=0"
set "VERIFY_ERROR=0"
for %%V in (%B_VAULTS%) do (
    set /a count+=1
    set "B_NAME=!%%V_NAME!"
    set "B_VAULT_JSON=!B_TIMESTAMP_DIR!\!B_NAME!.json"
    set "B_ORG_JSON=!B_TIMESTAMP_DIR!\organization.json"
    set "B_ATTACHMENT_PATH=!B_TIMESTAMP_DIR!\attachments"
    set "B_DEBUG_PATH=!B_TIMESTAMP_DIR!\debug"
    set "B_MASTER_PW=!%%V_MASTER_PW!"
    set "BW_CLIENTID=!%%V_CLIENTID!"
    set "BW_CLIENTSECRET=!%%V_CLIENTSECRET!"
    if not exist "!B_DEBUG_PATH!" mkdir "!B_DEBUG_PATH!"  || goto error-exit

    @echo Logging in to Bitwarden as !B_NAME! using API credentials.
    bw login --apikey --raw
    if errorlevel 1 goto error-exit
    rem Clear any session token carried over from the previous vault
    set "BW_SESSION="
    for /f %%i in ('bw unlock --passwordenv B_MASTER_PW --raw 2^>nul') do set BW_SESSION=%%i
    if not defined BW_SESSION (
        @echo Failed to unlock Bitwarden. Invalid PW?
        goto error-exit
    )
    @echo Synchronizing vault.
    bw sync --session !BW_SESSION!
    if errorlevel 1 goto error-exit
    @echo(
    if not exist "!B_TIMESTAMP_DIR!" mkdir "!B_TIMESTAMP_DIR!" || goto error-exit
    @echo Export !B_NAME! vault.
    bw export --output "!B_VAULT_JSON!" --format json --session !BW_SESSION!
    if errorlevel 1 goto error-exit
    @echo(
    @echo Export attachments...please wait
    if not exist "!B_ATTACHMENT_PATH!" mkdir "!B_ATTACHMENT_PATH!" || goto error-exit
    rem Dump items once
	bw list items --session !BW_SESSION! > "!B_DEBUG_PATH!\items_!B_NAME!.json"
    if errorlevel 1 goto error-exit
    rem Build a pipe-delimited list: itemId|||attachmentId|||fileName
    jq -r ".[] | select(.attachments) | .id as $itemid | .attachments[] | ($itemid + \"~\" + .id + \"~\" + .fileName)" ^
      "!B_DEBUG_PATH!\items_!B_NAME!.json" > "!B_DEBUG_PATH!\attlist_!B_NAME!.txt"
    if errorlevel 1 goto error-exit

    rem Download attachments
	
	for /f "usebackq tokens=1,2,* delims=~" %%I in ("!B_DEBUG_PATH!\attlist_!B_NAME!.txt") do (
        set "ITEMID=%%I"
        set "ATTID=%%J"
        set "FNAME=%%K"
        if not exist "!B_ATTACHMENT_PATH!\!ITEMID!" mkdir "!B_ATTACHMENT_PATH!\!ITEMID!" || goto error-exit
        bw get attachment !ATTID! --itemid !ITEMID! --session !BW_SESSION! --output "!B_ATTACHMENT_PATH!\!ITEMID!\!FNAME!"
        @echo(	
        if errorlevel 1 goto error-exit
    )
    @echo(
    rem ---- Verify this vault's export ----
    set "V_ITEMS="
    for /f "usebackq delims=" %%N in (`jq -r ".items | length" "!B_VAULT_JSON!" 2^>nul`) do set "V_ITEMS=%%N"
    if not defined V_ITEMS set "V_ITEMS=0"
    if !V_ITEMS! gtr 0 (
        @echo Verify !B_NAME!: !V_ITEMS! items in export.
    ) else (
        @echo VERIFY FAIL: !B_NAME!.json missing, unreadable, or empty.
        set "VERIFY_ERROR=1"
    )
    set /a ATT_EXPECT=0
    set /a ATT_FOUND=0
    for /f "usebackq tokens=1,2,* delims=~" %%I in ("!B_DEBUG_PATH!\attlist_!B_NAME!.txt") do (
        set /a ATT_EXPECT+=1
        if exist "!B_ATTACHMENT_PATH!\%%I\%%K" set /a ATT_FOUND+=1
    )
    if !ATT_FOUND! equ !ATT_EXPECT! (
        @echo Verify !B_NAME!: !ATT_FOUND! of !ATT_EXPECT! attachments present.
    ) else (
        @echo VERIFY FAIL: !B_NAME! attachments - expected !ATT_EXPECT!, found !ATT_FOUND!.
        set "VERIFY_ERROR=1"
    )
    @echo(
    if !count! equ 1 (
        if defined ORGANIZATION_ID (
            @echo Export organization vault.
			bw export --output "!B_ORG_JSON!" --format json --organizationid %ORGANIZATION_ID% --session !BW_SESSION!
            if errorlevel 1 goto error-exit
            @echo(
    )
    )
    bw logout
    if errorlevel 1 goto error-exit
@echo(
)
@echo(
if "!VERIFY_ERROR!"=="1" (
    @echo *** VERIFICATION FAILED - see VERIFY FAIL messages above. Do not trust this backup. ***
    goto error-exit
)
@echo Verification passed - item and attachment counts as expected.
@echo All listed vaults and their attachments exported. To exit,
endlocal
goto terminate
:abort-preflight
@echo(
@echo Aborted before export. Nothing was written.
goto terminate
:error-exit
@echo(
@echo Error. Review/correct/try again.
bw logout
:terminate
endlocal
:: remove this if you always run at command line and not double-click bat file.
@echo(
pause
