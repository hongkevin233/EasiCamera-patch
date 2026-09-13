# 删除 9.1.3 遗留的 AkVCamAssistant SCM 服务（9.4.1 不需要服务，assistant 按需自动拉起）
$log = 'D:\easi-connector\tools\akvcam-service-delete.log'
Start-Transcript -Path $log -Force
sc.exe stop AkVCamAssistant
Start-Sleep -Seconds 1
# 清理孤儿 assistant 进程（SCM 1053 超时遗留，LocalSystem 权限需提权才能杀）
Get-Process AkVCamAssistant -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Output ("Killing orphan assistant PID " + $_.Id)
    Stop-Process -Id $_.Id -Force
}
sc.exe delete AkVCamAssistant
Start-Sleep -Seconds 1
sc.exe query AkVCamAssistant
Stop-Transcript
Write-Output 'DONE'
