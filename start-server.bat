@echo off
REM ============================================================
REM PERENNIA PRODUCTION - START SERVER
REM ============================================================
REM This script starts the Perennia server on Windows

setlocal enabledelayedexpansion
color 0B
title Perennia Production Server

echo.
echo ============================================================
echo  PERENNIA PRODUCTION - SERVER
echo ============================================================
echo.

REM Check if virtual environment exists
if not exist venv (
    echo ERROR: Virtual environment not found!
    echo.
    echo Please run install-windows.bat first
    echo.
    pause
    exit /b 1
)

REM Activate virtual environment
echo Activating Python environment...
call venv\Scripts\activate.bat

REM Check if API key is configured
if not exist data\config.json (
    echo WARNING: config.json not found!
    echo Please configure your API key first.
    pause
    exit /b 1
)

REM Start the server
echo.
echo ============================================================
echo  Server Starting...
echo ============================================================
echo.
echo If this is your first time, please wait for startup messages
echo.
echo Access the application at:
echo   http://localhost:8000
echo.
echo Admin panel at:
echo   http://localhost:8000/admin
echo.
echo Press Ctrl+C to stop the server
echo.
echo ============================================================
echo.

REM Start uvicorn server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

if errorlevel 1 (
    echo.
    echo ERROR: Failed to start server
    echo.
    echo Troubleshooting:
    echo   1. Check if Python is installed: python --version
    echo   2. Check dependencies: pip install -r requirements.txt
    echo   3. Verify config.json exists and is valid JSON
    echo.
    pause
    exit /b 1
)

pause
