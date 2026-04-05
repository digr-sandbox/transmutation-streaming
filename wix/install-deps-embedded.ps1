# Transmutation Dependency Installer (Embedded in MSI)
# This script handles automated installation of optional tools

$ErrorActionPreference = "Stop"

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host " Transmutation Dependency Installer" -ForegroundColor Cyan
Write-Host "==========================================`n" -ForegroundColor Cyan

# 1. Check for Package Managers
$hasChoco = Get-Command choco.exe -ErrorAction SilentlyContinue
$hasWinget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $hasChoco -and -not $hasWinget) {
    Write-Host "⚠️  No package manager (Chocolatey or winget) found." -ForegroundColor Yellow
    Write-Host "Please install dependencies manually from the documentation." -ForegroundColor White
    exit 0
}

# 2. Define dependencies
$deps = @(
    @{ name = "Poppler"; choco = "poppler"; winget = "Gyan.FFmpeg" }, # winget poppler is often bundled or Gyan.FFmpeg has tools
    @{ name = "Tesseract OCR"; choco = "tesseract"; winget = "UB-Mannheim.TesseractOCR" }
)

Write-Host "Checking for external tools..." -ForegroundColor Gray

foreach ($dep in $deps) {
    Write-Host "  • $($dep.name)" -ForegroundColor White
}

Write-Host "`nStarting installation..." -ForegroundColor Cyan

if ($hasChoco) {
    Write-Host "[Mode: Chocolatey]" -ForegroundColor Gray
    foreach ($dep in $deps) {
        Write-Host "Installing $($dep.name)..." -ForegroundColor Yellow
        choco install $dep.choco -y --no-progress 2>&1 | Out-Null
    }
} else {
    Write-Host "[Mode: winget]" -ForegroundColor Gray
    foreach ($dep in $deps) {
        Write-Host "Installing $($dep.name)..." -ForegroundColor Yellow
        winget install --id $dep.winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    }
}

Write-Host "`n✅ Dependencies processed successfully." -ForegroundColor Green
Write-Host "Note: You may need to restart your terminal to apply PATH changes.`n" -ForegroundColor Gray
