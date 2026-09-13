# ============================================================
# smoke50.ps1 - 50 次快速启停验证重连路径
#
# 每轮: 启动 EasiCamera -> 轮询新日志目录等 "Camera FirstVideoFrameCame"
#       -> 保持 2s -> 优雅关闭(CloseMainWindow, 10s 超时强杀) -> 间歇 0.5s
# 全程快照 ffmpeg/AkVCamManager/AkVCamAssistant 句柄数(基线 + 每 10 轮 + 收尾)
# 结果: tools\smoke50-result.csv / tools\smoke50-handles.csv
#
# 用法: powershell -ExecutionPolicy Bypass -File tools\smoke50.ps1 [-Cycles 50]
# 前置: 桥必须活着(run-bridge.cmd), obs64 虚拟摄像头已开启
# ============================================================
param(
    [int]$Cycles = 50,
    [int]$HoldMs = 2000,
    [int]$FrameTimeoutSec = 25
)

$exe     = 'D:\easi-connector\easi-soft\EasiCamera_2.1.0.4410\Main\EasiCamera.exe'
$workdir = Split-Path $exe -Parent
$logRoot = "$env:APPDATA\Seewo\EasiCamera\Log"
$targets = @('ffmpeg','AkVCamManager','AkVCamAssistant')

function Snap($tag) {
    $rows = foreach ($n in $targets) {
        $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) { [pscustomobject]@{ tag=$tag; name=$n; pid=$p.Id; handles=$p.Handles; threads=$p.Threads.Count } }
        else    { [pscustomobject]@{ tag=$tag; name=$n; pid=-1;  handles=-1;  threads=-1 } }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 120 | Write-Output
    return $rows
}

# ---- 前置检查: 桥必须活着 ----
$alive = Get-Process ffmpeg,AkVCamManager -ErrorAction SilentlyContinue
if (@($alive).Count -lt 2) {
    Write-Output 'FATAL: ffmpeg/AkVCamManager 不全, 先启动桥 (run-bridge.cmd) 再跑'
    exit 1
}
Write-Output "smoke start: $Cycles cycles, hold ${HoldMs}ms, frame timeout ${FrameTimeoutSec}s"
$allSnaps = @()
$allSnaps += Snap 'BASE'

$results = @()
$failStreak = 0
for ($i = 1; $i -le $Cycles; $i++) {
    $before = (Get-ChildItem $logRoot -Directory -ErrorAction SilentlyContinue).Name
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Process $exe -WorkingDirectory $workdir | Out-Null

    # 等新日志目录(目录名 yyyyMMdd_HHmmss,PID)
    $dir = $null
    while ($sw.Elapsed.TotalSeconds -lt $FrameTimeoutSec) {
        $d = Get-ChildItem $logRoot -Directory | Where-Object { $_.Name -notin $before } |
             Sort-Object Name | Select-Object -Last 1
        if ($d) { $dir = $d; break }
        Start-Sleep -Milliseconds 200
    }

    $ok = $false; $frameMs = -1; $why = 'no-logdir'
    if ($dir) {
        $why = 'no-firstframe'
        while ($sw.Elapsed.TotalSeconds -lt $FrameTimeoutSec) {
            $t = Join-Path $dir.FullName 'last_info.txt'
            if (Test-Path $t) {
                $c = Get-Content $t -Raw -ErrorAction SilentlyContinue
                if ($c -match 'FirstVideoFrameCame') { $ok = $true; $frameMs = [int]$sw.ElapsedMilliseconds; $why=''; break }
                if ($c -match 'Could not find output pin') { $why = 'no-output-pin'; break }
                if ($c -match 'fatal|Fatal|FATAL') { $why = 'fatal-log'; break }
            }
            Start-Sleep -Milliseconds 200
        }
        if (-not $ok -and $why -eq 'no-firstframe' -and $sw.Elapsed.TotalSeconds -ge $FrameTimeoutSec) { $why = 'timeout' }
    }

    Start-Sleep -Milliseconds $HoldMs

    # 优雅关闭, 10s 不退则强杀
    $mode = 'none'
    $p = Get-Process -Name 'EasiCamera' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) {
        $null = $p.CloseMainWindow()
        if (-not $p.WaitForExit(10000)) { $p | Stop-Process -Force; $p.WaitForExit(5000) | Out-Null; $mode = 'kill' }
        else { $mode = 'close' }
    }
    Start-Sleep -Milliseconds 500

    $results += [pscustomobject]@{ cycle=$i; ok=$ok; frameMs=$frameMs; close=$mode; why=$why; logdir=$dir.Name }
    Write-Output ('{0,3}/{1}  ok={2}  firstFrame={3}ms  close={4} {5}' -f $i, $Cycles, $ok, $frameMs, $mode, $why)

    if ($ok) { $failStreak = 0 } else {
        $failStreak++
        if ($failStreak -ge 3) { Write-Output '连续 3 轮失败, 中止 (链路疑似断了)'; break }
    }
    if ($i % 10 -eq 0) { $allSnaps += Snap "CY$i" }
}

$allSnaps += Snap 'END'

$pass = @($results | Where-Object ok).Count
$avg  = if ($pass) { [int](($results | Where-Object ok | Measure-Object frameMs -Average).Average) } else { -1 }
$mx   = if ($pass) { ($results | Where-Object ok | Measure-Object frameMs -Maximum).Maximum } else { -1 }
Write-Output ''
Write-Output ("==== SUMMARY: PASS {0}/{1}  firstFrame avg={2}ms max={3}ms ====" -f $pass, @($results).Count, $avg, $mx)

# 句柄对比: BASE vs END (按 name 对齐, 看增量)
$base = $allSnaps | Where-Object tag -eq 'BASE'
$end  = $allSnaps | Where-Object tag -eq 'END'
foreach ($n in $targets) {
    $b = $base | Where-Object name -eq $n | Select-Object -First 1
    $e = $end  | Where-Object name -eq $n | Select-Object -First 1
    if ($b -and $e) {
        $dHandles = if ($e.handles -ge 0 -and $b.handles -ge 0) { $e.handles - $b.handles } else { 'N/A(进程没了)' }
        Write-Output ('handles {0,-16}: {1} -> {2}  (Δ{3})' -f $n, $b.handles, $e.handles, $dHandles)
    }
}

$results     | Export-Csv "$PSScriptRoot\smoke50-result.csv"  -NoTypeInformation -Encoding UTF8
$allSnaps    | Export-Csv "$PSScriptRoot\smoke50-handles.csv" -NoTypeInformation -Encoding UTF8
Write-Output 'result -> tools\smoke50-result.csv, handles -> tools\smoke50-handles.csv'
