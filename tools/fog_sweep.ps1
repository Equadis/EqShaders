# Pitch sweep with a fog A/B at each pose. At every pose: capture normal, then Comfy [fog] off, then [fog] + [volume] off (INI + F11),
# and report mean brightness of the far (top) and near (bottom) parts of the world area, so "darker everywhere / far things clearer"
# can be traced to fog. usage: fog_sweep.ps1 -Out <dir> [-Steps 6] [-Dy 40]   (hands off the keyboard and mouse while it runs)
param([string]$Out, [int]$Steps = 6, [int]$Dy = 40)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class FS1 { [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f,int x,int y,int d,UIntPtr e); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint fl, UIntPtr ex);}
"@
New-Item -ItemType Directory -Force $Out | Out-Null
$tools = 'D:\Octowow\PhotonWoW\tools'
function Key($vk) { [FS1]::keybd_event($vk, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [FS1]::keybd_event($vk, 0, 2, [UIntPtr]::Zero) }
function Drag($dy) { [FS1]::SetCursorPos(1720, 720) | Out-Null; Start-Sleep -Milliseconds 120; [FS1]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100
    $n = [math]::Max(1, [math]::Abs($dy) / 10); 1..$n | ForEach-Object { [FS1]::mouse_event(1, 0, [math]::Sign($dy) * 10, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 25 }
    [FS1]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 700 }
function Region($png, $y0, $y1) { $b = [Drawing.Bitmap]::FromFile($png); $s = 0; $n = 0; $w = $b.Width; $h = $b.Height
    for ($x = [int]($w*0.2); $x -lt [int]($w*0.8); $x += 3) { for ($y = [int]($h*$y0); $y -lt [int]($h*$y1); $y += 3) { $c = $b.GetPixel($x,$y); $s += 0.2126*$c.R + 0.7152*$c.G + 0.0722*$c.B; $n++ } }
    $b.Dispose(); [math]::Round($s / $n, 1) }
function Fog($on, $vol) { & "$tools\eq_setini.ps1" fog enabled $(if ($on) { 1 } else { 0 }) | Out-Null; & "$tools\eq_setini.ps1" volume enabled $(if ($vol) { 1 } else { 0 }) | Out-Null; Key 0x7A; Start-Sleep -Milliseconds 2600 }
function Shot($name) { & "$tools\eq_capture.ps1" -Out "$Out\$name.png" -Wait 0.4 -Scale 0.25 | Out-Null }

[FS1]::SetForegroundWindow((Get-Process WoW | Select-Object -First 1).MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 700
Fog $true $true
Drag (-$Dy * 2)
$rows = @()
for ($i = 0; $i -lt $Steps; $i++) {
    Key 0x7B; Start-Sleep 3
    $cam = (python -I "$tools\camera_from_probe.py" | Select-String 'solution \+1' | Select-Object -Last 1).Line
    $pitch = if ($cam -match 'pitch (-?[\d\.]+)') { $Matches[1] } else { '?' }
    Shot "p$i`_normal"
    Fog $false $true;  Shot "p$i`_nofog"
    Fog $false $false; Shot "p$i`_nofog_novol"
    Fog $true $true
    $r = [pscustomobject]@{ pose = $i; pitch = $pitch }
    foreach ($v in 'normal','nofog','nofog_novol') { $f = "$Out\p$i`_$v.png"
        $r | Add-Member "far_$v" (Region $f 0.08 0.30) ; $r | Add-Member "near_$v" (Region $f 0.40 0.62) }
    $rows += $r
    Drag $Dy
}
$rows | Format-Table -AutoSize | Out-String -Width 200
