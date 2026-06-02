@echo off
REM Launch VS Code with GitHub CLI and Copilot CLI automatically configured
REM This script ensures GitHub CLI is in PATH before VS Code starts

setlocal enabledelayedexpansion

REM Add GitHub CLI to PATH permanently (in session)
set "PATH=C:\Program Files\GitHub CLI;!PATH!"

REM Launch VS Code with the configured environment
start "" code.cmd %*
