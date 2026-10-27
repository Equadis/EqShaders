# Pitch sweep with a Comfy A/B at each pose: orbit the camera up/down in steps (left-drag), and at every pose capture the screen with the
# sun rays on, then with them off (INI [rays] enabled + F11), plus an F12 probe for the pose. Output: a table of mean world brightness.
# usage: pitch_sweep.ps1 -Out <dir> [-Steps 8] [-Dy 30]   (leave the keyboard and mouse alone while it runs)
param([string]$Out, [int]$Steps = 8, [int]$Dy = 30)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class PS1 { [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f,int x,int y,int d,UIntPtr e); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint fl, UIntPtr ex);}
"@
New-Item -ItemType Directory -Force $Out | Out-Null
$tools = 'D:\Octowow\PhotonWoW\tools'
function Key($vk) { [PS1]::keybd_event($vk, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [PS1]::keybd_event($vk, 0, 2, [UIntPtr]::Zero) }
function Drag($dy) { [PS1]::SetCursorPos(1720, 720) | Out-Null; Start-Sleep -Milliseconds 120; [PS1]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100
    $n = [math]::Max(1, [math]::Abs($dy) / 10); 1..$n | ForEach-Object { [PS1]::mouse_event(1, 0, [math]::Sign($dy) * 10, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 25 }
    [PS1]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 500 }
function Mean($png) { $b = [Drawing.Bitmap]::FromFile($png); $s = 0; $n = 0; $w = $b.Width; $h = $b.Height
    for ($x = [int]($w*0.2); $x -lt [int]($w*0.8); $x += 3) { for ($y = [int]($h*0.08); $y -lt [int]($h*0.62); $y += 3) { $c = $b.GetPixel($x,$y); $s += 0.2126*$c.R + 0.7152*$c.G + 0.0722*$c.B; $n++ } }
    $b.Dispose(); [math]::Round($s / $n, 1) }
function SetRays($on) { & "$tools\eq_setini.ps1" rays enabled $(if ($on) { 1 } else { 0 }) | Out-Null; Key 0x7A; Start-Sleep -Milliseconds 2200 }

[PS1]::SetForegroundWindow((Get-Process WoW | Select-Object -First 1).MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 700
SetRays $true
Drag (-$Dy * 3)   # start low
$rows = @()
for ($i = 0; $i -lt $Steps; $i++) {
    Key 0x7B; Start-Sleep 3          # F12 probe for this pose
    $cam = (python -I "$tools\camera_from_probe.py" | Select-String 'solution \+1' | Select-Object -Last 1).Line
    $pitch = if ($cam -match 'pitch (-?[\d\.]+)') { $Matches[1] } else { '?' }
    & "$tools\eq_capture.ps1" -Out "$Out\p$i`_on.png" -Wait 0.4 -Scale 0.25 | Out-Null
    SetRays $false
    & "$tools\eq_capture.ps1" -Out "$Out\p$i`_off.png" -Wait 0.4 -Scale 0.25 | Out-Null
    SetRays $true
    $rows += [pscustomobject]@{ pose = $i; pitch = $pitch; raysOn = (Mean "$Out\p$i`_on.png"); raysOff = (Mean "$Out\p$i`_off.png") }
    Drag $Dy
}
$rows | ForEach-Object { $_ | Add-Member delta ([math]::Round($_.raysOn - $_.raysOff, 1)) -PassThru } | Format-Table -AutoSize | Out-String
