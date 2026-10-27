# At a held pose: capture, set CVars through /script, capture, restore, capture. usage: cvar_ab.ps1 -Out <dir> -Name comfySunShadowStrength -Value 0
param([string]$Out, [string]$Name, [string]$Value)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CA1 { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
New-Item -ItemType Directory -Force $Out | Out-Null
$tools = 'D:\Octowow\PhotonWoW\tools'
function Say($s) { [Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 400; [Windows.Forms.SendKeys]::SendWait(($s -replace '([\(\)\{\}\+\^%~])', '{$1}')); Start-Sleep -Milliseconds 300; [Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 600 }
[CA1]::SetForegroundWindow((Get-Process WoW | Select-Object -First 1).MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 800
& "$tools\eq_capture.ps1" -Out "$Out\a_before.png" -Wait 0.2 -Scale 0.5 | Out-Null
Say "/script EQ_SAVED=GetCVar('$Name')"
Say "/script SetCVar('$Name','$Value')"
Start-Sleep -Milliseconds 2500
& "$tools\eq_capture.ps1" -Out "$Out\b_changed.png" -Wait 0.2 -Scale 0.5 | Out-Null
Say "/script SetCVar('$Name',EQ_SAVED)"
Start-Sleep -Milliseconds 2500
& "$tools\eq_capture.ps1" -Out "$Out\c_restored.png" -Wait 0.2 -Scale 0.5 | Out-Null
"done"
