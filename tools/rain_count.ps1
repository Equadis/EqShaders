# Reads the LAST F12 capture in Logs\comfyatmos.log and counts the game's rain draws in it: splash draws/triangles, streak draws/triangles.
# usage: rain_count.ps1 -Tag roof   (press F12 in game first)
param([string]$Tag = "spot")
$fs = [IO.File]::Open('D:\Octowow\Logs\comfyatmos.log', 'Open', 'Read', 'ReadWrite')
$txt = (New-Object IO.StreamReader $fs).ReadToEnd(); $fs.Close()
$i = $txt.LastIndexOf('--- begin frame'); if ($i -lt 0) { 'no capture in the log'; return }
$cap = $txt.Substring($i); $lines = $cap -split "`r?`n"
$head = $lines[0]
$sp = $lines | Where-Object { $_ -match 'RAIN\s+256x256.*the splashes' }
$st = $lines | Where-Object { $_ -match 'RAIN\s+16x128' }
function Tri($set) { ($set | ForEach-Object { if ($_ -match '(\d+) triangles') { [int]$Matches[1] } } | Measure-Object -Sum).Sum }
$under = ($lines | Where-Object { $_ -match 'underwater: camera read' } | Select-Object -Last 1)
$rainLine = ($lines | Where-Object { $_ -match '^clouds:.*rain ' } | Select-Object -First 1)
"[$Tag] $head"
"splash draws: $(@($sp).Count), triangles: $(Tri $sp)"
"streak draws: $(@($st).Count), triangles: $(Tri $st)"
if ($rainLine -match 'rain ([\d\.]+)') { "clouds' rain amount: $($Matches[1])" }
if ($under) { $under.Substring(0, [Math]::Min(120, $under.Length)) }
