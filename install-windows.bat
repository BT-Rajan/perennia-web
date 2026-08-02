@echo off
REM ============================================================
REM PERENNIA PRODUCTION - WINDOWS INSTALLER
REM ============================================================
REM This script sets up Perennia on Windows
REM Requires: Windows 7+ and internet connection

setlocal enabledelayedexpansion
color 0A
title Perennia Production - Windows Installer

echo.
echo ============================================================
echo  PERENNIA PRODUCTION - WINDOWS INSTALLER
echo ============================================================
echo.
echo This installer will:
echo   1. Check Python installation
echo   2. Install Python (if needed)
echo   3. Create virtual environment
echo   4. Install Python dependencies
echo   5. Create data directories
echo   6. Configure application
echo.
pause

REM ============================================================
REM Step 1: Check Python Installation
REM ============================================================

echo.
echo [1/6] Checking Python installation...
python --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: Python not found!
    echo.
    echo Download Python from: https://www.python.org/downloads/
    echo.
    echo Important: Check "Add Python to PATH" during installation!
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('python --version') do set PYTHON_VERSION=%%i
echo OK - %PYTHON_VERSION% is installed

REM ============================================================
REM Step 2: Check pip
REM ============================================================

echo.
echo [2/6] Checking pip installation...
pip --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: pip not found!
    echo Please reinstall Python with pip enabled.
    echo.
    pause
    exit /b 1
)
echo OK - pip is available

REM ============================================================
REM Step 3: Create Virtual Environment
REM ============================================================

echo.
echo [3/6] Creating Python virtual environment...
if exist venv (
    echo Virtual environment already exists, skipping...
) else (
    python -m venv venv
    if errorlevel 1 (
        echo.
        echo ERROR: Failed to create virtual environment
        echo.
        pause
        exit /b 1
    )
    echo OK - Virtual environment created
)

REM ============================================================
REM Step 4: Activate Virtual Environment and Install Dependencies
REM ============================================================

echo.
echo [4/6] Installing Python dependencies...
call venv\Scripts\activate.bat
if errorlevel 1 (
    echo.
    echo ERROR: Failed to activate virtual environment
    echo.
    pause
    exit /b 1
)

pip install --upgrade pip >nul 2>&1
pip install -r requirements.txt
if errorlevel 1 (
    echo.
    echo ERROR: Failed to install dependencies
    echo.
    echo Try running manually:
    echo   venv\Scripts\activate.bat
    echo   pip install -r requirements.txt
    echo.
    pause
    exit /b 1
)
echo OK - Dependencies installed

REM ============================================================
REM Step 5: Create Data Directories
REM ============================================================

echo.
echo [5/6] Setting up data directories...

if not exist data mkdir data
if not exist data\uploads mkdir data\uploads
if not exist public\static\images mkdir public\static\images

REM Create empty config if doesn't exist
if not exist data\config.json (
    echo Creating default configuration...
    (
        echo {
        echo   "provider": "anthropic",
        echo   "model": "claude-sonnet-4-6",
        echo   "baseUrl": "",
        echo   "apiKeyEncrypted": "",
        echo   "tone": "",
        echo   "knowledge": {},
        echo   "contact": {
        echo     "ct-email": "info@perennia.com",
        echo     "ct-phone": "+965 0000 0000",
        echo     "ct-addr-en": "Kuwait",
        echo     "ct-addr-ar": "الكويت"
        echo   },
        echo   "landing": {
        echo     "welcomeText-en": "Welcome to Perennia",
        echo     "welcomeText-ar": "مرحبا بك في بيرينيا",
        echo     "tagline-en": "Visit our V-Lounge for more",
        echo     "tagline-ar": "زر V-Lounge الخاص بنا لمزيد من المعلومات",
        echo     "ourWorkUrl": "",
        echo     "contactUrl": ""
        echo   },
        echo   "booking": {
        echo     "enabled": true,
        echo     "promptsEn": [
        echo       "Would you like me to schedule a call with our Growth Strategist?",
        echo       "Shall I book an appointment with our Growth Strategist for you?",
        echo       "Interested in speaking with our Growth Strategist? I can set that up.",
        echo       "Want to chat with our Growth Strategist? I can book a time.",
        echo       "Would a call with our Growth Strategist be helpful?"
        echo     ],
        echo     "promptsAr": [
        echo       "هل تود لي أن أحجز لك موعداً مع خبيرنا في النمو؟",
        echo       "هل تود لي أن أحجز لك مكالمة مع خبيرنا في النمو؟",
        echo       "هل تود التحدث مع خبيرنا في النمو؟ يمكنني ترتيب ذلك.",
        echo       "هل مكالمة مع خبيرنا في النمو مفيدة لك؟",
        echo       "هل ترغب في جدولة موعد مع خبيرنا في النمو؟"
        echo     ]
        echo   }
        echo }
    ) > data\config.json
    echo OK - Config created
)

echo OK - Directories ready

REM ============================================================
REM Step 6: Installation Complete
REM ============================================================

echo.
echo ============================================================
echo  INSTALLATION COMPLETE!
echo ============================================================
echo.
echo Next steps:
echo.
echo 1. CONFIGURE API KEY (Required):
echo    - Edit: data/config.json
echo    - Add your Anthropic API key
echo    - Save the file
echo.
echo 2. START THE APPLICATION:
echo    - Run: start-server.bat (double-click)
echo    OR
echo    - Manual: venv\Scripts\activate.bat
echo              uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
echo.
echo 3. OPEN IN BROWSER:
echo    - Visit: http://localhost:8000
echo.
echo 4. ADMIN PANEL:
echo    - Visit: http://localhost:8000/admin
echo.
echo For help or issues:
echo   - Check: README.md
echo   - Email: support@perennia.com
echo.
pause
exit /b 0
