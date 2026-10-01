<#
.SYNOPSIS
    Instalador Local (Mismo Directorio).
    Busca el paquete .zip/.nupkg en la carpeta actual, lo instala y ejecuta.
#>

[CmdletBinding()]
param([switch]$AuditOnly = $false)
$ErrorActionPreference = "Stop"

# --- 1. CONFIGURACIÓN ---
# Usamos la ruta donde está el script, no el Escritorio
$CurrentDir = $PSScriptRoot 
if (-not $CurrentDir) { $CurrentDir = Get-Location } # Fallback si se ejecuta copy-paste

$InstallPath = "$env:USERPROFILE\Documents\PowerShell\Modules\Harden-Windows-Security"
$TempDir = "C:\Temp_HWS_Local"

# Clear-Host
Write-Host "--- INSTALADOR LOCAL (SAME FOLDER) ---" -ForegroundColor Yellow
Write-Host "Buscando paquete en: $CurrentDir" -ForegroundColor Cyan

# --- 2. BUSCAR EL PAQUETE ---
# Buscamos cualquier zip o nupkg grande (>500KB) en la carpeta actual
$Package = Get-ChildItem -Path $CurrentDir -Include "*.zip", "*.nupkg" -Recurse -Depth 0 | 
Where-Object { $_.Length -gt 20000 } | 
Select-Object -First 1

if (-not $Package) {
    # [console]::Beep(500,300)
    Write-Host "ERROR: No encuentro el archivo del módulo aquí." -ForegroundColor Red
    Write-Host "--------------------------------------------------------"
    Write-Host "1. Descarga el archivo de: https://www.powershellgallery.com/api/v2/package/Harden-Windows-Security"
    Write-Host "2. PÉGALO en esta carpeta: $CurrentDir"
    Write-Host "3. Vuelve a ejecutar este script."
    Write-Host "--------------------------------------------------------"
    exit 1
}

Write-Host "Paquete encontrado: $($Package.Name)" -ForegroundColor Green

# --- 3. EXTRACCIÓN ---
Write-Host "Procesando..." -ForegroundColor Cyan
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Si es .nupkg, lo tratamos como zip
$ZipSource = $Package.FullName
if ($Package.Extension -eq ".nupkg") {
    $ZipSource = "$TempDir\renamed_package.zip"
    Copy-Item $Package.FullName -Destination $ZipSource
}

Expand-Archive -Path $ZipSource -DestinationPath $TempDir -Force

# --- 4. INSTALACIÓN ---
# Buscar el .psd1 (Manifiesto) dentro de lo descomprimido
$Manifest = Get-ChildItem -Path $TempDir -Filter "Harden-Windows-Security.psd1" -Recurse | Select-Object -First 1

if (-not $Manifest) {
    Throw "CRÍTICO: El archivo descargado NO es un módulo válido (no tiene .psd1). ¿Seguro que bajaste el link correcto?"
}

Write-Host "Instalando módulo en el sistema..." -ForegroundColor Cyan
if (Test-Path $InstallPath) { Remove-Item $InstallPath -Recurse -Force }
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

Copy-Item -Path "$($Manifest.DirectoryName)\*" -Destination $InstallPath -Recurse -Force

# Desbloquear
Get-ChildItem -Path $InstallPath -Recurse | Unblock-File

# --- 5. EJECUCIÓN ---
Write-Host "Cargando módulo..." -ForegroundColor Cyan
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:PSModulePath"

try {
    Import-Module Harden-Windows-Security -Force
}
catch {
    Import-Module "$InstallPath\Harden-Windows-Security.psd1" -Force
}

if (-not (Get-Command "Protect-WindowsSecurity" -ErrorAction SilentlyContinue)) {
    Throw "El módulo se instaló pero el comando falló al cargar."
}

$categories = @(
    "MicrosoftSecurityBaselines", "Microsoft365AppsSecurityBaselines", "Defender", 
    "AttackSurfaceReductionRules", "BitLocker", "DeviceGuard", "TLSSecurity", 
    "LockScreen", "UserAccountControl", "WindowsFirewall", "OptionalFeatures", 
    "WindowsNetworking", "ProcessMitigations"
)

Write-Host ">>> EJECUTANDO PROTECCIÓN EN 5 SEGUNDOS <<<" -ForegroundColor Green -BackgroundColor Black
Start-Sleep -Seconds 5

# Ir al directorio instalado para asegurar assets
Push-Location $InstallPath

try {
    if ($AuditOnly) {
        Protect-WindowsSecurity -Categories $categories -Operation "Confirm" -LogPath "C:\Logs"
    }
    else {
        Protect-WindowsSecurity -Categories $categories -Operation "Protect" -LogPath "C:\Logs" -Verbose
    }
}
finally {
    Pop-Location
}