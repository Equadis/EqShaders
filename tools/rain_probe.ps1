# Press F12 (Comfy probe) at the current spot, wait, screenshot, and print the splash/rain lines the probe wrote. usage: rain_probe.ps1 -Tag open
param([string]$Tag = "spot")
Add-Type @"
using System; using System.Runtime.InteropServices;
public class RP1 { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint fl, UIntPtr ex); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
$log = 'D:\Octowow\Logs\comfyatmos.log'
$before = (Get-Item $log).Length
[RP1]::SetForegroundWindow((Get-Process WoW | Select-Object -First 1).MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 700
& 'D:\Octowow\PhotonWoW\tools\eq_capture.ps1' -Out "D:\Octowow\EqShaders\rain_$Tag.png" -Wait 0.2 -Scale 0.5 | Out-Null
[RP1]::keybd_event(0x7B,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 400; [RP1]::keybd_event(0x7B,0,2,[UIntPtr]::Zero)
Start-Sleep 15
$fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); $fs.Seek($before, 'Begin') | Out-Null
$txt = (New-Object IO.StreamReader $fs).ReadToEnd(); $fs.Close()
$lines = $txt -split "`r?`n"
"bytes written by the probe: $($txt.Length); lines: $($lines.Count)"
$lines | Select-String -Pattern 'RAIN|splash|rain|weather|indoor|Indoor' | Select-Object -First 25 | % { $_.Line.Substring(0, [Math]::Min(200, $_.Line.Length)) }
