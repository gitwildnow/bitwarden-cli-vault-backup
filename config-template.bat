@echo off
rem ============================================================
rem Bitwarden Backup Configuration
rem
rem *** STORE THIS FILE ONLY ON ENCRYPTED MEDIA (e.g. VeraCrypt) ***
rem
rem This file is called by backupBitwarden.bat and defines
rem all configuration and secret variables.
rem
rem ============================================================

rem B_OUTPUT_PARENT
rem   Parent directory where exports will be written.
rem   Example: V:\bwExports
set "B_OUTPUT_PARENT=V:\bwExports"

rem ORGANIZATION_ID
rem   Optional. Required if exporting organization vault.
rem   Obtain via:
rem     bw login
rem     bw list organizations --session <session_id>
set "ORGANIZATION_ID="

rem B_VAULTS
rem   Space-separated symbolic vault names.
rem   Example: H W
set "B_VAULTS=H W"

rem ============================================================
rem Vault-Specific Configuration
rem
rem Each vault must define:
rem   ?_NAME
rem   ?_CLIENTID
rem   ?_CLIENTSECRET
rem   ?_MASTER_PW
rem
rem Replace ? with your vault prefix (H, W, etc.)
rem ============================================================
rem ------------------------------------------------------------
rem API Client ID and Client Secret
rem
rem These values come from your Bitwarden Personal API Key.
rem
rem How to generate:
rem   1. Log in to the Bitwarden Web Vault.
rem   2. Click your profile icon (top right).
rem   3. Go to Account Settings → Security → Keys.
rem   4. Create a "Personal API Key".
rem   5. Copy the Client ID and Client Secret shown.
rem
rem Official documentation:
rem   https://bitwarden.com/help/personal-api-key/
rem
rem IMPORTANT:
rem   - These are NOT your email address.
rem   - These are NOT your master password.
rem   - Keep these values private.
rem   - Store this config file only on encrypted media.
rem ------------------------------------------------------------

rem ----- Vault H -----
set "H_NAME=YourNameHere"
set "H_CLIENTID="
set "H_CLIENTSECRET="
set "H_MASTER_PW="

rem ----- Vault W -----
set "W_NAME=OtherVaultName"
set "W_CLIENTID="
set "W_CLIENTSECRET="
set "W_MASTER_PW="

rem ============================================================
rem End of configuration
rem ============================================================


