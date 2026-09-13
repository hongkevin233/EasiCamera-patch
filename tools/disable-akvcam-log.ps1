# disable-akvcam-log.ps1
# 回滚 debug 日志：loglevel -> 0xFFFFFFFF (-1, AKVCAM_LOGLEVEL_DEFAULT)，删 logfile 键。
# 修复：freopen CONOUT$ 在 GUI 宿主（希沃）里失败会关闭 stdout/stderr，
# 后续 fwrite/setvbuf 触发 CRT invalid parameter -> abort -> 0xc0000409 闪退。

$ErrorActionPreference = 'Continue'
$R = 'D:\easi-connector\tools\akvcam\logs\disable-log-result.txt'

"=== disable akvcam log $(Get-Date) ===" | Out-File $R -Encoding utf8

"--- set loglevel=0xFFFFFFFF (-1) ---" | Out-File $R -Append -Encoding utf8
reg add "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /v loglevel /t REG_DWORD /d 4294967295 /f 2>&1 | Out-File $R -Append -Encoding utf8

"--- delete logfile ---" | Out-File $R -Append -Encoding utf8
reg delete "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /v logfile /f 2>&1 | Out-File $R -Append -Encoding utf8

"--- verify ---" | Out-File $R -Append -Encoding utf8
reg query "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /v loglevel 2>&1 | Out-File $R -Append -Encoding utf8
reg query "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /v logfile 2>&1 | Out-File $R -Append -Encoding utf8

"DONE" | Out-File $R -Append -Encoding utf8
