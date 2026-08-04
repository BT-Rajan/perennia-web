@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

REM ============================================================
REM  Perennia -- Windows Installer
REM
REM  Safe to re-run: existing secrets in .env are preserved unless
REM  --force is passed, so re-running this to pick up a code update
REM  does NOT invalidate admin sessions, the admin password, or the
REM  encrypted LLM API key.
REM
REM  Usage:
REM    installer.bat
REM    installer.bat --port 8080
REM    installer.bat --admin-username admin --admin-password "MyPass123!"
REM    installer.bat --force
REM ============================================================

set "APP_HOST=127.0.0.1"
set "APP_PORT=8001"
set "PORT_EXPLICIT="
set "ADMIN_USERNAME=admin"
set "ADMIN_PASSWORD="
set "FORCE_FLAG="

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--port" (
    set "APP_PORT=%~2"
    set "PORT_EXPLICIT=--port-explicit"
    shift & shift
    goto parse_args
)
if /i "%~1"=="--host" (
    set "APP_HOST=%~2"
    shift & shift
    goto parse_args
)
if /i "%~1"=="--admin-username" (
    set "ADMIN_USERNAME=%~2"
    shift & shift
    goto parse_args
)
if /i "%~1"=="--admin-password" (
    set "ADMIN_PASSWORD=%~2"
    shift & shift
    goto parse_args
)
if /i "%~1"=="--force" (
    set "FORCE_FLAG=--force"
    shift
    goto parse_args
)
if /i "%~1"=="/?" goto show_help
if /i "%~1"=="--help" goto show_help
echo Unknown option: %~1
goto show_help

:show_help
echo Usage: installer.bat [--port 8001] [--host 127.0.0.1] [--admin-username admin]
echo                       [--admin-password "your-password"] [--force]
exit /b 1

:args_done

echo.
echo ============================================================
echo                 PERENNIA INSTALLER
echo ============================================================
echo.
echo Directory : %CD%
echo Host      : %APP_HOST%
echo Port      : %APP_PORT%
echo.

REM ============================================================
echo [1/5] Checking Python installation...
REM ============================================================

set "PYTHON_CMD="

python --version >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=2" %%v in ('python --version 2^>^&1') do set "PY_DETECTED=%%v"
    echo !PY_DETECTED! | findstr /r "^3\." >nul
    if not errorlevel 1 set "PYTHON_CMD=python"
)

if not defined PYTHON_CMD (
    py -3 --version >nul 2>&1
    if not errorlevel 1 set "PYTHON_CMD=py -3"
)

if not defined PYTHON_CMD (
    echo.
    echo ============================================================
    echo   ERROR: Python was not found ^(or the "python" command only
    echo   opens the Microsoft Store -- this happens when Python isn't
    echo   actually installed yet^).
    echo ============================================================
    echo.
    echo   1. Download Python from: https://www.python.org/downloads/
    echo   2. Run the installer and CHECK "Add python.exe to PATH"
    echo   3. Click "Install Now", then close and reopen this window
    echo   4. If "python" still opens the Store afterward: open
    echo      Settings ^> Apps ^> Advanced app settings ^> App execution
    echo      aliases, and turn OFF the "python.exe"/"python3.exe"
    echo      entries pointing at the Store, then try again.
    echo   5. Re-run installer.bat
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('%PYTHON_CMD% --version 2^>^&1') do echo   Found: %%v

for /f "tokens=2" %%v in ('%PYTHON_CMD% --version 2^>^&1') do set "PY_FULL_VER=%%v"
for /f "tokens=1,2 delims=." %%a in ("!PY_FULL_VER!") do (
    set "PY_MAJOR=%%a"
    set "PY_MINOR=%%b"
)
set "PY_VERSION_OK=1"
if !PY_MAJOR! LSS 3 set "PY_VERSION_OK=0"
if !PY_MAJOR! EQU 3 if !PY_MINOR! LSS 10 set "PY_VERSION_OK=0"

if "!PY_VERSION_OK!"=="0" (
    echo.
    echo   ERROR: Python 3.10 or newer is required ^(found !PY_FULL_VER!^). Please
    echo   upgrade Python from https://www.python.org/downloads/ and re-run
    echo   this installer.
    echo.
    pause
    exit /b 1
)
echo   OK - Python version is compatible.
echo.

REM ============================================================
echo [2/5] Creating virtual environment...
REM ============================================================

if not exist "venv\Scripts\python.exe" (
    %PYTHON_CMD% -m venv venv
    if errorlevel 1 (
        echo.
        echo   ERROR: Could not create the virtual environment.
        echo   Try running this window as Administrator and re-running
        echo   installer.bat.
        echo.
        pause
        exit /b 1
    )
    echo   OK - Virtual environment created in .\venv
) else (
    echo   OK - Virtual environment already exists, reusing it.
)
echo.

set "VENV_PY=%CD%\venv\Scripts\python.exe"

REM ============================================================
echo [3/5] Installing Python packages ^(this can take a few minutes^)...
REM ============================================================

"%VENV_PY%" -m pip install --upgrade pip --quiet
if errorlevel 1 (
    echo   WARNING: Could not upgrade pip -- continuing anyway.
)

if not exist "requirements.txt" (
    echo   ERROR: requirements.txt not found in %CD%.
    echo   Make sure you extracted the full project folder, not just this file.
    pause
    exit /b 1
)

"%VENV_PY%" -m pip install -r requirements.txt
if errorlevel 1 (
    echo.
    echo ============================================================
    echo   ERROR: Installing dependencies failed.
    echo ============================================================
    echo.
    echo   Things to try:
    echo     1. Check your internet connection
    echo     2. Temporarily disable antivirus / Windows Defender real-time
    echo        protection, which sometimes blocks pip mid-download
    echo     3. Re-run this window as Administrator
    echo     4. Try the manual install:
    echo          venv\Scripts\activate.bat
    echo          pip install -r requirements.txt
    echo.
    pause
    exit /b 1
)
echo   OK - Dependencies installed.
echo.

REM ============================================================
echo [4/5] Creating data directories...
REM ============================================================

if not exist "data" mkdir "data"
if not exist "logs" mkdir "logs"
if not exist "public\static\images" mkdir "public\static\images"
echo   OK - Directories ready.
echo.

REM ============================================================
echo [5/5] Generating configuration and startup script ^(.env^)...
REM ============================================================

set "PW_FILE=%TEMP%\perennia_admin_password_%RANDOM%.tmp"
set "STATUS_FILE=%TEMP%\perennia_env_status_%RANDOM%.tmp"
if exist "%PW_FILE%" del /f /q "%PW_FILE%" >nul 2>&1
if exist "%STATUS_FILE%" del /f /q "%STATUS_FILE%" >nul 2>&1

"%VENV_PY%" scripts\win_env_setup.py --host "%APP_HOST%" --port "%APP_PORT%" %PORT_EXPLICIT% --admin-username "%ADMIN_USERNAME%" --admin-password "%ADMIN_PASSWORD%" %FORCE_FLAG% --out-password-file "%PW_FILE%" --status-file "%STATUS_FILE%"

if errorlevel 1 (
    echo   ERROR: Failed to generate .env -- see the error above.
    pause
    exit /b 1
)

if not exist "%STATUS_FILE%" (
    echo   ERROR: .env generation did not report status -- something went wrong.
    pause
    exit /b 1
)
for /f "usebackq tokens=1,2 delims==" %%A in ("%STATUS_FILE%") do set "%%A=%%B"
del /f /q "%STATUS_FILE%" >nul 2>&1

set "GENERATED_PASSWORD="
if exist "%PW_FILE%" (
    set /p GENERATED_PASSWORD=<"%PW_FILE%"
    del /f /q "%PW_FILE%" >nul 2>&1
)

echo   OK - .env written ^(existing secrets preserved unless invalid or --force was used^).
if /i "%REGENERATED%"=="yes" (
    echo   NOTE: SECRET_KEY, ENCRYPTION_KEY and/or ADMIN_PASSWORD_HASH were
    echo   ^(re^)generated -- either --force was used, or no valid existing
    echo   .env was found. Any previous admin session is now invalid, and
    echo   a previously saved LLM API key can no longer be decrypted.
)
if not exist "start-server.bat" (
    echo   ERROR: start-server.bat was not created -- something went wrong
    echo   generating configuration. Check the output above for errors.
    pause
    exit /b 1
)
echo   OK - start-server.bat ready.
echo.

REM ============================================================
echo ============================================================
echo               INSTALLATION COMPLETE
echo ============================================================
echo.
echo Directory : %CD%
echo Local URL : http://%HOST%:%PORT%
echo Admin URL : http://%HOST%:%PORT%/admin
echo Username  : %ADMIN_USERNAME%
if defined GENERATED_PASSWORD (
    echo Password  : %GENERATED_PASSWORD%   ^(auto-generated -- shown once, save it now^)
) else (
    echo Password  : unchanged from a previous install ^(not shown^).
    echo             Use --force with --admin-password to reset it, or
    echo             use "Forgot password?" on the /admin login page.
)
echo.
echo This has also been written to admin_access.secret in this folder
echo the first time the server starts, as a local reference copy.
echo.
echo Next steps:
echo   1. Double-click start-server.bat to start Perennia
echo   2. Open http://%HOST%:%PORT% in your browser
echo   3. Go to http://%HOST%:%PORT%/admin to add your Anthropic API key
echo.
echo This install is HTTP-only and bound to %HOST% ^(not exposed to
echo your network or the internet^). Put a reverse proxy with HTTPS in
echo front of it before exposing it more broadly, and set
echo COOKIE_SECURE=true in .env once you do.
echo.

set /p START_NOW="Start the server now? [Y/N]: "
if /i "%START_NOW%"=="Y" (
    call start-server.bat
) else (
    echo.
    echo OK -- run start-server.bat whenever you're ready.
    pause
)

endlocal
