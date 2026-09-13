# ============================================================
# switch-913.ps1 - 黑屏根因实验：akvcam 9.4.1 <-> 9.1.3 一键切换
#
# 【根因结论（源码实锤，notes\akvirtualcamera-9.1.3 / -9.4.1 完整源码树对比）】
#   9.4.1 重写 dshow 时删除了 IKsPropertySet 实现：
#     - 9.1.3 有 dshow/VirtualCamera/src/propertyset.h/.cpp，pin.cpp:402 挂接
#     - 9.4.1 windows/dshow/BaseFilter/src/pin.cpp 的 QueryInterface 不再响应
#       IID_IKsPropertySet（全树 grep 零匹配）
#   ffmpeg/希沃 枚举输出 pin 时必须查到：
#     IKsPropertySet_Get(AMPROPSETID_Pin, AMPROPERTY_PIN_CATEGORY) = PIN_CATEGORY_CAPTURE
#   否则跳过该 pin → "Could not find output pin" → 建图失败黑屏，
#   且 ffmpeg stdout 管道无人消费 → rtbufsize 102% 满溢掉帧（实报 311 次）。
#
# 【实验目的】切回 9.1.3（有 IKsPropertySet），希沃若出画面 → 根因锤死
#   → 投入 9.4.1 编译修复（移植 propertyset.h/.cpp + pin QueryInterface 挂接）。
#
# 【9.1.3 已知缺陷】每帧新建管道+线程：句柄泄漏 ~63/s，长跑崩溃
#   abort 0x40000015 @ 0x142f6c。验证出画面后尽快 -Revert 回 9.4.1，勿久留！
#
# 【用法】（非管理员运行会自动弹 UAC 自提权，结果写 tools\switch-913-result.txt）
#   powershell -ExecutionPolicy Bypass -File tools\switch-913.ps1           # 切 9.1.3
#   powershell -ExecutionPolicy Bypass -File tools\switch-913.ps1 -Revert   # 切回 9.4.1
#
# 【两版差异备忘】
#   9.4.1: DLL=tools\akvcam\{x86,x64}\AkVirtualCamera.dll
#          manager=tools\akvcam\x86\AkVCamManager.exe（stream 用）
#          assistant：无 SCM 服务，manager/DLL 按需自动拉起
#   9.1.3: DLL=tools\akvcam913\{x86,x64}\AkVirtualCamera.dll
#          manager=tools\akvcam913\x86\AkVCamManager.exe（stream 用）
#          assistant：需要 SCM 服务 AkVCamAssistant
#          → akvcam913\x64\AkVCamAssistant.exe（type= own start= auto）
#
# 【关键约束】
#   - x86 DLL 注册必须 MTA（SysWOW64 powershell -MTA + reg-dll-mta.ps1），
#     regsvr32 STA 宿主会 RPC_E_CHANGED_MODE
#   - x86 注册表视图（WOW6432Node）Instance 列表独立，须用 x86 manager 重建设备
#   - 设备 caps 必须 30fps（25fps 触发希沃堆损坏 0xc0000374 窗口透明）
#   - FilterMapper2 键 {C1D403C6-...} 必须存在（fix-com-register.ps1 已补，勿删）
# ============================================================
param([switch]$Revert, [switch]$ServiceOnly)

$T = 'D:\easi-connector\tools'
$B = 'D:\easi-connector\connector'
$Log = "$T\switch-913-result.txt"

# ---- 自提权：非管理员 → 弹 UAC 重跑自身，等待后回显日志 ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $flags = @()
    if ($Revert) { $flags += '-Revert' }
    if ($ServiceOnly) { $flags += '-ServiceOnly' }
    $arg = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`" $($flags -join ' ')".TrimEnd()
    try {
        Start-Process powershell -Verb RunAs -Wait -ArgumentList $arg
        Get-Content $Log
    } catch { Write-Output "UAC 被取消或提权失败: $_" }
    exit
}

# -ServiceOnly 快速通道：只重建 assistant 服务 + 重启桥（几秒完成，不重跑注册/设备）
if ($ServiceOnly) {
    "[$(Get-Date -Format HH:mm:ss)] ===== service-only rebuild =====" | Set-Content $Log
    sc.exe delete AkVCamAssistant 2>&1 | Out-Null
    Start-Sleep 2   # 等 delete 完成，避免 MARKED_FOR_DELETE 导致 create 静默失败
    sc.exe create AkVCamAssistant type= own start= auto binPath= "$T\akvcam913\x64\AkVCamAssistant.exe" displayName= "AkVCam Assistant Service" 2>&1 | Out-Null
    sc.exe start AkVCamAssistant 2>&1 | Out-Null
    Start-Sleep 1
    "[$(Get-Date -Format HH:mm:ss)] service: {0}" -f ((sc.exe query AkVCamAssistant | Select-String 'STATE') -join ' ') | Add-Content $Log
    & "$B\bridge.ps1"
    Start-Sleep 2
    ("[$(Get-Date -Format HH:mm:ss)] processes: {0}" -f ((Get-Process ffmpeg,AkVCamManager,AkVCamAssistant -EA SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ',')) | Add-Content $Log
    'DONE. 重启希沃确认画面。' | Add-Content $Log
    exit
}

$ErrorActionPreference = 'Continue'
"[$(Get-Date -Format HH:mm:ss)] ===== switch to $(if($Revert){'9.4.1'}else{'9.1.3'}) =====" | Set-Content $Log
function Step($m) { "[$(Get-Date -Format HH:mm:ss)] $m" | Add-Content $Log }

# ---- 参数表 ----
if ($Revert) {
    $dll64="$T\akvcam\x64\AkVirtualCamera.dll";     $dll86="$T\akvcam\x86\AkVirtualCamera.dll"
    $mgr64="$T\akvcam\x64\AkVCamManager.exe";       $mgr="$T\akvcam\x86\AkVCamManager.exe"
    $old64="$T\akvcam913\x64\AkVirtualCamera.dll";  $old86="$T\akvcam913\x86\AkVirtualCamera.dll"
    $newMgr='tools\akvcam\x86\AkVCamManager.exe';   $oldMgr='tools\akvcam913\x86\AkVCamManager.exe'
} else {
    $dll64="$T\akvcam913\x64\AkVirtualCamera.dll";  $dll86="$T\akvcam913\x86\AkVirtualCamera.dll"
    $mgr64="$T\akvcam913\x64\AkVCamManager.exe";    $mgr="$T\akvcam913\x86\AkVCamManager.exe"
    $old64="$T\akvcam\x64\AkVirtualCamera.dll";     $old86="$T\akvcam\x86\AkVirtualCamera.dll"
    $newMgr='tools\akvcam913\x86\AkVCamManager.exe'; $oldMgr='tools\akvcam\x86\AkVCamManager.exe'
}
$ps64 = 'powershell.exe'
$ps86 = "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"

# 1. 停管线（bridge 进程 + assistant + 服务）
Step '1. kill ffmpeg/AkVCamManager/AkVCamAssistant + stop service'
Get-Process ffmpeg,AkVCamManager,AkVCamAssistant -ErrorAction SilentlyContinue | Stop-Process -Force
sc.exe stop AkVCamAssistant 2>&1 | Out-Null

# 2. MTA 反注册旧版 DLL（清掉旧版独有的 COM 键，如 9.4.1 的 registerFilter 类别项）
Step '2. unregister old dlls (MTA)'
& $ps64 -MTA -NoProfile -ExecutionPolicy Bypass -File "$T\reg-dll-mta.ps1" -DllPath $old64 -OutFile "$T\reg-u-x64.txt" -Unregister | Out-Null
& $ps86 -MTA -NoProfile -ExecutionPolicy Bypass -File "$T\reg-dll-mta.ps1" -DllPath $old86 -OutFile "$T\reg-u-x86.txt" -Unregister | Out-Null
Step ("  hr: x64={0} x86={1}" -f (Get-Content "$T\reg-u-x64.txt" -EA SilentlyContinue), (Get-Content "$T\reg-u-x86.txt" -EA SilentlyContinue))

# 3. MTA 注册新版 DLL
Step '3. register new dlls (MTA, x64=64bit ps / x86=SysWOW64 ps)'
& $ps64 -MTA -NoProfile -ExecutionPolicy Bypass -File "$T\reg-dll-mta.ps1" -DllPath $dll64 -OutFile "$T\reg-hr-x64.txt" | Out-Null
& $ps86 -MTA -NoProfile -ExecutionPolicy Bypass -File "$T\reg-dll-mta.ps1" -DllPath $dll86 -OutFile "$T\reg-hr-x86.txt" | Out-Null
Step ("  hr: x64={0} x86={1}" -f (Get-Content "$T\reg-hr-x64.txt" -EA SilentlyContinue), (Get-Content "$T\reg-hr-x86.txt" -EA SilentlyContinue))

# 4. assistant 服务（9.1.3 需要 SCM；9.4.1 删除、按需自动拉起）
Step '4. assistant service'
sc.exe delete AkVCamAssistant 2>&1 | Out-Null
if ($Revert) {
    Step '  deleted (9.4.1 auto-start mode)'
} else {
    sc.exe create AkVCamAssistant type= own start= auto binPath= "$T\akvcam913\x64\AkVCamAssistant.exe" displayName= "AkVCam Assistant Service" 2>&1 | Out-Null
    sc.exe start AkVCamAssistant 2>&1 | Out-Null
    $q = (sc.exe query AkVCamAssistant | Select-String 'STATE') -join ' '
    Step ("  {0}" -f $q.Trim())
}

# 5. 重建设备（64 视图 + 32 视图各来一遍；caps 固定 30fps）
#    注意：先清 prefs（两视图，REG_PREFIX=SOFTWARE\Webcamoid\VirtualCamera，
#    9.1.3/9.4.1 相同），否则残留键会让 add-device 分配出 AkVCamVideoDevice1，
#    而 bridge/格式写死 Device0 → stream 秒退
Step '5. wipe prefs + rebuild devices (64-view + x86-view, RGB24 1920x1080 30fps)'
reg delete "HKLM\SOFTWARE\Webcamoid" /f 2>&1 | Out-Null
reg delete "HKLM\SOFTWARE\WOW6432Node\Webcamoid" /f 2>&1 | Out-Null
foreach ($m in @($mgr64, $mgr)) {
    & $m remove-devices 2>&1 | Out-Null
    & $m add-device 'EASI-Bridge Camera' 2>&1 | Out-Null
    & $m add-format AkVCamVideoDevice0 RGB24 1920 1080 30 2>&1 | Out-Null
    & $m update 2>&1 | Out-Null
    Step ("  [{0}] devices: {1}" -f (Split-Path (Split-Path $m -Parent) -Leaf), ((& $m devices) -join ', '))
}

# 6. run-bridge.cmd 指向对应版本的 manager（先备份 .bak）
Step '6. rewrite run-bridge.cmd manager path'
$rb = "$B\run-bridge.cmd"
Copy-Item $rb "$rb.bak" -Force
$txt = [IO.File]::ReadAllText($rb).Replace($oldMgr, $newMgr)
[IO.File]::WriteAllText($rb, $txt)
if ($txt.Contains($newMgr)) { Step "  -> $newMgr" } else { Step '  WARN: replace failed, check run-bridge.cmd!' }

# 7. 重启桥
Step '7. restart bridge'
& "$B\bridge.ps1"
Start-Sleep 2
$procs = (Get-Process ffmpeg,AkVCamManager,AkVCamAssistant -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ','
Step ("  processes: {0}" -f $(if ($procs) { $procs } else { 'NONE (bridge 未启动, 检查 run-bridge.cmd)' }))

Step 'DONE. 请重启希沃 EasiCamera，确认 EASI-Bridge Camera 是否出画面。'
if (-not $Revert) {
    Step '提醒：9.1.3 句柄泄漏 ~63/s，验证完画面立即执行 switch-913.ps1 -Revert 回 9.4.1！'
}
