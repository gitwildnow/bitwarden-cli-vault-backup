@echo off
setlocal enabledelayedexpansion
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
set "B_TIMESTAMP=%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%"
:: Replace leading space in hour with zero
set "B_TIMESTAMP=%B_TIMESTAMP: =0%"
set B_TIMESTAMP_DIR=%B_OUTPUT_PARENT%\exp_%B_TIMESTAMP%
@echo This script saves unencrypted json exports of the Bitwarden vaults.
@echo (target only encrypted media such as VeraCrypt volume)
@echo Exports will be written to a new...
@echo %B_TIMESTAMP_DIR%
@echo Checking for pending updates to the CLI...
rem Show the configured server endpoint (helps avoid wrong .com/.edu/etc)
for /f "usebackq delims=" %%S in (`bw config server 2^>nul`) do set "BW_SERVER_DISPLAY=%%S"
if defined BW_SERVER_DISPLAY (
    echo Bitwarden server: %BW_SERVER_DISPLAY%
) else (
    echo Bitwarden server: (unable to determine)
)
bw update
@echo(
@echo Please ctrl-c/abort and apply update if pending.
@echo https://bitwarden.com/help/cli/
pause
bw logout
@echo(
:: Loop thru each vault to export
set "count=0"
for %%V in (%B_VAULTS%) do (
    set /a count+=1
    set B_NAME=!%%V_NAME!
    set B_VAULT_JSON=!B_TIMESTAMP_DIR!\!B_NAME!.json
    set B_ORG_JSON=!B_TIMESTAMP_DIR!\organization.json
    set B_ATTACHMENT_PATH=!B_TIMESTAMP_DIR!\attachments
    set B_DEBUG_PATH=!B_TIMESTAMP_DIR!\debug
    if not exist !B_DEBUG_PATH! mkdir !B_DEBUG_PATH!
    set B_MASTER_PW=!%%V_MASTER_PW!
    set BW_CLIENTID=!%%V_CLIENTID!
    set BW_CLIENTSECRET=!%%V_CLIENTSECRET!
    @echo Logging in to Bitwarden as !B_NAME! using API credentials.
    bw login --apikey --raw
    if errorlevel 1 goto error-exit
    for /f %%i in ('bw unlock !B_MASTER_PW! --raw 2^>nul') do set BW_SESSION=%%i
    if not defined BW_SESSION (
        @echo Failed to unlock Bitwarden. Invalid PW?
        goto error-exit
    )
    @echo Synchronizing vault.
    bw sync --session !BW_SESSION!
    if errorlevel 1 goto error-exit
    @echo(
    if not exist !B_TIMESTAMP_DIR! mkdir !B_TIMESTAMP_DIR!
    if errorlevel 1 goto error-exit
    @echo Export !B_NAME! vault.
    bw export --output "!B_VAULT_JSON!" --format json --session !BW_SESSION!
    if errorlevel 1 goto error-exit
    @echo(
    @echo Export attachments...please wait
    if not exist !B_ATTACHMENT_PATH! mkdir !B_ATTACHMENT_PATH!
    if errorlevel 1 goto error-exit
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
        if not exist "!B_ATTACHMENT_PATH!\!ITEMID!" mkdir "!B_ATTACHMENT_PATH!\!ITEMID!"
        bw get attachment !ATTID! --itemid !ITEMID! --session !BW_SESSION! --output "!B_ATTACHMENT_PATH!\!ITEMID!\!FNAME!"
        @echo(	
        if errorlevel 1 goto error-exit
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
@echo All listed vaults and their attachments exported. To exit,
goto terminate
:error-exit
@echo(
@echo Error. Review/correct/try again.
bw logout
:terminate
endlocal
:: remove this if you always run at command line and not double-click bat file.
pause
