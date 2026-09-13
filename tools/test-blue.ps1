# 最小链路实验：纯蓝帧喂 AkVCam stream，10 秒
$mgr = 'D:\easi-connector\tools\akvcam913\x64\AkVCamManager.exe'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $mgr
$psi.Arguments = 'stream AkVCamVideoDevice1 RGB24 1920 1080'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)

# RGB24 = BGR 字节序：纯蓝 = B=255
$frame = New-Object byte[] (1920 * 1080 * 3)
for ($i = 2; $i -lt $frame.Length; $i += 3) { $frame[$i] = 255 }
$stdin = $p.StandardInput.BaseStream
Write-Output 'feeding blue frames 10s...'
$end = [DateTime]::Now.AddSeconds(10)
while ([DateTime]::Now -lt $end -and -not $p.HasExited) {
    $stdin.Write($frame, 0, $frame.Length)
    $stdin.Flush()
    Start-Sleep -Milliseconds 33
}
if (-not $p.HasExited) { $p.Kill() }
Write-Output 'done'
