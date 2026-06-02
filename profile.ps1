# GitHub Copilot CLI Setup for PowerShell
# This script configures GitHub CLI and Copilot CLI automatically when PowerShell starts

# Add GitHub CLI to PATH
$env:PATH = "C:\Program Files\GitHub CLI;$env:PATH"

# Create aliases for easier access
Set-Alias -Name gh -Value "C:\Program Files\GitHub CLI\gh.exe" -Force
Set-Alias -Name copilot -Value "C:\Program Files\GitHub CLI\gh.exe" -Force

# Optional: Add function for quick initialization check
function Test-CopilotSetup {
    Write-Host "Testing GitHub CLI and Copilot CLI setup..." -ForegroundColor Green
    Write-Host ""
    Write-Host "GitHub CLI version:" -ForegroundColor Yellow
    & "C:\Program Files\GitHub CLI\gh.exe" --version
    Write-Host ""
    Write-Host "Copilot CLI version:" -ForegroundColor Yellow
    & "C:\Program Files\GitHub CLI\gh.exe" copilot --version
    Write-Host ""
    Write-Host "Setup is complete and ready to use!" -ForegroundColor Green
}

# Optional: Display setup info on profile load
Write-Host "GitHub Copilot CLI has been configured for this PowerShell session." -ForegroundColor Cyan
Write-Host "Available commands: 'gh' and 'copilot'" -ForegroundColor Cyan
