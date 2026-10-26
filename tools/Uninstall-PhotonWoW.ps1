# Removes ONLY the files PhotonWoW/ReShade setup added. Existing OctoWoW/DXVK files are never touched.
$g='D:\Octowow'
Remove-Item -Recurse -Force "$g\reshade","$g\reshade-shaders" -ErrorAction SilentlyContinue
Remove-Item -Force "$g\ReShade.ini","$g\ReShade.log","$g\PhotonWoW.ini","$g\Launch_WoW_PhotonWoW.bat" -ErrorAction SilentlyContinue
Write-Host 'PhotonWoW/ReShade removed. Launch the game normally.'
