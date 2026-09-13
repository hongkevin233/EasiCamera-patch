# easi-connector 一键补丁：编译 Patcher -> 生成补丁 DLL -> 部署到希沃视频展台
# 幂等：Patcher.exe 与补丁 DLL 均按源码/原始 DLL 时间戳增量重做
# 用法（在 connector 目录或任意位置）:
#   powershell -NoProfile -ExecutionPolicy Bypass -File patch-all.ps1              # 全流程：编译+补丁+部署
#   ... -SkipDeploy                     # 只生成 connector\patched\ 三个补丁 DLL，不部署
#   ... -FirstInstall                   # 部署希沃补丁后，附带首次安装 akvcam 9.1.3 虚拟摄像头（需管理员）
#   ... -SourceDll <原始Api.dll> -InstallDir <Main目录>   # 手动指定，跳过自动探测
param(
    [string]$SourceDll = '',
    [string]$InstallDir = '',
    [switch]$SkipDeploy,
    [switch]$FirstInstall
)
$Banner = @(
'######   ###      ___   ######',
'##      ##  ##   /        ##  ',
'#####   ######    ---_    ##  ',
'##     ##   ##      /     ##   ',
'###### ##   ##   ---    ######',
'',
' #####   ####  ##   ##  ##   ## ######    #### #####  ####  ##### ',
'##      ##  ## ###  ##  ###  ## ##      ##      ##   ##  ## ##  ##',
'##      ##  ## ## # ##  ## # ## #####  ##       ##   ##  ## ##### ',
'##      ##  ## ##  ###  ##  ### ##      ##      ##   ##  ## ## ## ',
' #####   ####  ##   ##  ##   ## ######    ####  ##    ####  ##  ##',
'',
' /-------------------------------------------\',
'| by:diamond_dia | powered by: GLM-5.3-flash |',
' \-------------------------------------------/'
)

foreach ($line in $Banner) { Write-Host $line -ForegroundColor Cyan }
Write-Host ''
Write-Host '  easi-connector  -  YJZ-B870 camera bridge for Seewo EasiCamera' -ForegroundColor Yellow
Write-Host ''
$ErrorActionPreference = 'Stop'
$Connector = $PSScriptRoot
$Root = Split-Path $Connector -Parent
$Patched = Join-Path $Connector 'patched'
if (-not (Test-Path $Patched)) { New-Item $Patched -ItemType Directory | Out-Null }

# ---------- 1. Mono.Cecil（编译 Patcher 的唯一依赖，MIT 开源） ----------
$cecil = Join-Path $Connector 'Mono.Cecil.dll'
if (-not (Test-Path $cecil)) {
    $alt = Join-Path $Root 'tools\ilspy\Mono.Cecil.dll'
    if (Test-Path $alt) {
        Copy-Item $alt $cecil -Force
        Write-Output "cecil: copied from tools\ilspy"
    } else {
        Write-Output 'Mono.Cecil.dll not found; downloading mono.cecil 0.11.6 from nuget.org ...'
        $nupkg = Join-Path $env:TEMP 'mono.cecil.0.11.6.zip'
        Invoke-WebRequest 'https://www.nuget.org/api/v2/package/Mono.Cecil/0.11.6' -OutFile $nupkg
        $extDir = Join-Path $env:TEMP 'mono.cecil.ext'
        Expand-Archive $nupkg $extDir -Force
        Copy-Item (Join-Path $extDir 'lib\netstandard2.0\Mono.Cecil.dll') $cecil -Force
        Remove-Item $nupkg -Force; Remove-Item $extDir -Recurse -Force
        Write-Output "cecil: downloaded to $cecil"
    }
}

# ---------- 2. 编译 Patcher.exe（源码更新时才重编） ----------
$patcherSrc = Join-Path $Root 'tools\Patcher.cs'
$patcherExe = Join-Path $Connector 'Patcher.exe'
if ((Test-Path $patcherExe) -and ((Get-Item $patcherExe).LastWriteTime -ge (Get-Item $patcherSrc).LastWriteTime)) {
    Write-Output 'patcher: up-to-date'
} else {
    # csc 查找顺序：仓库内 BuildTools Roslyn -> VS 安装的 Roslyn -> 系统 Framework csc（兜底）
    $cscList = @()
    $roslyn = Join-Path $Root 'BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe'
    if (Test-Path $roslyn) { $cscList += $roslyn }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $cscList += & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\Roslyn\csc.exe' 2>$null
    }
    $cscList += Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $csc = $cscList | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $csc) { throw 'no csc found; need .NET Framework 4.x or Visual Studio' }

    $cscArgs = @('/nologo', "/out:$patcherExe", "/reference:$cecil")
    # Mono.Cecil 是 netstandard2.0 目标：需引用 netstandard 运行时 facade（.NET Framework 4.7.2+ GAC 自带）
    $shim = Get-ChildItem (Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\netstandard\*\netstandard.dll') -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $shim) { throw 'netstandard shim not found in GAC; need .NET Framework 4.7.2+' }
    $cscArgs += "/reference:$($shim.FullName)"
    $cscArgs += $patcherSrc
    & $csc @cscArgs
    if ($LASTEXITCODE -ne 0) { throw "csc failed: $csc" }
    Write-Output "patcher: built -> $patcherExe"
}

# ---------- 3. 定位原始 EasiCamera.Api.dll ----------
function Find-InstallDir {
    # 1) 注册表 InstallLocation（正规安装）
    foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $entry = Get-ItemProperty $r -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '视频展台|EasiCamera' } | Select-Object -First 1
        if ($entry -and $entry.InstallLocation) { return $entry.InstallLocation }
    }
    # 2) 运行中的 EasiCamera.exe（绿色解包/便携安装场景最可靠）
    $proc = (Get-Process EasiCamera -ErrorAction SilentlyContinue | Where-Object Path | Select-Object -First 1).Path
    if ($proc) { return Split-Path $proc -Parent }
    # 3) 注册表 DisplayIcon / UninstallString 推导：在其目录附近浅层递归找 EasiCamera.exe
    $hint = $null
    foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $entry = Get-ItemProperty $r -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '视频展台|EasiCamera' } | Select-Object -First 1
        if ($entry) {
            if ($entry.DisplayIcon) { $hint = ($entry.DisplayIcon -split ',')[0] }
            elseif ($entry.UninstallString) { $hint = ($entry.UninstallString -split ',')[0] }
            if ($hint -and (Test-Path $hint)) {
                $exe = Get-ChildItem (Split-Path $hint -Parent) -Recurse -Depth 3 -Filter 'EasiCamera.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exe) { return Split-Path $exe.FullName -Parent }
            }
        }
    }
    # 4) Program Files 目录名搜索
    $found = Get-ChildItem 'C:\Program Files*','D:\Program Files*' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Seewo|希沃' } |
        ForEach-Object { Get-ChildItem $_.FullName -Recurse -Depth 4 -Filter 'EasiCamera.exe' -ErrorAction SilentlyContinue } |
        Select-Object -First 1
    if ($found) { return Split-Path $found.FullName -Parent }
    return ''
}
if (-not $InstallDir) { $InstallDir = Find-InstallDir }
if ($InstallDir -and ((Split-Path $InstallDir -Leaf) -ne 'Main')) {
    $main = Join-Path $InstallDir 'Main'
    if (Test-Path $main) { $InstallDir = $main }
}

# 原始 DLL 解析顺序：.orig 原始备份优先（绿色解包装的 easi-soft 同时是活安装目录，
# 其裸 DLL 可能已被 install.ps1 替换为补丁版），裸 DLL 仅作兜底
function Resolve-Orig([string]$name) {
    $candidates = @()
    $candidates += Get-ChildItem (Join-Path $Root 'easi-soft') -Recurse -Filter "$name.orig" -ErrorAction SilentlyContinue
    if ($InstallDir) { $p = Join-Path $InstallDir "$name.orig"; if (Test-Path $p) { $candidates += Get-Item $p } }
    $candidates += Get-ChildItem (Join-Path $Root 'easi-soft') -Recurse -Filter $name -ErrorAction SilentlyContinue
    if ($InstallDir) { $p = Join-Path $InstallDir $name; if (Test-Path $p) { $candidates += Get-Item $p } }
    return ($candidates | Select-Object -First 1).FullName
}
if (-not $SourceDll) { $SourceDll = Resolve-Orig 'EasiCamera.Api.dll' }
if (-not ($SourceDll -and (Test-Path $SourceDll))) {
    throw "original EasiCamera.Api.dll not found; pass -SourceDll explicitly（希沃安装目录或安装包解包目录）"
}
Write-Output "source: $SourceDll"

# ---------- 4. 生成补丁 DLL（原始 DLL 更新时才重跑） ----------
$apiOut = Join-Path $Patched 'EasiCamera.Api.dll'
if ((Test-Path $apiOut) -and ((Get-Item $apiOut).LastWriteTime -ge (Get-Item $SourceDll).LastWriteTime)) {
    Write-Output 'patch: EasiCamera.Api.dll up-to-date'
} else {
    & $patcherExe $SourceDll $apiOut
    if ($LASTEXITCODE -ne 0) { throw "Patcher failed (exit $LASTEXITCODE)" }
}
$hash = (Get-FileHash $apiOut -Algorithm SHA256).Hash.Substring(0, 16)
Write-Output "patch: $apiOut (sha256 $hash...)"

# ---------- 4b. 生成 Business / WPFMediaKit 补丁（tools 补丁脚本，时间戳增量幂等） ----------
$toolDir = Join-Path $Root 'tools'
$patchJobs = @(
    @{ Name = 'EasiCamera.Business.dll'; Steps = @('patch-business.ps1') },
    @{ Name = 'WPFMediaKit.dll';         Steps = @('patch-wpfmt.ps1', 'patch-wpfmt2.ps1') }
)
foreach ($job in $patchJobs) {
    $name = $job.Name
    $src = Resolve-Orig $name
    if (-not ($src -and (Test-Path $src))) {
        throw "original $name not found（希沃安装目录或安装包解包目录）"
    }
    $out = Join-Path $Patched $name
    $deps = @($src) + ($job.Steps | ForEach-Object { Join-Path $toolDir $_ })
    $latest = ($deps | ForEach-Object { (Get-Item $_).LastWriteTime } | Measure-Object -Maximum).Maximum
    if ((Test-Path $out) -and ((Get-Item $out).LastWriteTime -ge $latest)) {
        Write-Output "patch: $name up-to-date"
        continue
    }
    $searchDir = Split-Path $src -Parent
    $cur = $src
    for ($i = 0; $i -lt $job.Steps.Count; $i++) {
        $stepOut = if ($i -eq $job.Steps.Count - 1) { $out } else { Join-Path $Patched "$($name).stage$($i + 1)" }
        try {
            & (Join-Path $toolDir $job.Steps[$i]) -InDll $cur -OutDll $stepOut -SearchDir $searchDir
            # 补丁脚本断言失败走 exit 1（& 同进程调用会设置 $LASTEXITCODE 但不中断父脚本）；
            # 正常结束则该变量保持原值（可能为空）→ 用真值判断：空/0 通过，非 0 抛错
            if ($LASTEXITCODE) { throw "$($job.Steps[$i]) failed (exit $LASTEXITCODE)" }
        } catch { throw "$($job.Steps[$i]) failed: $_" }
        $cur = $stepOut
    }
    for ($i = 1; $i -lt $job.Steps.Count; $i++) { Remove-Item (Join-Path $Patched "$($name).stage$i") -Force -ErrorAction SilentlyContinue }
    $hash = (Get-FileHash $out -Algorithm SHA256).Hash.Substring(0, 16)
    Write-Output "patch: $out (sha256 $hash...)"
}

# ---------- 5. 部署 ----------
if ($SkipDeploy) { Write-Output 'SKIP deploy (-SkipDeploy)'; return }

# Business/WPFMediaKit 补丁已在步骤 4b 自动生成；到这里仍缺失（手动删除等）则提示
foreach ($n in @('EasiCamera.Business.dll', 'WPFMediaKit.dll')) {
    if (-not (Test-Path (Join-Path $Patched $n))) {
        Write-Output "note: $n not in patched\ (见 README '补丁明细 → 复现命令' 手动生成)"
    }
}
if (-not $InstallDir) { $InstallDir = Find-InstallDir }
if (-not $InstallDir) { throw 'install dir not found; pass -InstallDir explicitly' }
& (Join-Path $Connector 'install.ps1') -Dir $InstallDir -PatchedDir $Patched
# & 同进程调用，脚本正常结束不写 $LASTEXITCODE（空）→ 真值判断：空/0 通过，非 0 抛错
if ($LASTEXITCODE) { throw "install.ps1 failed (exit $LASTEXITCODE)" }

# ---------- 6. 首次安装 akvcam 9.1.3 虚拟摄像头（可选） ----------
if ($FirstInstall) {
    $deploy = Join-Path $Root 'tools\deploy-akvcam913.ps1'
    if (-not (Test-Path $deploy)) { throw "not found: $deploy（需先从 release 获取 akvcam913 二进制）" }
    Write-Output '=== first install: akvcam 9.1.3 (needs admin) ==='
    & $deploy
}
Write-Output ''
Write-Output 'ALL DONE. 下一步: 1) 管理员运行 tools\deploy-akvcam913.ps1（仅首次）'
Write-Output '            2) 双击 connector\run-bridge.cmd 启动桥接'
Write-Output '            3) 打开希沃视频展台，视频源选 AkVCamVideoDevice0'
