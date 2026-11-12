<#
    Build-OptiWin-exe.ps1
    ---------------------------------------------------------------------------
    Turns OptiWin.ps1 into a single OptiWin.exe, on Windows.

    An .exe cannot be built on a non-Windows machine, so this runs where the tool
    runs. It uses the community module "ps2exe", installs it for your user if it
    is missing, and produces OptiWin.exe with the CyberX icon, version info, the
    company name "CyberX, SVPNPA", and a built-in request for administrator rights.

    HOW TO RUN
      1. Keep this file next to OptiWin.ps1 and the assets folder.
      2. Right-click it > Run with PowerShell  (or, in a PowerShell window:
         powershell -ExecutionPolicy Bypass -File .\Build-OptiWin-exe.ps1 )
      3. If asked to trust the PSGallery repository the first time, answer Yes.
      4. OptiWin.exe appears in this folder. Double-click it to run the tool.

    Installing the module needs internet the first time only. After that the exe
    is self-contained and runs offline.
#>

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$src  = Join-Path $here 'OptiWin.ps1'
$out  = Join-Path $here 'OptiWin.exe'
$icon = Join-Path $here 'assets\OptiWin.ico'

if (-not (Test-Path $src)) { throw "OptiWin.ps1 was not found next to this script ($src)." }

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'Installing the ps2exe module for your user (needs internet, one time)...'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    try { Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null } catch { }
    Install-Module -Name ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

$params = @{
    InputFile   = $src
    OutputFile  = $out
    noConsole   = $true          # it is a window app, no console
    requireAdmin = $true         # asks for administrator rights on launch
    x64         = $true
    title       = 'OptiWin'
    product     = 'OptiWin'
    description = 'OptiWin - Windows 10/11 debloater. Powered by CyberX, SVPNPA.'
    company     = 'CyberX, SVPNPA'
    copyright   = 'CyberX, SVPNPA'
    version     = '2.1.0.0'
}
if (Test-Path $icon) { $params['iconFile'] = $icon }

Write-Host 'Building OptiWin.exe ...'
Invoke-ps2exe @params
Write-Host ''
Write-Host "Done. Created: $out"
Write-Host 'Double-click OptiWin.exe to run the tool (it will ask for administrator rights).'
