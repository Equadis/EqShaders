# Copies PhotonWoW into an existing ReShade install. Does not touch WoW, DXVK or ReShade binaries.
# usage: powershell -ExecutionPolicy Bypass -File Install.ps1 -GameDir D:\Octowow
param(
    [Parameter(Mandatory = $true)][string]$GameDir,
    [string]$ShadersDir = ""   # default: <GameDir>\reshade-shaders
)

$root = Split-Path -Parent $PSScriptRoot
if (-not $ShadersDir) { $ShadersDir = Join-Path $GameDir "reshade-shaders" }

$dstShaders = Join-Path $ShadersDir "Shaders"
New-Item -ItemType Directory -Force $dstShaders | Out-Null
Copy-Item -Recurse -Force (Join-Path $root "Shaders\*") $dstShaders
Copy-Item -Force (Join-Path $root "PhotonWoW.ini") (Join-Path $GameDir "PhotonWoW.ini")
Copy-Item -Force (Join-Path $root "PHOTON_LICENSE.txt") $dstShaders

Write-Host "Installed to $dstShaders"
Write-Host "Preset copied to $(Join-Path $GameDir 'PhotonWoW.ini')"
Write-Host "In ReShade: Settings > Effect search paths must include $dstShaders ; load PhotonWoW.ini on the Home tab."
