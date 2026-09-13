# AkVCam 部署状态检查
$mgr = 'D:\easi-connector\tools\akvcam\x64\AkVCamManager.exe'
Write-Output '--- COM classes (broader search) ---'
reg query "HKCR\CLSID" /f "AkVirtualCamera" /s /d 2>&1 | Select-Object -First 6
reg query "HKLM\SOFTWARE\Classes\CLSID" /f "AkVCam" /s /d 2>&1 | Select-Object -First 6
Write-Output '--- devices ---'
& $mgr devices 2>&1
Write-Output "devices exit: $LASTEXITCODE"
Write-Output '--- assistant service ---'
sc.exe query AkVCamAssistant 2>&1 | Select-Object -First 5
Write-Output '--- HKCU fallback config ---'
reg query "HKCU\SOFTWARE\AkVirtualCamera" /s 2>&1 | Select-Object -First 10
