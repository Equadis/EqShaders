# usage: eq_setini.ps1 -Section general -Key enabled -Value 0   (edits comfyatmos.ini in place, keeps the trailing comment)
param([string]$Section, [string]$Key, [string]$Value, [string]$Ini = 'D:\Octowow\comfyatmos.ini')
$lines = [IO.File]::ReadAllLines($Ini)
$in = $false; $done = $false
for ($i = 0; $i -lt $lines.Length; $i++) {
  if ($lines[$i] -match '^\[(.+)\]\s*$') { $in = ($Matches[1] -eq $Section); continue }
  if ($in -and -not $done -and $lines[$i] -match "^($([regex]::Escape($Key))\s*=\s*)(\S+)(.*)$") {
    $lines[$i] = $Matches[1] + $Value + $Matches[3]; $done = $true
  }
}
if (-not $done) { throw "[$Section] $Key not found" }
[IO.File]::WriteAllLines($Ini, $lines, (New-Object Text.UTF8Encoding($false)))
"[$Section] $Key = $Value"
