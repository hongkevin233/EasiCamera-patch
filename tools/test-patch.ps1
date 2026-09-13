# easi-connector 离线语义验证 v3
# 1) patched IsSeewoCamera(DsDevice) 无条件放行（方法体已 patch 成 ldc.i4.1/ret，参数不读）
# 2) IsSpecificCamera 正则未被破坏（希沃自家 VID/PID 仍识别、第三方仍不识别）
#    => 型号判定、希沃硬件专属分支完全不受 patch 影响（静态推理：IsScXXCamera 全部经
#       IsSpecificCamera(cam.DevicePath,...) 匹配，第三方 VID 全不中 => SeewoCameraType.None
#       => CameraService 走 None 通用 controller）
# 3) 原版 IsSpecificCamera 对照
param()

$ErrorActionPreference = 'Stop'
$main = 'D:\easi-connector\easi-soft\EasiCamera_2.1.0.4410\Main'

[System.Reflection.Assembly]::LoadFrom("$main\DirectShowLib.dll") | Out-Null
Get-ChildItem $main -Filter 'Cvte.*.dll' | ForEach-Object { try { [System.Reflection.Assembly]::LoadFrom($_.FullName) | Out-Null } catch {} }
try { [System.Reflection.Assembly]::LoadFrom("$main\EasiCamera.Util.dll") | Out-Null } catch {}

$patched = [System.Reflection.Assembly]::LoadFrom('D:\easi-connector\connector\patched\EasiCamera.Api.dll')
$orig    = [System.Reflection.Assembly]::LoadFrom("$main\EasiCamera.Api.dll.orig")

$extP = $patched.GetType('EasiCamera.CameraExtension')
$extO = $orig.GetType('EasiCamera.CameraExtension')

# 3862 = 0x0F16（希沃 SC03 的 PID）
$seewoPath = '@device:pnp:\\?\usb#vid_1ff7&pid_0f16&mi_00#8&2c9f1a2b&0&0000#{e5323777-f976-4f5b-9b55-b94699c46e44}'
$thirdPath = '@device:pnp:\\?\usb#vid_1234&pid_5678&mi_00#8&2c9f1a2b&0&0000#{e5323777-f976-4f5b-9b55-b94699c46e44}'

$script:pass = $true
function Check($name, $actual, $expect) {
    $ok = ($actual -eq $expect)
    $script:pass = $script:pass -and $ok
    $mark = if ($ok) { 'PASS' } else { 'FAIL' }
    Write-Output ("[{0}] {1} => {2} (expect {3})" -f $mark, $name, $actual, $expect)
}

# ---- 1. patched IsSeewoCamera(DsDevice)：无条件 true ----
$mP = $extP.GetMethods() | Where-Object { $_.Name -eq 'IsSeewoCamera' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'DsDevice' } | Select-Object -First 1
if ($mP) {
    Check 'patched.IsSeewoCamera(null-device)' ([bool]$mP.Invoke($null, @($null))) $true
} else { Write-Output 'FAIL: patched method resolve'; exit 1 }

# ---- 2. IsSpecificCamera 正则完整性（patched vs orig 对照）----
$specP = $extP.GetMethods() | Where-Object { $_.Name -eq 'IsSpecificCamera' -and $_.IsStatic } | Select-Object -First 1
$specO = $extO.GetMethods() | Where-Object { $_.Name -eq 'IsSpecificCamera' -and $_.IsStatic } | Select-Object -First 1
if (-not $specP -or -not $specO) { Write-Output 'FAIL: IsSpecificCamera resolve'; exit 1 }

Check 'patched.IsSpecificCamera(vid_1ff7 pid_0f16 => SC03)' ([bool]$specP.Invoke($null, @($seewoPath, [int]8183, [int]3862))) $true
Check 'patched.IsSpecificCamera(vid_1234 => no match)'      ([bool]$specP.Invoke($null, @($thirdPath, [int]8183, [int]3862))) $false
Check 'orig.IsSpecificCamera(vid_1ff7 pid_0f16 => SC03)'    ([bool]$specO.Invoke($null, @($seewoPath, [int]8183, [int]3862))) $true
Check 'orig.IsSpecificCamera(vid_1234 => no match)'         ([bool]$specO.Invoke($null, @($thirdPath, [int]8183, [int]3862))) $false

if ($script:pass) { Write-Output 'ALL SEMANTIC TESTS PASS' } else { Write-Output 'SEMANTIC TESTS FAILED'; exit 1 }
