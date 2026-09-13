# easicam resource monitor v2
# v2 additions over v1:
#   - WMI ProcessStopTrace: captures EXIT CODE of EasiCamera.exe at the moment it dies (decisive evidence)
#   - WMI ProcessStartTrace: captures parent pid (who launched EasiCamera)
#   - GDI / USER handle counters (GetGuiResources) to classify the handle leak type
#   - csv now 14 cols: ts,pid,uptime_s,cpu_pct,ws_mb,priv_mb,handles,gdi,user,gpu_proc,gpu_sys,gpu_ded,gpu_sha,note
# exit code cheatsheet:
#   0x00000000 = clean exit / ExitProcess(0)
#   0x40000015 = abort()
#   0x40010004 = DBG_TERMINATE_PROCESS (typical when killed via TerminateProcess)
#   0xC0000005 = access violation (dangling pointer / heap corruption)
#   0xFFFFFFFF = -1
# usage: powershell -NoProfile -ExecutionPolicy Bypass -File monitor-easicam.ps1 [-IntervalSec 2] [-MaxHours 4]
# note: run console AS ADMIN, otherwise exit-code capture is unavailable (degrades to v1 behavior)
# stop: Stop-Process -Id (Get-Content <脚本目录>\..\logs\monitor-easicam.pid)
param(
    [int]$IntervalSec = 2,
    [double]$MaxHours = 4,
    [string]$OutPath = '',
    [int]$GpuEveryN = 5   # sample GPU counters only every N loops (they cost ~2s each round otherwise)
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $OutPath) { $OutPath = Join-Path $PSScriptRoot '..\logs\easicam-monitor-v2.csv' }
$logDir = Split-Path $OutPath -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$PID | Out-File -FilePath (Join-Path $logDir 'monitor-easicam.pid') -Encoding ascii

$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
if (-not $cores -or $cores -lt 1) { $cores = 1 }

if (-not ([System.Management.Automation.PSTypeName]'W32.Gui').Type) {
    Add-Type -Namespace W32 -Name Gui -MemberDefinition '[DllImport("user32.dll")] public static extern uint GetGuiResources(System.IntPtr hProcess, uint uiFlags);'
}

# --- WMI process lifecycle traces (need admin; degrade gracefully) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$hasStop = $false; $hasStart = $false
try {
    Register-CimIndicationEvent -Query "SELECT * FROM Win32_ProcessStopTrace WHERE ProcessName = 'EasiCamera.exe'" -SourceIdentifier EasiStop -ErrorAction Stop | Out-Null
    $hasStop = $true
} catch {}
try {
    Register-CimIndicationEvent -Query "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName = 'EasiCamera.exe'" -SourceIdentifier EasiStart -ErrorAction Stop | Out-Null
    $hasStart = $true
} catch {}
Write-Output "admin=$isAdmin stopTrace=$hasStop startTrace=$hasStart"
if (-not $hasStop) { Write-Output 'WARN: run as ADMIN to capture exit code (decisive evidence)' }

$header = 'ts,pid,uptime_s,cpu_pct,ws_mb,priv_mb,handles,gdi,user,gpu_proc,gpu_sys,gpu_ded,gpu_sha,note'
if (-not (Test-Path $OutPath)) { $header | Out-File -FilePath $OutPath -Encoding ascii }
$ts0 = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
Add-Content -Path $OutPath -Value "$ts0,0,0,-1,0,0,0,0,0,-1,-1,-1,-1,MONITOR v2 start admin=$isAdmin stop=$hasStop start=$hasStart"

function Get-Target { Get-Process EasiCamera -ErrorAction SilentlyContinue | Select-Object -First 1 }

$seenPid = 0
$seenStart = $null
$prevPid = 0
$prevCpuMs = -1.0
$prevTs = $null
$loopN = 0
$deadline = (Get-Date).AddHours($MaxHours)

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $IntervalSec
    $now = Get-Date
    $ts = $now.ToString('yyyy-MM-dd HH:mm:ss.fff')

    # stop sentinel: create this file from any shell to stop the (possibly elevated) monitor
    $stopSentinel = Join-Path $logDir 'monitor-easicam.stop'
    if (Test-Path $stopSentinel) {
        Remove-Item $stopSentinel -Force
        Add-Content -Path $OutPath -Value "$ts,0,0,-1,0,0,0,0,0,-1,-1,-1,-1,MONITOR stopped by sentinel"
        break
    }

    # drain WMI events first: STOPPED arrives the instant the process dies
    Get-Event -SourceIdentifier EasiStop -ErrorAction SilentlyContinue | ForEach-Object {
        $e = $_.SourceEventArgs.NewEvent
        $code = [int64]$e.ExitCode
        $hex = '0x{0:X8}' -f ($code -band 0xFFFFFFFF)
        $ets = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -Path $OutPath -Value "$ets,$($e.ProcessId),0,-1,0,0,0,0,0,-1,-1,-1,-1,STOPPED exitcode=$code ($hex)"
        Remove-Event -EventIdentifier $_.EventIdentifier -ErrorAction SilentlyContinue
        if ([int]$e.ProcessId -eq $seenPid) { $seenPid = 0; $seenStart = $null; $prevPid = 0; $prevCpuMs = -1.0; $prevTs = $null }
    }
    Get-Event -SourceIdentifier EasiStart -ErrorAction SilentlyContinue | ForEach-Object {
        $e = $_.SourceEventArgs.NewEvent
        $ets = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -Path $OutPath -Value "$ets,$($e.ProcessId),0,-1,0,0,0,0,0,-1,-1,-1,-1,STARTED parent=$($e.ParentProcessId)"
        Remove-Event -EventIdentifier $_.EventIdentifier -ErrorAction SilentlyContinue
    }

    $p = Get-Target

    if (-not $p) {
        if ($seenPid -ne 0 -and $seenStart) {
            $life = [math]::Round(($now - $seenStart).TotalSeconds, 1)
            Add-Content -Path $OutPath -Value "$ts,0,0,-1,0,0,0,0,0,-1,-1,-1,-1,PID $seenPid GONE uptime=${life}s"
            $seenPid = 0; $seenStart = $null; $prevPid = 0; $prevCpuMs = -1.0; $prevTs = $null
        } else {
            Add-Content -Path $OutPath -Value "$ts,0,0,-1,0,0,0,0,0,-1,-1,-1,-1,no EasiCamera"
        }
        continue
    }

    if ($p.Id -ne $seenPid) {
        Add-Content -Path $OutPath -Value "$ts,$($p.Id),0,-1,0,0,0,0,0,-1,-1,-1,-1,NEW PID start=$($p.StartTime.ToString('HH:mm:ss'))"
        $seenPid = $p.Id; $seenStart = $p.StartTime
        $prevPid = 0; $prevCpuMs = -1.0; $prevTs = $null
    }

    $uptime = [math]::Round(($now - $p.StartTime).TotalSeconds, 1)
    $wsMb = [math]::Round($p.WorkingSet64 / 1MB, 1)
    $privMb = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)

    # instantaneous cpu pct (delta of total processor time, normalized to task-manager scale)
    $cpuPct = -1
    if ($prevPid -eq $p.Id -and $prevCpuMs -ge 0 -and $prevTs) {
        $dMs = $p.TotalProcessorTime.TotalMilliseconds - $prevCpuMs
        $dTs = ($now - $prevTs).TotalSeconds
        if ($dTs -gt 0) { $cpuPct = [math]::Round(($dMs / 1000.0) / $dTs / $cores * 100.0, 1) }
    }
    $prevPid = $p.Id; $prevCpuMs = $p.TotalProcessorTime.TotalMilliseconds; $prevTs = $now

    # gdi/user handle counts (independent limits, default 10000 each) - leak classification
    $gdi = 0; $usr = 0
    try { $gdi = [W32.Gui]::GetGuiResources($p.Handle, 0) } catch {}
    try { $usr = [W32.Gui]::GetGuiResources($p.Handle, 1) } catch {}

    # gpu: one full capture, split into per-pid and system-wide
    # Get-Counter on GPU Engine enumerates hundreds of instances (~2s); sample only every N loops
    $gpuProc = -1; $gpuSys = -1; $gpuDed = -1; $gpuSha = -1
    $loopN++
    if ($GpuEveryN -le 0 -or ($loopN % $GpuEveryN) -eq 0) {
        $esc = "pid_$($p.Id)"
        try {
            $c = Get-Counter '\GPU Engine(*)\Utilization Percentage','\GPU Adapter Memory(*)\Dedicated Usage','\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop
            $samples = $c.CounterSamples
            $mine = $samples | Where-Object { $_.InstanceName -like "$esc*" }
            $s1 = ($mine | Where-Object { $_.Path -like '*\gpu engine*' } | Measure-Object CookedValue -Sum).Sum
            if ($null -ne $s1) { $gpuProc = [math]::Round($s1, 1) }
            $s2 = ($samples | Where-Object { $_.Path -like '*\gpu engine*' } | Measure-Object CookedValue -Sum).Sum
            if ($null -ne $s2) { $gpuSys = [math]::Round($s2, 1) }
            $v = ($samples | Where-Object { $_.Path -like '*dedicated usage*' } | Measure-Object CookedValue -Sum).Sum
            if ($null -ne $v) { $gpuDed = [math]::Round($v / 1MB, 1) }
            $v = ($samples | Where-Object { $_.Path -like '*shared usage*' } | Measure-Object CookedValue -Sum).Sum
            if ($null -ne $v) { $gpuSha = [math]::Round($v / 1MB, 1) }
        } catch {}
    }

    Add-Content -Path $OutPath -Value "$ts,$seenPid,$uptime,$cpuPct,$wsMb,$privMb,$($p.HandleCount),$gdi,$usr,$gpuProc,$gpuSys,$gpuDed,$gpuSha,"
}
