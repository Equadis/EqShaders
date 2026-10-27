# Builds comfyatmos.dll (32-bit) from the ComfyAtmosphere source with llvm-mingw, for the EqShaders patches.
# usage: .\build_comfy.ps1 -Source <comfy checkout> -Toolchain <llvm-mingw\bin> [-Out comfyatmos.dll] [-Jobs 6]
# The upstream build is MSVC (CMake). This is the same sources compiled with clang as a 32-bit Windows DLL, static runtime.
# Source patches needed for clang: function-pointer -> void* forwarding templates for HookSlot (comfyatmos.cpp) and WriteJump
# (grass.cpp); version.h is written here instead of by cmake/version.cmake.
param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Toolchain, [string]$Out = "comfyatmos.dll", [int]$Jobs = 6)
$ErrorActionPreference = 'Stop'
$cc = Join-Path $Toolchain 'i686-w64-mingw32-clang++.exe'
$obj = Join-Path $Source 'build_obj'; New-Item -ItemType Directory -Force $obj | Out-Null
"#pragma once`n#define COMFYATMOS_VERSION `"v0.17.1-alpha + EqShaders patches`"`n" | Set-Content (Join-Path $Source 'version.h') -Encoding ASCII
$flags = @('-std=c++17','-O2','-w','-c','-fms-extensions','-DWIN32_LEAN_AND_MEAN','-DNOMINMAX',"-I$Source","-I$(Join-Path $Source 'src')")
$files = Get-ChildItem (Join-Path $Source 'src') -Filter *.cpp
$running = @()
foreach ($f in $files) {
    $o = Join-Path $obj ($f.BaseName + '.o')
    if ((Test-Path $o) -and ((Get-Item $o).LastWriteTime -gt $f.LastWriteTime) -and ((Get-Item $o).LastWriteTime -gt (Get-ChildItem (Join-Path $Source 'src') -Filter *.h | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime)) { continue }
    while (@($running | Where-Object { -not $_.HasExited }).Count -ge $Jobs) { Start-Sleep -Milliseconds 300 }
    $argv = ($flags + @($f.FullName, '-o', $o)) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $running += Start-Process $cc -ArgumentList ($argv -join ' ') -NoNewWindow -PassThru -RedirectStandardError "$o.err"
}
$running | ForEach-Object { $_.WaitForExit() }
$bad = Get-ChildItem $obj -Filter *.err | Where-Object { (Get-Content $_.FullName -Raw) -match 'error' }
if ($bad) { $bad | ForEach-Object { "COMPILE FAILED: $($_.Name)"; Get-Content $_.FullName | Select-Object -First 8 }; throw "compile errors" }
$objs = Get-ChildItem $obj -Filter *.o | ForEach-Object { $_.FullName }
& $cc -shared -static -o (Join-Path $Source $Out) @objs -lkernel32 -luser32 -lgdi32 -ladvapi32 -lshell32 -lole32 -lversion -lpsapi -ldbghelp 2>&1 | Select-Object -First 40
Get-Item (Join-Path $Source $Out) | ForEach-Object { "built $($_.FullName) $($_.Length) bytes" }
