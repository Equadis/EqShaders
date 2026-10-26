param(
    [Parameter(Position=0)]
    [string]$WoWPath = (Get-Location).Path,

    [switch]$SkipComfyDownload
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$EqVersion = '0.1.0-mvp'
$ComfyVersion = 'v0.17.1-alpha'
$ComfyCommit = '73bebaaf2439aa17cc7766bb99bf8513f9aa6ade'
$ComfyUrl = 'https://github.com/aloofbit/comfyatmosphere/releases/download/v0.17.1-alpha/comfyatmosphere-v0.17.1-alpha.zip'

$SourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WoWPath = [IO.Path]::GetFullPath($WoWPath)

function Say([string]$Text) { Write-Host "[EqShaders] $Text" }
function Ensure-Dir([string]$Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }

if (-not (Test-Path (Join-Path $WoWPath 'WoW.exe'))) {
    throw "WoW.exe was not found in '$WoWPath'. Pass your OctoWoW client directory, e.g. .\Install-EqShaders.ps1 'D:\Octowow'."
}

$ShaderSource = Join-Path $SourceRoot 'Shaders'
$EqFxSource = Join-Path $ShaderSource 'EqShaders.fx'
$HeaderSource = Join-Path $ShaderSource 'PhotonWoW'
$PresetSource = Join-Path $SourceRoot 'EqShaders.ini'

foreach ($Required in @($EqFxSource, $HeaderSource, $PresetSource)) {
    if (-not (Test-Path $Required)) { throw "Missing EqShaders package file: $Required" }
}

$StateDir = Join-Path $WoWPath 'EqShaders'
$ShaderDest = Join-Path $WoWPath 'reshade-shaders\Shaders'
$HeaderDest = Join-Path $ShaderDest 'PhotonWoW'
$PresetDest = Join-Path $WoWPath 'EqShaders.ini'
$ManifestPath = Join-Path $StateDir 'install.json'
Ensure-Dir $StateDir
Ensure-Dir $ShaderDest

Say "Installing EqShaders $EqVersion into $WoWPath"
Copy-Item $EqFxSource (Join-Path $ShaderDest 'EqShaders.fx') -Force
if (Test-Path $HeaderDest) { Remove-Item $HeaderDest -Recurse -Force }
Copy-Item $HeaderSource $HeaderDest -Recurse -Force
Copy-Item $PresetSource $PresetDest -Force
if (Test-Path (Join-Path $SourceRoot 'PHOTON_LICENSE.txt')) {
    Copy-Item (Join-Path $SourceRoot 'PHOTON_LICENSE.txt') (Join-Path $StateDir 'PHOTON_LICENSE.txt') -Force
}
if (Test-Path (Join-Path $SourceRoot 'THIRD_PARTY.md')) {
    Copy-Item (Join-Path $SourceRoot 'THIRD_PARTY.md') (Join-Path $StateDir 'THIRD_PARTY.md') -Force
}

$installedComfyDll = $false
$installedComfyIni = $false
$installedComfyAddon = $false
$comfyDllDest = Join-Path $WoWPath 'comfyatmos.dll'
$comfyIniDest = Join-Path $WoWPath 'comfyatmos.ini'
$comfyAddonDest = Join-Path $WoWPath 'Interface\AddOns\ComfyAtmosphere'

if (-not $SkipComfyDownload) {
    $needComfy = -not (Test-Path $comfyDllDest)
    if ($needComfy) {
        Say "ComfyAtmosphere is not installed; downloading pinned $ComfyVersion ($ComfyCommit)."
        $TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("EqShaders-" + [guid]::NewGuid().ToString('N'))
        $ZipPath = Join-Path $TempRoot 'comfyatmosphere.zip'
        $ExtractPath = Join-Path $TempRoot 'comfy'
        Ensure-Dir $TempRoot
        try {
            Invoke-WebRequest -Uri $ComfyUrl -OutFile $ZipPath -UseBasicParsing
            Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force

            $Dll = Get-ChildItem $ExtractPath -Recurse -File -Filter 'comfyatmos.dll' | Select-Object -First 1
            $Ini = Get-ChildItem $ExtractPath -Recurse -File -Filter 'comfyatmos.ini' | Select-Object -First 1
            $Addon = Get-ChildItem $ExtractPath -Recurse -Directory -Filter 'ComfyAtmosphere' | Where-Object {
                Test-Path (Join-Path $_.FullName 'ComfyAtmosphere.toc')
            } | Select-Object -First 1

            if (-not $Dll) { throw 'Pinned ComfyAtmosphere archive did not contain comfyatmos.dll.' }
            Copy-Item $Dll.FullName $comfyDllDest -Force
            $installedComfyDll = $true

            if ($Ini -and -not (Test-Path $comfyIniDest)) {
                Copy-Item $Ini.FullName $comfyIniDest
                $installedComfyIni = $true
            }

            if ($Addon -and -not (Test-Path $comfyAddonDest)) {
                Ensure-Dir (Split-Path -Parent $comfyAddonDest)
                Copy-Item $Addon.FullName $comfyAddonDest -Recurse
                $installedComfyAddon = $true
            }
        }
        finally {
            if (Test-Path $TempRoot) { Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    else {
        Say 'Existing comfyatmos.dll detected; leaving the user-installed copy and settings untouched.'
    }
}
else {
    Say 'Skipping ComfyAtmosphere download by request.'
}

# VanillaFixes loads comfyatmos.dll from dlls.txt. Keep a one-time backup because this is
# the only existing client file EqShaders edits.
$DllsPath = Join-Path $WoWPath 'dlls.txt'
$DllsBackup = Join-Path $StateDir 'dlls.txt.before-eqshaders'
if (Test-Path $DllsPath) {
    if (-not (Test-Path $DllsBackup)) { Copy-Item $DllsPath $DllsBackup }
    $lines = @(Get-Content $DllsPath)
}
else {
    $lines = @()
}

# Upstream ComfyAtmosphere says these old split modules must be removed when the combined DLL is used.
$lines = @($lines | Where-Object {
    $t = $_.Trim().ToLowerInvariant()
    $t -notin @('comfyfog.dll', 'comfygrass.dll', 'comfytime.dll')
})
if (-not ($lines | Where-Object { $_.Trim().ToLowerInvariant() -eq 'comfyatmos.dll' })) {
    $lines += 'comfyatmos.dll'
}
Set-Content -Path $DllsPath -Value $lines -Encoding ASCII

$LauncherPath = Join-Path $WoWPath 'Launch_EqShaders.bat'
$Launcher = @'
@echo off
setlocal
cd /d "%~dp0"

rem EqShaders stack:
rem WoW -> ComfyAtmosphere -> DXVK -> Vulkan -> ReShade -> EqShaders

if exist "reshade\ReShade32.json" (
    set "VK_ADD_IMPLICIT_LAYER_PATH=%CD%\reshade"
) else (
    echo [EqShaders] ReShade Vulkan layer not found at reshade\ReShade32.json.
    echo [EqShaders] The game can still start with ComfyAtmosphere, but EqShaders.fx will not load.
)

if exist "VanillaFixes.exe" (
    start "" "VanillaFixes.exe"
) else (
    echo [EqShaders] VanillaFixes.exe was not found. comfyatmos.dll normally requires VanillaFixes/dlls.txt.
    start "" "WoW.exe"
)
endlocal
'@
Set-Content -Path $LauncherPath -Value $Launcher -Encoding ASCII

$ReShadeLayer = Join-Path $WoWPath 'reshade\ReShade32.json'
$ReShadeState = if (Test-Path $ReShadeLayer) { 'detected' } else { 'missing' }
$VanillaFixesState = if (Test-Path (Join-Path $WoWPath 'VanillaFixes.exe')) { 'detected' } else { 'missing' }

$Manifest = [ordered]@{
    eqShadersVersion = $EqVersion
    installedAt = (Get-Date).ToString('o')
    wowPath = $WoWPath
    comfyPinnedVersion = $ComfyVersion
    comfyPinnedCommit = $ComfyCommit
    installedComfyDll = $installedComfyDll
    installedComfyIni = $installedComfyIni
    installedComfyAddon = $installedComfyAddon
    reshadeLayer = $ReShadeState
    vanillaFixes = $VanillaFixesState
    files = @(
        'EqShaders.ini',
        'Launch_EqShaders.bat',
        'reshade-shaders\Shaders\EqShaders.fx',
        'reshade-shaders\Shaders\PhotonWoW'
    )
}
$Manifest | ConvertTo-Json -Depth 4 | Set-Content $ManifestPath -Encoding UTF8

Say 'Install complete.'
Say "Launcher: $LauncherPath"
Say "ReShade Vulkan layer: $ReShadeState"
Say "VanillaFixes: $VanillaFixesState"
Say 'In ReShade, select EqShaders.ini and enable EqShaders [EqShaders.fx].'
Say 'For first in-world validation: Home -> EqShaders -> Debug / calibration -> Debug view -> Contact sheet.'
