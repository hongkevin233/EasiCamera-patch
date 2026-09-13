# easi-connector 安装脚本 v2：把 patched 目录下所有 DLL 覆盖到希沃视频展台安装目录（Main）
# 现有 patch：
#   EasiCamera.Api.dll      - IsSeewoCamera(DsDevice) 放行第三方设备
#   EasiCamera.Business.dll - 去除 virtual/smartclass vcamera 名字剔除（调试虚拟摄像头用）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-Dir <安装目录Main>] [-PatchedDir <patched目录>]
param(
    [string]$Dir = '',
    [string]$PatchedDir = ''
)

$ErrorActionPreference = 'Stop'
if (-not $PatchedDir) { $PatchedDir = Join-Path $PSScriptRoot 'patched' }

# 1. 定位安装目录（Main）
if (-not $Dir) {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($r in $roots) {
        $entry = Get-ItemProperty $r -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '视频展台|EasiCamera' } |
            Select-Object -First 1
        if ($entry -and $entry.InstallLocation) { $Dir = $entry.InstallLocation; break }
    }
    if (-not $Dir) {
        $found = Get-ChildItem 'C:\Program Files*','D:\Program Files*' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Seewo|希沃' } |
            ForEach-Object { Get-ChildItem $_.FullName -Recurse -Filter 'EasiCamera.exe' -ErrorAction SilentlyContinue } |
            Select-Object -First 1
        if ($found) { $Dir = Split-Path $found.FullName }
    }
}
if (-not $Dir) { Write-Output 'install dir not found; pass -Dir explicitly'; exit 1 }
if ((Split-Path $Dir -Leaf) -ne 'Main') {
    $main = Join-Path $Dir 'Main'
    if (Test-Path $main) { $Dir = $main }
}
Write-Output "install dir: $Dir"

# 2. 停进程（软件 + 守护）
foreach ($p in @('EasiCamera', 'EasiCameraGuardian', 'GuardianUpdater')) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 800

# 3. 逐 DLL：首次备份 .orig + 覆盖
$patches = Get-ChildItem $PatchedDir -Filter '*.dll'
if ($patches.Count -eq 0) { Write-Output "no patched dlls in $PatchedDir"; exit 1 }
foreach ($pf in $patches) {
    $target = Join-Path $Dir $pf.Name
    if (-not (Test-Path $target)) { Write-Output "skip (not installed): $($pf.Name)"; continue }
    $backup = Join-Path $Dir ($pf.Name + '.orig')
    if (-not (Test-Path $backup)) { Copy-Item $target $backup -Force; Write-Output "backup: $($pf.Name) -> $(Split-Path $backup -Leaf)" }
    Copy-Item $pf.FullName $target -Force
    $len = (Get-Item $target).Length; $origLen = (Get-Item $backup).Length
    Write-Output ("patched: {0} (patched={1}B orig={2}B)" -f $pf.Name, $len, $origLen)
}
Write-Output 'DONE. 启动希沃视频展台验证。'
