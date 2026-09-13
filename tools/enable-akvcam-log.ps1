# enable-akvcam-log.ps1
# 打开 akvirtualcamera debug 日志（需管理员）。
# loglevel=7 (AKVCAM_LOGLEVEL_DEBUG, REG_DWORD, 64位视图 HKLM\SOFTWARE\Webcamoid\VirtualCamera)
# logfile 指到固定目录（setLogFile 会自动加时间戳后缀，每个进程一个文件）
# 同时杀掉 AkVCamAssistant 让它以新日志设置重启。

$ErrorActionPreference = 'Continue'
$R = 'D:\easi-connector\tools\akvcam\logs\enable-log-result.txt'
$LogDir = 'D:\easi-connector\tools\akvcam\logs'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
"=== enable akvcam log $(Get-Date) ===" | Out-File $R -Encoding utf8

"--- set loglevel=7 ---" | Out-File $R -Append -Encoding utf8
reg add "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /v loglevel /t REG_DWORD /d 7 /f 2>&1 | Out-File $R -Append -Encoding utf8

"--- set logfile ---" | Out-File $R -Append -Encoding utf8
reg add "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /v logfile /t REG_SZ /d "D:\easi-connector\tools\akvcam\logs\akvcam.log" /f 2>&1 | Out-File $R -Append -Encoding utf8

"--- verify ---" | Out-File $R -Append -Encoding utf8
reg query "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /v loglevel 2>&1 | Out-File $R -Append -Encoding utf8
reg query "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /v logfile 2>&1 | Out-File $R -Append -Encoding utf8

"--- restart assistant ---" | Out-File $R -Append -Encoding utf8
taskkill /f /im AkVCamAssistant.exe 2>&1 | Out-File $R -Append -Encoding utf8

"DONE" | Out-File $R -Append -Encoding utf8
