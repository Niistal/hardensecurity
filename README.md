# HardenSecurity - Windows Security Hardening Automation

Script de automatización para la instalación y ejecución segura del módulo `Harden-Windows-Security`.

## Contenido
- `Invoke-WindowsHardening.ps1`: Script PowerShell que busca, instala, desbloquea y ejecuta las categorías de seguridad de Windows baselines y Defender.

## Uso
```powershell
# Modo auditoría (sin aplicar cambios destructivos)
.\Invoke-WindowsHardening.ps1 -AuditOnly

# Modo protección completa
.\Invoke-WindowsHardening.ps1
```
