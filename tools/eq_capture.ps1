# usage: eq_capture.ps1 -Out file.png [-Key 0x7A] [-Wait 3] [-Scale 0.5]
# Foregrounds WoW, optionally presses one virtual key (e.g. 0x7A = F11, Comfy's INI reload), waits, captures the primary screen.
param([string]$Out, [int]$Key = 0, [double]$Wait = 3, [double]$Scale = 0.5)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class EqW { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint fl, UIntPtr ex); }
"@
$h = (Get-Process WoW | Select -First 1).MainWindowHandle
[EqW]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 800
if ($Key) { [EqW]::keybd_event([byte]$Key, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [EqW]::keybd_event([byte]$Key, 0, 2, [UIntPtr]::Zero) }
Start-Sleep -Seconds $Wait
$b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
[Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
$w = [int]($b.Width * $Scale); $hh = [int]($b.Height * $Scale)
$s = New-Object Drawing.Bitmap $w, $hh
$g = [Drawing.Graphics]::FromImage($s); $g.InterpolationMode = 'HighQualityBicubic'; $g.DrawImage($bmp, 0, 0, $w, $hh)
$s.Save($Out); $Out
