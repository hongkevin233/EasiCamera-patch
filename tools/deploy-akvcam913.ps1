# AkVCam 9.1.3 (DirectShow 版) 部署：需要管理员权限
$log = Join-Path $PSScriptRoot 'akvcam-deploy.log'
Start-Transcript -Path $log -Force

$base = Join-Path $PSScriptRoot 'akvcam913\x64'

Write-Output '=== 1. register DirectShow filters ==='
Start-Process regsvr32 -ArgumentList '/s', "$base\AkVirtualCamera.dll" -Wait
Start-Process regsvr32 -ArgumentList '/s', (Join-Path $PSScriptRoot 'akvcam913\x86\AkVirtualCamera.dll') -Wait
Write-Output 'regsvr32 done'

Write-Output '=== 2. Assistant service ==='
$svc = sc.exe query AkVCamAssistant 2>&1
if ($LASTEXITCODE -ne 0) {
    sc.exe create AkVCamAssistant type= own start= auto binPath= "$base\AkVCamAssistant.exe" displayName= "AkVCam Assistant Service"
    sc.exe start AkVCamAssistant
} else {
    Write-Output 'service exists, ensure running'
    sc.exe start AkVCamAssistant
}
sc.exe query AkVCamAssistant

Write-Output '=== 3. create bridge device ==='
$mgr = "$base\AkVCamManager.exe"
& $mgr add-device 'EASI-Bridge Camera' 2>&1
& $mgr devices 2>&1

$devList = & $mgr devices -p 2>&1
$devId = ($devList | Select-Object -First 1)
Write-Output ("device id: " + $devId)
if ($devId) {
    & $mgr add-format $devId RGB24 1920 1080 30 2>&1
    & $mgr update 2>&1
    & $mgr formats $devId 2>&1
}

Write-Output '=== 4. verify COM registration ==='
reg query "HKCR\CLSID" /f "AkVirtualCamera" /s /d 2>&1 | Select-Object -First 6

Stop-Transcript
