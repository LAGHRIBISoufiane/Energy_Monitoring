@echo off
REM Save OCP Logo Script
REM This script will help save the OCP logo to the correct location

SETLOCAL ENABLEDELAYEDEXPANSION

SET "LOGO_DIR=C:\Users\riosh\Documents\Energy_Monitoring\kofert_dashboard\assets\images"
SET "LOGO_FILE=%LOGO_DIR%\ocp_logo.png"

ECHO.
ECHO ========================================
ECHO OCP Logo Save Instructions
ECHO ========================================
ECHO.
ECHO Target Location:
ECHO %LOGO_FILE%
ECHO.
ECHO Directory Status:
IF EXIST "%LOGO_DIR%" (
    ECHO [OK] Directory exists
) ELSE (
    ECHO [ERROR] Directory not found
    ECHO Creating directory...
    MKDIR "%LOGO_DIR%"
)

ECHO.
ECHO Current files in assets/images/:
DIR "%LOGO_DIR%"

ECHO.
ECHO ========================================
ECHO MANUAL SAVE STEPS:
ECHO ========================================
ECHO.
ECHO 1. Right-click the OCP logo image from the chat
ECHO 2. Select "Save image as..."
ECHO 3. Navigate to: %LOGO_DIR%
ECHO 4. Name it: ocp_logo.png
ECHO 5. Click Save
ECHO.
ECHO THEN run:
ECHO cd kofert_dashboard
ECHO flutter run -d edge
ECHO.
PAUSE
