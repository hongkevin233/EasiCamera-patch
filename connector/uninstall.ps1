# easi-connector 卸载脚本 v2：还原所有 .orig 备份
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1 [-Dir <安装目录Main>]
param(
    [string]$Dir = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Dir) {
    $found = Get-ChildItem 'C:\Program Files*','D:\Program Files*' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Seewo|希沃' } |
        ForEach-Object { Get-ChildItem $_.FullName -Recurse -Filter '*.dll.orig' -ErrorAction SilentlyContinue } |
        Select-Object -First 1
    if ($found) { $Dir = Split-Path $found.FullName }
}
if (-not $Dir) { Write-Output 'dir not found; pass -Dir explicitly'; exit 1 }

foreach ($p in @('EasiCamera', 'EasiCameraGuardian', 'GuardianUpdater')) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 800

$backups = Get-ChildItem $Dir -Filter '*.orig'
if ($backups.Count -eq 0) { Write-Output "no backups found in $Dir"; exit 1 }
foreach ($b in $backups) {
    $origName = $b.Name -replace '\.orig$', ''
    $target = Join-Path $Dir $origName
    Copy-Item $b.FullName $target -Force
    Remove-Item $b.FullName -Force
    Write-Output "restored: $origName"
}
Write-Output 'DONE.'
