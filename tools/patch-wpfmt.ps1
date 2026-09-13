# patch-wpfmt.ps1：WPFMediaKit 第三分支改造
# SetupGraph 格式分支：
#   MJPG caps  -> AddLavDecoder()        （保留：B870 等 MJPG 高拍仪依赖 LAV 解压）
#   RGB24/32   -> AddColorSpaceConverter()（保留）
#   其他(裸YUV)-> AddLavDecoder()        ← 改为 AddColorSpaceConverter()
#     （OBS VC 等纯裸 YUV 设备：LAV 不吃裸 NV12/YUY2 导致 VFW_E_NOT_CONNECTED 灰屏；
#       WPFMediaKit 自带 ColorSpaceConverter 软转 filter 支持 raw 输入）
# 手法：SetupGraph 方法体内最后一个 call AddLavDecoder 的操作数替换为 AddColorSpaceConverter
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

$setup = $tp.Methods | Where-Object { $_.Name -eq 'SetupGraph' } | Select-Object -First 1
$addLav = $tp.Methods | Where-Object { $_.Name -eq 'AddLavDecoder' } | Select-Object -First 1
$addCsc = $tp.Methods | Where-Object { $_.Name -eq 'AddColorSpaceConverter' } | Select-Object -First 1
if (-not $setup -or -not $addLav -or -not $addCsc) { Write-Output 'FAIL: methods not found'; exit 1 }

$calls = @()
foreach ($ins in $setup.Body.Instructions) {
    if (($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Call -or $ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Callvirt) -and
        $ins.Operand -is [Mono.Cecil.MethodReference] -and $ins.Operand.Name -eq 'AddLavDecoder') {
        $calls += $ins
    }
}
Write-Output ("AddLavDecoder calls in SetupGraph: " + $calls.Count)
if ($calls.Count -lt 2) { Write-Output 'FAIL: expected >=2 calls (first branch + third branch)'; exit 1 }

$last = $calls[$calls.Count - 1]
$last.Operand = $addCsc
Write-Output ("patched: last AddLavDecoder call (IL offset " + ('0x{0:X}' -f $last.Offset) + ") -> AddColorSpaceConverter")

$asm.Write($OutDll)
$asm.Dispose()
if (Test-Path $OutDll) { Write-Output ("written: " + $OutDll + " (" + (Get-Item $OutDll).Length + " bytes)") } else { Write-Output 'FAIL: output missing'; exit 1 }
