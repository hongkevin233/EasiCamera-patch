# easi-connector 格式桥 v2：cmd 原生管道泵（低延迟）
# 用法: powershell -File bridge.ps1 [-Source 'OBS Virtual Camera'] [-Width 1920] [-Height 1080] [-Fps 30] [-BridgeDevice AkVCamVideoDevice1]

param(
    [string]$Source = 'OBS Virtual Camera',
    [int]$Width = 1920,
    [int]$Height = 1080,
    [int]$Fps = 19,
    [string]$BridgeDevice = 'AkVCamVideoDevice0',
    [switch]$Hidden
)
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
Get-Process ffmpeg, AkVCamManager -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Output "bridge v2 (cmd pipe): [$Source] -> RGB24 ${Width}x${Height}@${Fps} -> [$BridgeDevice]"
# default: visible window (stderr visible, good for debugging); -Hidden for production
$style = if ($Hidden) { 'Hidden' } else { 'Normal' }
Start-Process (Join-Path $PSScriptRoot 'run-bridge.cmd') -ArgumentList "`"$Source`"", "$Width", "$Height", "$Fps", $BridgeDevice -WindowStyle $style
Write-Output 'bridge started'
pause