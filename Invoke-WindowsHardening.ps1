<#
.SYNOPSIS
    Automated Windows Defensive Hardening Orchestrator.
    Integrates and executes the Harden-Windows-Security baseline module.

.DESCRIPTION
    Safely unpacks, validates, and runs system hardening categories according to
    Microsoft Security Baselines and Attack Surface Reduction (ASR) rules.
    Runs in AuditOnly mode by default to prevent accidental configuration changes.

.PARAMETER AuditOnly
    Runs verification and compliance checking without making system modifications (Default: $true).

.PARAMETER Apply
    Enforces hardening rules on the host operating system. Requires elevation and System Restore.

.EXAMPLE
    .\Invoke-WindowsHardening.ps1
    Runs compliance audit mode by default.

.EXAMPLE
    .\Invoke-WindowsHardening.ps1 -Apply
    Applies defensive hardening baselines.
#>

[CmdletBinding()]
param(
    [switch]$AuditOnly = $true,
    [switch]$Apply = $false
)

$ErrorActionPreference = "Stop"

# If -Apply is explicitly passed, disable AuditOnly
if ($Apply) {
    $AuditOnly = $false
}

# --- 1. CONFIGURATION ---
$CurrentDir = $PSScriptRoot 
if (-not $CurrentDir) { $CurrentDir = Get-Location }

$InstallPath = "$env:USERPROFILE\Documents\PowerShell\Modules\Harden-Windows-Security"
$TempDir = "C:\Temp_HWS_Local"
$LogPath = "C:\Logs\Hardening"

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Windows Security Hardening Orchestrator — Defensive Baseline  " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
if ($AuditOnly) {
    Write-Host "  MODE: AUDIT ONLY (Safe inspection mode — no mutations made)   " -ForegroundColor Green
} else {
    Write-Host "  MODE: APPLY ENFORCEMENT (System changes will be written)     " -ForegroundColor Yellow
}
Write-Host "  Log Directory: $LogPath" -ForegroundColor DarkGray
Write-Host "----------------------------------------------------------------"

# --- 2. LOCATE PACKAGE ---
$Package = Get-ChildItem -Path $CurrentDir -Include "*.zip", "*.nupkg" -Recurse -Depth 0 | 
    Where-Object { $_.Length -gt 20000 } | 
    Select-Object -First 1

if (-not $Package) {
    Write-Host "ERROR: Module package (.nupkg / .zip) not found in current directory." -ForegroundColor Red
    Write-Host "Please download the verified module from PowerShell Gallery or GitHub releases:"
    Write-Host "  https://www.powershellgallery.com/api/v2/package/Harden-Windows-Security"
    Write-Host "Save the file to: $CurrentDir and re-run this script."
    exit 1
}

Write-Host "[+] Found package: $($Package.Name)" -ForegroundColor Green

# --- 3. EXTRACTION & UNBLOCK ---
Write-Host "[*] Extracting package..." -ForegroundColor Cyan
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$ZipSource = $Package.FullName
if ($Package.Extension -eq ".nupkg") {
    $ZipSource = "$TempDir\package.zip"
    Copy-Item $Package.FullName -Destination $ZipSource
}

Expand-Archive -Path $ZipSource -DestinationPath $TempDir -Force

$Manifest = Get-ChildItem -Path $TempDir -Filter "Harden-Windows-Security.psd1" -Recurse | Select-Object -First 1
if (-not $Manifest) {
    Throw "CRITICAL: Valid module manifest (.psd1) not found inside package archive."
}

Write-Host "[*] Installing module to user scope: $InstallPath" -ForegroundColor Cyan
if (Test-Path $InstallPath) { Remove-Item $InstallPath -Recurse -Force }
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

Copy-Item -Path "$($Manifest.DirectoryName)\*" -Destination $InstallPath -Recurse -Force
Get-ChildItem -Path $InstallPath -Recurse | Unblock-File

# --- 4. EXECUTION ---
Write-Host "[*] Loading module into session..." -ForegroundColor Cyan
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:PSModulePath"

try {
    Import-Module Harden-Windows-Security -Force
} catch {
    Import-Module "$InstallPath\Harden-Windows-Security.psd1" -Force
}

if (-not (Get-Command "Protect-WindowsSecurity" -ErrorAction SilentlyContinue)) {
    Throw "Module loaded but Protect-WindowsSecurity command is unavailable."
}

$categories = @(
    "MicrosoftSecurityBaselines", "Microsoft365AppsSecurityBaselines", "Defender", 
    "AttackSurfaceReductionRules", "BitLocker", "DeviceGuard", "TLSSecurity", 
    "LockScreen", "UserAccountControl", "WindowsFirewall", "OptionalFeatures", 
    "WindowsNetworking", "ProcessMitigations"
)

Push-Location $InstallPath
try {
    if ($AuditOnly) {
        Write-Host "[*] Running verification pass (AuditOnly / Confirm)..." -ForegroundColor Green
        Protect-WindowsSecurity -Categories $categories -Operation "Confirm" -LogPath $LogPath
    } else {
        Write-Host "[!] Enforcing defensive baselines across 13 categories..." -ForegroundColor Yellow
        Protect-WindowsSecurity -Categories $categories -Operation "Protect" -LogPath $LogPath -Verbose
    }
} finally {
    Pop-Location
}

Write-Host "`n[+] Operation completed. Check audit logs in $LogPath" -ForegroundColor Cyan