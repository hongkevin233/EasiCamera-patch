# patch-wpfmt2.ps1：SetDefaultMediaSubType 的 DisableMjpegAsDefault 分支强制 YUY2
# 背景：该分支原本传 Guid.Empty（保持 pin 当前 subtype），OBS VC 等裸 YUV 设备默认 NV12，
#       系统 ColorSpaceConverter 不接受 NV12 → VFW_E_NOT_CONNECTED；改为 YUY2 后 CSC 可协商。
# B870 真机路径（EnableForceMjpegDefault=true → MJPG 分支）不受影响。
param(
    [Parameter(Mandatory=$true)][string]$InDll,
    [Parameter(Mandatory=$true)][string]$OutDll,
    [string]$SearchDir = (Join-Path $PSScriptRoot '..\easi-soft\EasiCamera_2.1.0.4410\Main')
)

Add-Type -Path (Join-Path $PSScriptRoot 'ilspy\Mono.Cecil.dll')

$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($SearchDir)
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($InDll, $rp)

$tp = $asm.MainModule.Types | Where-Object { $_.Name -eq 'VideoCapturePlayer' }
if (-not $tp) { Write-Output 'FAIL: VideoCapturePlayer not found'; exit 1 }

# 本地函数编译产物：g__SetDefaultMediaSubType|xx_0
$g = $tp.Methods | Where-Object { $_.Name -like '*SetDefaultMediaSubType*' } | Select-Object -First 1
if (-not $g) { Write-Output 'FAIL: SetDefaultMediaSubType local function not found'; exit 1 }
Write-Output ("target method: " + $g.FullName)

# 解析 DirectShowLib.MediaSubType.YUY2 字段引用
$dsl = $resolver.Resolve([Mono.Cecil.AssemblyNameReference]::Parse('DirectShowLib'))
if (-not $dsl) { Write-Output 'FAIL: cannot resolve DirectShowLib'; exit 1 }
$mst = $dsl.MainModule.Types | Where-Object { $_.Name -eq 'MediaSubType' } | Select-Object -First 1
$yuy2 = $mst.Fields | Where-Object { $_.Name -eq 'YUY2' } | Select-Object -First 1
if (-not $yuy2) { Write-Output 'FAIL: MediaSubType.YUY2 field not found'; exit 1 }

# 替换方法体内第一处 ldsfld Guid.Empty（= DisableMjpegAsDefault 分支的 SetVideoCaptureParameters 参数）
$done = $false
foreach ($ins in $g.Body.Instructions) {
    if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldsfld -and
        $ins.Operand -is [Mono.Cecil.FieldReference] -and
        $ins.Operand.DeclaringType.Name -eq 'Guid' -and $ins.Operand.Name -eq 'Empty') {
        $ins.Operand = $asm.MainModule.ImportReference($yuy2)
        $done = $true
        break
    }
}
if (-not $done) { Write-Output 'FAIL: Guid.Empty ldsfld not found'; exit 1 }
Write-Output 'patched: first Guid.Empty in SetDefaultMediaSubType -> MediaSubType.YUY2'

$asm.Write($OutDll)
$asm.Dispose()
if (Test-Path $OutDll) { Write-Output ("written: " + $OutDll + " (" + (Get-Item $OutDll).Length + " bytes)") } else { Write-Output 'FAIL: output missing'; exit 1 }
