param([string[]]$Lines, [string]$Shot = "")
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SY1 { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
[SY1]::SetForegroundWindow((Get-Process WoW | Select-Object -First 1).MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 700
foreach ($s in $Lines) { [Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 400; [Windows.Forms.SendKeys]::SendWait(($s -replace '([\(\)\{\}\+\^%~])', '{$1}')); Start-Sleep -Milliseconds 300; [Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 700 }
Start-Sleep -Milliseconds 2500
if ($Shot) { & 'D:\Octowow\PhotonWoW\tools\eq_capture.ps1' -Out $Shot -Wait 0.2 -Scale 0.5 | Out-Null }
