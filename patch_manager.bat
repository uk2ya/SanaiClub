@echo off
REM ============================================================================
REM  Patch Manager Batch Script
REM  - Modes: patch / rollback
REM  - Backs up existing modules into timestamped folders and applies/rolls back
REM    patch files that share the same file names.
REM ============================================================================

REM -----------------------
REM User configuration
REM -----------------------
set "PATCH_SOURCE=C:\\path\\to\\prepared\\patches"
set "TARGET_PATH=C:\\Program Files (x86)\\Unidocs\\ezPDFWorkflow3\\GenPDF"
set "BACKUP_ROOT=C:\\Program Files (x86)\\Unidocs\\ezPDFWorkflow3\\GenPDF\\Backup"
set "MODULE_NAME=GenPDF"
REM Space-separated file names that should be patched.
set "FILE_LIST=GenPDFModule.dll AnotherModule.dll"

REM Optional log file (placed next to the batch file). Leave empty to disable logging.
set "LOG_FILE=%~dp0patch_manager.log"

REM Require administrator privileges; relaunch elevated if needed.
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Requesting administrative privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs" 2>nul
    exit /b
)

setlocal enabledelayedexpansion

REM -----------------------
REM Helpers
REM -----------------------
:log
if not defined LOG_FILE goto :eof
echo [%date% %time%] %~1>>"%LOG_FILE%"
goto :eof

:usage
echo Usage: %~nx0 ^<patch^|rollback^> [restore_date]
echo    patch    : Backup existing files and copy patch files from %PATCH_SOURCE%
echo    rollback : Restore files from the most recent or specified backup folder
echo    restore_date (optional for rollback) examples:
echo        20240823             ^(daily folder^)
echo        20240823\142233      ^(time subfolder inside the day folder^)
echo.
echo Or simply double-click the batch file to choose an option from the menu.
exit /b 1

:menu
echo ============================================
echo   Patch Manager
echo ============================================
echo   1: Patch
echo   2: Rollback (latest backup)
echo   3: Exit
echo ============================================
set /p MENU_CHOICE=Select an option ^(1-3^):

if "%MENU_CHOICE%"=="1" (
    set "MODE=PATCH"
    goto :menu_after_choice
)

if "%MENU_CHOICE%"=="2" (
    set "MODE=ROLLBACK"
    set "RESTORE_DATE="
    goto :menu_after_choice
)

if "%MENU_CHOICE%"=="3" (
    echo Exiting.
    exit /b 0
)

echo Invalid choice. Please try again.
echo.
goto :menu

:menu_after_choice
goto :entry_continue

REM -----------------------
REM Entry
REM -----------------------
if "%~1"=="/?" goto :usage
set "MODE="
set "RESTORE_DATE="

if "%~1"=="" goto :menu

set "MODE=%~1"
set "RESTORE_DATE=%~2"

:entry_continue

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set "TODAY=%%i"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format HHmmss"') do set "NOW=%%i"

set "BACKUP_DAY_DIR=%BACKUP_ROOT%\%MODULE_NAME%\%TODAY%"
set "BACKUP_DIR=%BACKUP_DAY_DIR%"
if exist "%BACKUP_DAY_DIR%" set "BACKUP_DIR=%BACKUP_DAY_DIR%\%NOW%"

call :log "===== Starting %MODE% ====="
call :log "PATCH_SOURCE=%PATCH_SOURCE%"
call :log "TARGET_PATH=%TARGET_PATH%"
call :log "BACKUP_ROOT=%BACKUP_ROOT%"
call :log "FILE_LIST=%FILE_LIST%"

if /i "%MODE%"=="PATCH" goto :patch
if /i "%MODE%"=="ROLLBACK" goto :rollback

echo [ERROR] Unknown mode: %MODE%
call :log "Unknown mode: %MODE%"
exit /b 1

REM -----------------------
REM Patch mode
REM -----------------------
:patch
echo [INFO] Running PATCH mode...

REM Verify patch files exist
for %%F in (%FILE_LIST%) do (
    if not exist "%PATCH_SOURCE%\%%F" (
        echo [ERROR] Patch file not found: %PATCH_SOURCE%\%%F
        call :log "Missing patch file: %PATCH_SOURCE%\%%F"
        exit /b 1
    )
)

echo [INFO] Creating backup folder: %BACKUP_DIR%
call :log "Creating backup folder: %BACKUP_DIR%"
mkdir "%BACKUP_DIR%" >nul 2>&1

set "SKIP_BACKUP=0"
for %%F in (%FILE_LIST%) do (
    if exist "%TARGET_PATH%\%%F" (
        move /Y "%TARGET_PATH%\%%F" "%BACKUP_DIR%" >nul
        if errorlevel 1 (
            echo [ERROR] Backup failed for %%F
            call :log "Backup failed for %%F"
            exit /b 1
        ) else (
            echo [INFO] Backed up %%F
            call :log "Backed up %%F to %BACKUP_DIR%"
        )
    ) else (
        echo [WARN] Target file not found: %%F
        call :log "Target missing, prompt for patch: %%F"
        if "%~2"=="/Y" (
            echo [INFO] Proceeding without backup for %%F (auto-yes)
        ) else (
            set /p USERCHOICE=Proceed without backup for %%F? (y/N): 
            if /i not "!USERCHOICE!"=="Y" (
                echo [INFO] Skipping patch.
                call :log "User aborted due to missing target %%F"
                exit /b 1
            )
        )
        set "SKIP_BACKUP=1"
    )
)

REM Apply patch files
for %%F in (%FILE_LIST%) do (
    copy /Y "%PATCH_SOURCE%\%%F" "%TARGET_PATH%" >nul
    if errorlevel 1 (
        echo [ERROR] Patch copy failed for %%F
        call :log "Patch copy failed for %%F"
        exit /b 1
    ) else (
        echo [INFO] Patched %%F
        call :log "Patched %%F"
    )
)

echo [SUCCESS] Patch completed. Backup: %BACKUP_DIR%
call :log "Patch completed successfully. Backup=%BACKUP_DIR%"
exit /b 0

REM -----------------------
REM Rollback mode
REM -----------------------
:rollback
echo [INFO] Running ROLLBACK mode...

if not defined RESTORE_DATE (
    echo [INFO] Selecting most recent backup folder...
    for /f "delims=" %%D in ('dir "%BACKUP_ROOT%\%MODULE_NAME%" /ad /b /o-n') do (
        if not defined RESTORE_DATE set "RESTORE_DATE=%%D"
    )
)

if not defined RESTORE_DATE (
    echo [ERROR] No backup folders found under %BACKUP_ROOT%\%MODULE_NAME%
    call :log "Rollback failed: no backups"
    exit /b 1
)

set "RESTORE_DIR=%BACKUP_ROOT%\%MODULE_NAME%\%RESTORE_DATE%"

if not exist "%RESTORE_DIR%" (
    echo [ERROR] Restore folder not found: %RESTORE_DIR%
    call :log "Restore folder missing: %RESTORE_DIR%"
    exit /b 1
)

REM If a day folder contains time-based subfolders, pick the newest one automatically.
set "SELECTED_TIME="
set "HAS_SUBLEVEL="
echo %RESTORE_DATE%|findstr "\\">nul && set "HAS_SUBLEVEL=1"

if not defined HAS_SUBLEVEL (
    if exist "%RESTORE_DIR%" (
        dir "%RESTORE_DIR%" /ad /b >nul 2>&1
        if not errorlevel 1 (
            for /f "delims=" %%T in ('dir "%RESTORE_DIR%" /ad /b /o-n') do (
                if not defined SELECTED_TIME set "SELECTED_TIME=%%T"
            )
            if defined SELECTED_TIME set "RESTORE_DIR=%RESTORE_DIR%\%SELECTED_TIME%"
        )
    )
)

echo [INFO] Restoring from %RESTORE_DIR%
call :log "Restoring from %RESTORE_DIR%"

for %%F in (%FILE_LIST%) do (
    if not exist "%RESTORE_DIR%\%%F" (
        echo [WARN] Backup file missing for %%F in %RESTORE_DIR%
        call :log "Missing backup file: %RESTORE_DIR%\%%F"
    ) else (
        copy /Y "%RESTORE_DIR%\%%F" "%TARGET_PATH%" >nul
        if errorlevel 1 (
            echo [ERROR] Rollback failed while copying %%F
            call :log "Rollback failed for %%F"
            exit /b 1
        ) else (
            echo [INFO] Restored %%F
            call :log "Restored %%F"
        )
    )
)

echo [SUCCESS] Rollback completed from backup %RESTORE_DATE%
call :log "Rollback completed successfully from %RESTORE_DATE%"
exit /b 0
