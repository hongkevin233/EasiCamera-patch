$log = 'D:\easi-connector\tools\akvcam-format.log'
Start-Transcript -Path $log -Force
$mgr = 'D:\easi-connector\tools\akvcam913\x64\AkVCamManager.exe'
& $mgr add-format AkVCamVideoDevice1 RGB24 1920 1080 30 2>&1
& $mgr update 2>&1
& $mgr formats AkVCamVideoDevice1 2>&1
Stop-Transcript
