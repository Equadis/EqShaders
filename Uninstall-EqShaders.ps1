param(
    [Parameter(Position=0)]
    [string]$WoWPath = (Get-Location).Path,

    [switch]$RemoveComfyInstalledByEqShaders
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$WoWPath = [IO.Path]::GetFullPath($WoWPath)
$StateDir = Join-Path $WoWPath 'EqShaders'
$ManifestPath = Join-Path $StateDir 'install.json'

function Say([string]$Text) { Write-Host "[EqShaders] $Text" }

if (-not (Test-Path (Join-Path $WoWPath 'WoW.exe'))) {
    throw "WoW.exe was not found in '$WoWPath'."
}

$manifest = $null
if (Test-Path $ManifestPath) {
    $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
}

$remove = @(
    (Join-Path $WoWPath 'EqShaders.ini'),
    (Join-Path $WoWPath 'Launch_EqShaders.bat'),
    (Join-Path $WoWPath 'reshade-shaders\Shaders\EqShaders.fx'),
    (Join-Path $WoWPath 'reshade-shaders\Shaders\PhotonWoW')
)
foreach ($p in $remove) {
    if (Test-Path $p) {
        Say "Removing $p"
        Remove-Item $p -Recurse -Force
    }
}

$dllsBackup = Join-Path $StateDir 'dlls.txt.before-eqshaders'
$dllsPath = Join-Path $WoWPath 'dlls.txt'
if (Test-Path $dllsBackup) {
    Say 'Restoring dlls.txt from the pre-EqShaders backup.'
    Copy-Item $dllsBackup $dllsPath -Force
}

if ($RemoveComfyInstalledByEqShaders -and $manifest) {
    if ($manifest.installedComfyDll -eq $true) {
        $p = Join-Path $WoWPath 'comfyatmos.dll'
        if (Test-Path $p) { Say 'Removing comfyatmos.dll installed by EqShaders.'; Remove-Item $p -Force }
    }
    if ($manifest.installedComfyIni -eq $true) {
        $p = Join-Path $WoWPath 'comfyatmos.ini'
        if (Test-Path $p) { Say 'Removing comfyatmos.ini installed by EqShaders.'; Remove-Item $p -Force }
    }
    if ($manifest.installedComfyAddon -eq $true) {
        $p = Join-Path $WoWPath 'Interface\AddOns\ComfyAtmosphere'
        if (Test-Path $p) { Say 'Removing ComfyAtmosphere addon installed by EqShaders.'; Remove-Item $p -Recurse -Force }
    }
}

Say 'EqShaders ReShade integration removed.'
if (-not $RemoveComfyInstalledByEqShaders) {
    Say 'ComfyAtmosphere files were left in place. Use -RemoveComfyInstalledByEqShaders to remove only Comfy files that the EqShaders manifest says it installed.'
}
