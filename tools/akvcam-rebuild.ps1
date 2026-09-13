# 清理 9.4.1 残留，统一为 9.1.3，重建桥设备
$log = 'D:\easi-connector\tools\akvcam-rebuild.log'
Start-Transcript -Path $log -Force

Write-Output '=== 1. unregister 9.4.1 filters ==='
Start-Process regsvr32 -ArgumentList '/s','/u','D:\easi-connector\tools\akvcam\x64\AkVirtualCamera.dll' -Wait
Start-Process regsvr32 -ArgumentList '/s','/u','D:\easi-connector\tools\akvcam\x86\AkVirtualCamera.dll' -Wait
Write-Output 'unregistered 9.4.1'

Write-Output '=== 2. wipe all devices (shared config) ==='
$mgr = 'D:\easi-connector\tools\akvcam913\x64\AkVCamManager.exe'
& $mgr remove-devices 2>&1

Write-Output '=== 3. recreate bridge device with 9.1.3 ==='
& $mgr add-device 'EASI-Bridge Camera' 2>&1
& $mgr devices 2>&1
& $mgr add-format AkVCamVideoDevice0 RGB24 1920 1080 30 2>&1
& $mgr update 2>&1
& $mgr formats AkVCamVideoDevice0 2>&1

Write-Output '=== 4. re-register 9.1.3 filters (ensure fresh) ==='
Start-Process regsvr32 -ArgumentList '/s','D:\easi-connector\tools\akvcam913\x64\AkVirtualCamera.dll' -Wait
Start-Process regsvr32 -ArgumentList '/s','D:\easi-connector\tools\akvcam913\x86\AkVirtualCamera.dll' -Wait

Write-Output '=== 5. restart assistant ==='
sc.exe stop AkVCamAssistant 2>&1 | Out-Null
Start-Sleep -Seconds 1
sc.exe start AkVCamAssistant 2>&1 | Select-Object -First 3

Stop-Transcript
