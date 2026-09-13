# 用 x86 Manager 在 32 位注册表视图（WOW6432Node）重建桥设备
$log = 'D:\easi-connector\tools\akvcam-x86.log'
Start-Transcript -Path $log -Force
$mgr = 'D:\easi-connector\tools\akvcam913\x86\AkVCamManager.exe'

Write-Output '=== wipe x86-view devices ==='
& $mgr remove-devices 2>&1

Write-Output '=== add device ==='
& $mgr add-device 'EASI-Bridge Camera' 2>&1
& $mgr devices 2>&1

Write-Output '=== add format + update ==='
& $mgr add-format AkVCamVideoDevice0 RGB24 1920 1080 30 2>&1
& $mgr update 2>&1
& $mgr formats AkVCamVideoDevice0 2>&1

Stop-Transcript
