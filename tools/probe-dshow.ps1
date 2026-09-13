# 链路抓帧二分验证：DirectShow 抓 EASI-Bridge 输出 N 帧
param(
    [string]$Device = 'EASI-Bridge Camera',
    [int]$Frames = 30,
    [int]$TimeoutSec = 30,
    [string]$Out = 'D:\easi-connector\tools\probe-out.mp4'
)
$ff = 'D:\easi-connector\tools\ffmpeg\ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe'
if (Test-Path $Out) { Remove-Item $Out -Force }
& $ff -hide_banner -loglevel error -f dshow -i "video=$Device" -frames:v $Frames -y $Out
if (Test-Path $Out) {
    $f = Get-Item $Out
    Write-Output ("OK size={0} bytes" -f $f.Length)
    & $ff -hide_banner -i $Out -frames:v 1 -y 'D:\easi-connector\tools\probe-last.png' 2>$null
} else {
    Write-Output 'FAIL: no output file'
}
