# easi-launcher v0.1 - ascii banner + autostart chooser
# standalone module; will be called by the start flow later
# usage: powershell -NoProfile -ExecutionPolicy Bypass -File D:\easi-connector\tools\easi-launcher.ps1
# note: ascii only, PS 5.1 encoding safe

$RunKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$ValName = 'easi-connector'
# what autostart runs: bridge hidden for now; switch to a master start script later if needed
$Target  = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\easi-connector\connector\bridge.ps1" -Hidden'

$Banner = @(
'######   ###      ___   ######',
'##      ##  ##   /        ##  ',
'#####   ######    ---_    ##  ',
'##     ##   ##      /     ##   ',
'###### ##   ##   ---    ######',
'',
' #####   ####  ##   ##  ##   ## ######    #### #####  ####  ##### ',
'##      ##  ## ###  ##  ###  ## ##      ##      ##   ##  ## ##  ##',
'##      ##  ## ## # ##  ## # ## #####  ##       ##   ##  ## ##### ',
'##      ##  ## ##  ###  ##  ### ##      ##      ##   ##  ## ## ## ',
' #####   ####  ##   ##  ##   ## ######    ####  ##    ####  ##  ##',
'',
' /-------------------------------------------\',
'| by:diamond_dia | powered by: GLM-5.3-flash |',
' \-------------------------------------------/'
)

foreach ($line in $Banner) { Write-Host $line -ForegroundColor Cyan }
Write-Host ''
Write-Host '  easi-connector  -  YJZ-B870 camera bridge for Seewo EasiCamera' -ForegroundColor Gray
Write-Host ''

function Test-Autostart {
    return $null -ne (Get-ItemProperty -Path $RunKey -Name $ValName -ErrorAction SilentlyContinue)
}

function Set-Autostart([bool]$On) {
    if ($On) { Set-ItemProperty -Path $RunKey -Name $ValName -Value $Target }
    else     { Remove-ItemProperty -Path $RunKey -Name $ValName -ErrorAction SilentlyContinue }
}

$on = Test-Autostart
if ($on) { Write-Host '  Autostart: ON  (HKCU Run)' -ForegroundColor Green }
else     { Write-Host '  Autostart: OFF' -ForegroundColor Yellow }

Write-Host ''
Write-Host '  [1] Enable autostart (HKCU Run)'
Write-Host '  [2] Disable autostart'
Write-Host '  [Enter] skip'
$choice = Read-Host '  Select'
switch ($choice) {
    '1' { Set-Autostart $true;  Write-Host '  Autostart enabled.' -ForegroundColor Green }
    '2' { Set-Autostart $false; Write-Host '  Autostart disabled.' -ForegroundColor Yellow }
    default { Write-Host '  Skipped.' -ForegroundColor Gray }
}
