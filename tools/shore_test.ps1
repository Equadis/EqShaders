# shore_test.ps1: one quick A/B run for the shoreline seam. Stand still with the seam near the screen centre first (about 25 s).
# Takes the same view with: baseline, Comfy wet sand off, Comfy foam off, Comfy surface 0 (game water only), EqShaders AO off.
# Restores every setting afterwards. Output sheet: D:\Octowow\PhotonWoW\_shore_test.png
param([string]$Game = 'D:\Octowow')
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class ST { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint fl, UIntPtr ex); }
"@
function Atmos($cmd) { Key 0x0D 0; Start-Sleep -Milliseconds 450; [Windows.Forms.SendKeys]::SendWait($cmd); Start-Sleep -Milliseconds 250; Key 0x0D 0; Start-Sleep -Milliseconds 700 }
function Key($vk, $sc) { [ST]::keybd_event($vk, $sc, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 100; [ST]::keybd_event($vk, $sc, 2, [UIntPtr]::Zero) }
$set = "$Game\PhotonWoW\tools\eq_setini.ps1"
$out = Join-Path $env:TEMP 'shore_test'; New-Item -ItemType Directory -Force $out | Out-Null
$comfyBackup = "$Game\comfyatmos.ini.shoretest.bak"; $presetBackup = "$Game\EqShaders.ini.shoretest.bak"
Copy-Item "$Game\comfyatmos.ini" $comfyBackup -Force; Copy-Item "$Game\EqShaders.ini" $presetBackup -Force
function Shot($name) {
    Start-Sleep 2.2
    $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
    [Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
    $r = New-Object Drawing.Rectangle ([int]($b.Width / 2 - 450)), ([int]($b.Height / 2 - 300)), 900, 600
    $c = $bmp.Clone($r, $bmp.PixelFormat); $c.Save("$out\$name.png"); $c.Dispose(); $bmp.Dispose()
}
try {
    [ST]::SetForegroundWindow((Get-Process WoW).MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 700
    Shot '0_baseline'
    Atmos '/atmos water.wetSand 0'; Shot '1_wetSand_off'; Atmos '/atmos water.wetSand 0.45'
    Atmos '/atmos water.shoreFoam 0'; Atmos '/atmos water.foam 0'; Shot '2_foam_off'
    Atmos '/atmos water.shoreFoam 0.85'; Atmos '/atmos water.foam 0.25'
    Atmos '/atmos water.surface 0'; Shot '3_game_water_only'; Atmos '/atmos water.surface 1'
    # EqShaders: AO and contact AO off through the preset, then reload effects (F8)
    $p = (Get-Content "$Game\EqShaders.ini") -replace '^AOStrength=.*', 'AOStrength=0.000000' -replace '^AOContact=.*', 'AOContact=0.000000'
    Set-Content "$Game\EqShaders.ini" $p -Encoding ASCII; Key 0x77 0x42; Start-Sleep 4; Shot '4_eq_AO_off'
} finally {
    Copy-Item $comfyBackup "$Game\comfyatmos.ini" -Force; Copy-Item $presetBackup "$Game\EqShaders.ini" -Force
    Key 0x77 0x42
}
$files = '0_baseline', '1_wetSand_off', '2_foam_off', '3_game_water_only', '4_eq_AO_off'
$tw = 600; $th = 400; $sheet = New-Object Drawing.Bitmap ($tw * 3), ($th * 2); $g = [Drawing.Graphics]::FromImage($sheet); $i = 0
foreach ($f in $files) {
    $im = [Drawing.Image]::FromFile("$out\$f.png"); $g.DrawImage($im, ($i % 3) * $tw, [math]::Floor($i / 3) * $th, $tw, $th); $im.Dispose()
    $g.DrawString($f, (New-Object Drawing.Font 'Arial', 13), [Drawing.Brushes]::Yellow, ($i % 3) * $tw + 4, [math]::Floor($i / 3) * $th + 3); $i++
}
$sheet.Save("$Game\PhotonWoW\_shore_test.png"); "saved $Game\PhotonWoW\_shore_test.png (settings restored)"

