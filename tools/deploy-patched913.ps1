# Deploy patched AkVCam 9.1.3 binaries (persistent-pipe fix). Requires admin.
$ErrorActionPreference = 'Continue'
$log = 'D:\easi-connector\tools\akvcam-patch-deploy.log'
Start-Transcript -Path $log -Force

Write-Output '=== 1. stop AkVCamAssistant service ==='
sc.exe stop AkVCamAssistant
Start-Sleep -Seconds 3
Get-Process AkVCamAssistant -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
sc.exe query AkVCamAssistant | Select-String STATE

Write-Output '=== 2. copy patched binaries ==='
Copy-Item 'D:\easi-connector\build913-x86\build\x86\Release\*' 'D:\easi-connector\tools\akvcam913\x86\' -Force
Copy-Item 'D:\easi-connector\build913-x64\build\x64\Release\*' 'D:\easi-connector\tools\akvcam913\x64\' -Force
Get-ChildItem 'D:\easi-connector\tools\akvcam913\x86', 'D:\easi-connector\tools\akvcam913\x64' |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize

Write-Output '=== 3. re-register DirectShow DLLs ==='
Start-Process regsvr32 -ArgumentList '/s', 'D:\easi-connector\tools\akvcam913\x64\AkVirtualCamera.dll' -Wait
Start-Process regsvr32 -ArgumentList '/s', 'D:\easi-connector\tools\akvcam913\x86\AkVirtualCamera.dll' -Wait
Write-Output 'regsvr32 done'

Write-Output '=== 4. start service ==='
sc.exe start AkVCamAssistant
Start-Sleep -Seconds 2
sc.exe query AkVCamAssistant | Select-String STATE

Write-Output '=== 5. verify device ==='
& 'D:\easi-connector\tools\akvcam913\x64\AkVCamManager.exe' devices

Stop-Transcript
