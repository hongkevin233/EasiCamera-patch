# AkVCam 9.1.3 -> 9.4.1 切换：需要管理员权限（UAC）
# 背景：9.1.3 每帧新建管道+线程导致句柄泄漏(~63/s)和 abort(0x40000015)@0x142f6c
# 9.4.1 官方重写 IPC（socket 长连接复用），架构级修复
$log = 'D:\easi-connector\tools\akvcam-switch-941.log'
Start-Transcript -Path $log -Force

$old = 'D:\easi-connector\tools\akvcam913'
$new = 'D:\easi-connector\tools\akvcam'

Write-Output '=== 0. kill all assistant instances (service + leftovers) ==='
Get-Process AkVCamAssistant -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Output ("killing assistant pid=" + $_.Id + " path=" + $_.Path)
    Stop-Process -Id $_.Id -Force
}

Write-Output '=== 1. unregister 9.1.3 DLLs (x64 + x86) ==='
Start-Process regsvr32 -ArgumentList '/u', '/s', "$old\x64\AkVirtualCamera.dll" -Wait
Start-Process regsvr32 -ArgumentList '/u', '/s', "$old\x86\AkVirtualCamera.dll" -Wait
Write-Output '9.1.3 unregistered'

Write-Output '=== 2. register 9.4.1 DLLs (x64 + x86) ==='
Start-Process regsvr32 -ArgumentList '/s', "$new\x64\AkVirtualCamera.dll" -Wait
Start-Process regsvr32 -ArgumentList '/s', "$new\x86\AkVirtualCamera.dll" -Wait
Write-Output '9.4.1 registered'

Write-Output '=== 3. repoint service to 9.4.1 assistant ==='
sc.exe stop AkVCamAssistant | Out-Null
Start-Sleep -Seconds 1
sc.exe config AkVCamAssistant binPath= "$new\x64\AkVCamAssistant.exe"
sc.exe qc AkVCamAssistant
sc.exe start AkVCamAssistant
sc.exe query AkVCamAssistant

Write-Output '=== 4. verify device with 9.4.1 manager ==='
& "$new\x64\AkVCamManager.exe" devices
& "$new\x64\AkVCamManager.exe" formats AkVCamVideoDevice0
& "$new\x64\AkVCamManager.exe" update
Write-Output '=== 5. verify COM registration paths ==='
reg query "HKCR\CLSID" /f "AkVirtualCamera" /s /d 2>&1 | Select-Object -First 4
Get-Process AkVCamAssistant -ErrorAction SilentlyContinue | Select-Object Id, Path

Stop-Transcript
Write-Output 'DONE'
