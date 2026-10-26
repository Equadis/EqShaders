# Builds EqUIGate.addon32 and EqFog.dll (32-bit) with llvm-mingw. usage: .\build.ps1 -Toolchain <path to llvm-mingw\bin>
# Headers: addons\inc holds the ReShade v6.8.0 add-on API headers (BSD-3-Clause, crosire/reshade, include\).
param([Parameter(Mandatory)][string]$Toolchain)
$cc = Join-Path $Toolchain 'i686-w64-mingw32-clang++.exe'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
New-Item -ItemType Directory -Force "$here\bin" | Out-Null
& $cc -std=c++17 -O2 -shared -static -w -I"$here\inc" -o "$here\bin\EqUIGate.addon32" "$here\EqUIGate\EqUIGate.cpp"
& $cc -std=c++17 -O2 -shared -static -w -o "$here\bin\EqFog.dll" "$here\EqFog\EqFog.cpp"
Get-ChildItem "$here\bin" | Select-Object Name, Length
