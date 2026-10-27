# Records the mean brightness of the world area about every 0.6 s while the user toggles EqShaders with F7 on audible cues.
# Cues: one long low beep = recording started; a double high beep = press F7 now. Output: a time series plus the step at each cue.
param([int]$Seconds = 40, [int[]]$Cues = @(8, 16, 24, 32), [string]$Out = "")
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$w = [int]($bounds.Width * 0.2); $h = [int]($bounds.Height * 0.2)
$full = New-Object Drawing.Bitmap $bounds.Width, $bounds.Height
$small = New-Object Drawing.Bitmap $w, $h
$gf = [Drawing.Graphics]::FromImage($full); $gs = [Drawing.Graphics]::FromImage($small); $gs.InterpolationMode = 'HighQualityBilinear'
function Sample {
    $gf.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
    $gs.DrawImage($full, 0, 0, $w, $h)
    $s = 0; $n = 0; $top = 0; $nt = 0; $bot = 0; $nb = 0
    for ($x = [int]($w * 0.2); $x -lt [int]($w * 0.8); $x += 2) {
        for ($y = [int]($h * 0.08); $y -lt [int]($h * 0.62); $y += 2) {
            $c = $small.GetPixel($x, $y); $l = 0.2126 * $c.R + 0.7152 * $c.G + 0.0722 * $c.B
            $s += $l; $n++
            if ($y -lt $h * 0.30) { $top += $l; $nt++ } elseif ($y -gt $h * 0.40) { $bot += $l; $nb++ }
        }
    }
    [pscustomobject]@{ all = [math]::Round($s / $n, 1); far = [math]::Round($top / $nt, 1); near = [math]::Round($bot / $nb, 1) }
}
[console]::Beep(500, 700)
$t0 = Get-Date; $rows = @(); $cueIdx = 0
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    $t = ((Get-Date) - $t0).TotalSeconds
    if ($cueIdx -lt $Cues.Count -and $t -ge $Cues[$cueIdx]) { [console]::Beep(1400, 250); [console]::Beep(1400, 250); $rows += [pscustomobject]@{ t = [math]::Round($t, 1); all = 'CUE'; far = ''; near = '' }; $cueIdx++ }
    $m = Sample
    $rows += [pscustomobject]@{ t = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1); all = $m.all; far = $m.far; near = $m.near }
    Start-Sleep -Milliseconds 250
}
[console]::Beep(500, 400)
$rows | Format-Table -AutoSize | Out-String -Width 120
if ($Out) { $rows | Export-Csv $Out -NoTypeInformation }
