# patch-business.ps1 v3：virtual 屏蔽全量去除（含嵌套闭包类型）
# 手法：递归遍历所有类型（含编译器生成的闭包类），替换方法内 ldstr
#       "virtual" -> "virtual_x"、"smartclass vcamera" -> "smartclass vcamera_x"
#       两处剔除条件（枚举 Contains + FindAll/Remove 兜底）永不命中
param(
    [Parameter(Mandatory=$true)][string]$InDll,
    [Parameter(Mandatory=$true)][string]$OutDll,
    [string]$SearchDir = (Join-Path $PSScriptRoot '..\easi-soft\EasiCamera_2.1.0.4410\Main')
)

Add-Type -Path (Join-Path $PSScriptRoot 'ilspy\Mono.Cecil.dll')

function Get-AllTypes([Mono.Cecil.ModuleDefinition]$mod) {
    $all = New-Object System.Collections.Generic.List[object]
    function Add-Type([object]$t, [object]$list) {
        $list.Add($t)
        foreach ($n in $t.NestedTypes) { Add-Type $n $list }
    }
    foreach ($t in $mod.Types) { Add-Type $t $all }
    return $all
}

$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($SearchDir)
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($InDll, $rp)

$totalV = 0; $totalS = 0; $patchedMethods = @()
foreach ($t in (Get-AllTypes $asm.MainModule)) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        $nV = 0; $nS = 0
        foreach ($ins in $m.Body.Instructions) {
            if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr) {
                if ($ins.Operand -eq 'virtual') { $ins.Operand = 'virtual_x'; $nV++ }
                elseif ($ins.Operand -eq 'smartclass vcamera') { $ins.Operand = 'smartclass vcamera_x'; $nS++ }
            }
        }
        if ($nV -gt 0 -or $nS -gt 0) {
            $patchedMethods += ("{0}::{1} (virtual x{2}, smartclass x{3})" -f $t.FullName, $m.Name, $nV, $nS)
            $totalV += $nV; $totalS += $nS
        }
    }
}

if ($totalV -eq 0 -and $totalS -eq 0) { Write-Output 'FAIL: no target strings found'; exit 1 }
$patchedMethods | ForEach-Object { Write-Output ("patched: " + $_) }
Write-Output ("total: virtual x{0}, smartclass vcamera x{1}" -f $totalV, $totalS)
Write-Output ("hasStrongName: " + ($asm.Name.PublicKey -ne $null -and $asm.Name.PublicKey.Length -gt 0))

$asm.Write($OutDll)
$asm.Dispose()
if (Test-Path $OutDll) { Write-Output ("written: " + $OutDll + " (" + (Get-Item $OutDll).Length + " bytes)") } else { Write-Output 'FAIL: output missing'; exit 1 }
