# COM 注册修复（需管理员）：在已提权的 PowerShell 窗口中运行
# 第 1 步：恢复 quartz.dll 的 COM 注册（本机缺失 CLSID_FilterMapper2，导致 akvcam registerFilter 失败回滚）
# 第 2 步：用 MTA 宿主直接调 akvcam DShow 插件的 DllRegisterServer（regsvr32 是 STA 宿主，会触发 RPC_E_CHANGED_MODE）

$ErrorActionPreference = 'Continue'
$work = 'D:\easi-connector\tools'
Start-Transcript "$work\fix-com-register.log" -Force

Write-Host '===== 第 1 步：恢复 quartz.dll COM 注册 ====='
$q64 = Start-Process regsvr32.exe -ArgumentList '/s', 'C:\Windows\System32\quartz.dll' -Wait -PassThru
Write-Host "quartz x64 regsvr32 退出码: $($q64.ExitCode)"
$q86 = Start-Process C:\Windows\SysWOW64\regsvr32.exe -ArgumentList '/s', 'C:\Windows\SysWOW64\quartz.dll' -Wait -PassThru
Write-Host "quartz x86 regsvr32 退出码: $($q86.ExitCode)"

# 校验 FilterMapper2 是否已出现，缺失则手工补键（仅 InprocServer32 + ThreadingModel，CoCreateInstance 所需最小集）
$fm2 = '{C1D403C6-D3D4-11D0-9DBE-0000F8004573}'
foreach ($v in @(
        @{ Key = "HKLM:\SOFTWARE\Classes\CLSID\$fm2\InprocServer32"; Dll = 'C:\Windows\System32\quartz.dll' },
        @{ Key = "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$fm2\InprocServer32"; Dll = 'C:\Windows\SysWOW64\quartz.dll' }
    )) {
    if (-not (Test-Path $v.Key)) {
        Write-Host "手工补键: $($v.Key)"
        New-Item -Path $v.Key -Force | Out-Null
        Set-Item -Path $v.Key -Value $v.Dll
        New-ItemProperty -Path $v.Key -Name 'ThreadingModel' -Value 'Both' -PropertyType String -Force | Out-Null
    }
}
Write-Host ("FilterMapper2 64 位视图存在: " + (Test-Path "HKLM:\SOFTWARE\Classes\CLSID\$fm2\InprocServer32"))
Write-Host ("FilterMapper2 32 位视图存在: " + (Test-Path "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$fm2\InprocServer32"))

Write-Host ''
Write-Host '===== 第 2 步：MTA 宿主注册 akvcam DShow 插件 ====='
$x64 = Start-Process powershell.exe -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-MTA', '-File', "$work\reg-dll-mta.ps1",
    '-DllPath', "$work\akvcam\x64\AkVirtualCamera.dll",
    '-OutFile', "$work\reg-hr-x64.txt") -Wait -PassThru
Write-Host "x64 注册 worker 退出码: $($x64.ExitCode)"

$x86 = Start-Process C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-MTA', '-File', "$work\reg-dll-mta.ps1",
    '-DllPath', "$work\akvcam\x86\AkVirtualCamera.dll",
    '-OutFile', "$work\reg-hr-x86.txt") -Wait -PassThru
Write-Host "x86 注册 worker 退出码: $($x86.ExitCode)"

Write-Host ''
Write-Host '===== 第 3 步：验证注册结果 ====='
Write-Host ("x64 HRESULT: " + (Get-Content "$work\reg-hr-x64.txt" -ErrorAction SilentlyContinue) + "  (0=成功)")
Write-Host ("x86 HRESULT: " + (Get-Content "$work\reg-hr-x86.txt" -ErrorAction SilentlyContinue) + "  (0=成功)")

foreach ($view in @('HKLM:\SOFTWARE\Classes\CLSID', 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID')) {
    $hits = @(Get-ChildItem $view -ErrorAction SilentlyContinue |
        Where-Object { "$($_.GetValue(''))" -like '*AkVirtualCamera*' })
    Write-Host "$view 中 AkVirtualCamera CLSID 数: $($hits.Count)"
    foreach ($h in $hits) { Write-Host "  -> $($h.PSChildName)  InprocServer32=$((Get-ItemProperty $h.PSPath -Name '(default)' -ErrorAction SilentlyContinue).'(default)')" }
}

# 视频输入类别 Instance 下应出现 akvcam 派生 CLSID
$category = '{860BB310-5D01-11D0-BD3B-00A0C911CE86}'
foreach ($base in @("HKLM:\SOFTWARE\Classes\CLSID\$category\Instance",
                    "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$category\Instance")) {
    Write-Host "[$base]"
    Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host ("  " + $_.PSChildName + "  FriendlyName=" + $_.GetValue('FriendlyName'))
    }
}

Stop-Transcript
Set-Content "$work\fix-com-register.done" "done $(Get-Date -Format 'HH:mm:ss')"
Write-Host ''

