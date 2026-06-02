@echo off
REM Robust setup script for GitHub CLI and Copilot CLI in VS Code terminals
REM Locates gh.exe, adds its folder to PATH for the session, creates aliases, and verifies installation.

echo Setting up GitHub CLI and Copilot CLI...

REM Try to locate gh.exe in common install locations first
set "GH_PATH="
for %%I in ("C:\Program Files\GitHub CLI\gh.exe" "C:\Program Files (x86)\GitHub CLI\gh.exe") do (
  if exist %%~I set "GH_PATH=%%~I"
)

REM If not found, try where to locate gh in PATH
if not defined GH_PATH (
  for /f "usebackq delims=" %%P in (`where gh 2^>nul`) do if exist "%%P" set "GH_PATH=%%P"
)

if not defined GH_PATH (
  echo GitHub CLI (gh.exe) not found in common locations or PATH.
  echo Please install GitHub CLI: https://cli.github.com/
  goto :EOF
)

REM Add containing folder to PATH for current session
for %%F in ("%GH_PATH%") do set "GH_DIR=%%~dpF"
set "PATH=%GH_DIR%;%PATH%"

REM Create doskey aliases
doskey gh="%GH_PATH%" $*
doskey copilot="%GH_PATH%" copilot $*

REM Verify installations
echo.
echo === GitHub CLI Status ===
"%GH_PATH%" --version

echo.
echo === Copilot CLI Status ===
"%GH_PATH%" copilot --version

echo.
echo Setup complete! You can now use:
echo   - 'gh' for GitHub CLI commands
echo   - 'copilot' for Copilot CLI commands
echo.
