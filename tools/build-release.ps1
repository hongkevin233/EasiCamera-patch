# easi-connector release packer：把安装所需脚本/文件镜像到 release\（gitignore 排除）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File build-release.ps1
# 产物: release\ 直接 zip 挂 GitHub release 附件（akvcam913 二进制走附件，见 README）
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Rel = Join-Path $Root 'release'

if (Test-Path $Rel) { Remove-Item $Rel -Recurse -Force }
New-Item $Rel -ItemType Directory | Out-Null

# ---- 复制清单（保持 repo 目录结构，脚本全部便携化、相对 $PSScriptRoot） ----
$files = @(
    'README.md',
    'connector\patch-all.ps1',
    'connector\install.ps1',
    'connector\uninstall.ps1',
    'connector\bridge.ps1',
    'connector\run-bridge.cmd',
    'tools\Patcher.cs',
    'tools\patch-business.ps1',
    'tools\patch-wpfmt.ps1',
    'tools\patch-wpfmt2.ps1',
    'tools\verify-patches.ps1',
    'tools\deploy-akvcam913.ps1',
    'tools\monitor-easicam.ps1',
    'tools\monitor-viewer.py'
)
$dirs = @(
    'tools\akvcam913\x64',      # AkVCam 9.1.3 补丁版二进制（release 附件）
    'tools\akvcam913\x86'
)
# 预编译产物（有则预置，省去克隆者联网下载 Cecil；没有 patch-all 也会现场编译）
$optional = @(
    'connector\Patcher.exe',
    'connector\Mono.Cecil.dll'
)

foreach ($f in $files + $optional) {
    $src = Join-Path $Root $f
    if (-not (Test-Path $src)) { Write-Output "skip (missing): $f"; continue }
    $dst = Join-Path $Rel $f
    New-Item (Split-Path $dst -Parent) -ItemType Directory -Force | Out-Null
    Copy-Item $src $dst -Force
}
foreach ($d in $dirs) {
    $src = Join-Path $Root $d
    if (-not (Test-Path $src)) { Write-Output "skip (missing dir): $d"; continue }
    Copy-Item $src (Join-Path $Rel $d) -Recurse -Force
}

# ---- PowerShell 5.1 对无 BOM 的 UTF-8 按 GBK 解析：确保所有 ps1 带 BOM ----
Get-ChildItem $Rel -Recurse -Filter '*.ps1' | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return }
    $text = [IO.File]::ReadAllText($_.FullName, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($_.FullName, $text, [Text.UTF8Encoding]::new($true))
    Write-Output "bom added: $($_.FullName.Substring($Rel.Length + 1))"
}

# ---- 自检：release 内不允许出现硬编码盘符路径 ----
$bad = Get-ChildItem $Rel -Recurse -Include '*.ps1', '*.cmd', '*.py' |
    Select-String -Pattern 'D:\\easi-connector' -List
if ($bad) { throw "hardcoded paths leaked into release: $($bad.Path)" }

Write-Output ''
Write-Output 'release packed:'
Get-ChildItem $Rel -Recurse -File | ForEach-Object { '  ' + $_.FullName.Substring($Rel.Length + 1) }
Write-Output ''
Write-Output 'note: ffmpeg 不打包（OBS 安装或自备），放到 release\tools\ffmpeg\ 即可被 run-bridge.cmd 找到'
