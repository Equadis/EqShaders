# Captures the screen, then again after each F7 press the user makes (detected with GetAsyncKeyState). usage: f7_ab.ps1 -Out <dir> [-Presses 2] [-Timeout 90]
param([string]$Out, [int]$Presses = 2, [int]$Timeout = 90)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class F7K { [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k); }
"@
New-Item -ItemType Directory -Force $Out | Out-Null
$tools = 'D:\Octowow\PhotonWoW\tools'
& "$tools\eq_capture.ps1" -Out "$Out\s0.png" -Wait 0.2 -Scale 0.5 | Out-Null
[console]::Beep(800, 200)
$t0 = Get-Date
for ($i = 1; $i -le $Presses; $i++) {
    while (((Get-Date) - $t0).TotalSeconds -lt $Timeout -and -not ([F7K]::GetAsyncKeyState(0x76) -band 0x8000)) { Start-Sleep -Milliseconds 30 }
    while ([F7K]::GetAsyncKeyState(0x76) -band 0x8000) { Start-Sleep -Milliseconds 30 }
    Start-Sleep -Milliseconds 1200
    & "$tools\eq_capture.ps1" -Out "$Out\s$i.png" -Wait 0.2 -Scale 0.5 | Out-Null
    "captured s$i"
}
