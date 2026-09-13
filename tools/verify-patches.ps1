# verify-patches.ps1：核对 connector\patched\*.dll 与补丁脚本描述一致（对照 easi-soft 原始 .orig）
# 检查三点：
#   1. EasiCamera.Business：ldstr "virtual"/"smartclass vcamera" 已改为 "virtual_x"/"smartclass vcamera_x"
#   2. WPFMediaKit SetupGraph：最后一个 AddLavDecoder call 已换成 AddColorSpaceConverter（首处保留）
#   3. WPFMediaKit SetDefaultMediaSubType：第一处 Guid.Empty 已换成 MediaSubType.YUY2
param(
    [string]$PatchedDir = (Join-Path $PSScriptRoot '..\connector\patched'),
    [string]$OrigDir    = (Join-Path $PSScriptRoot '..\easi-soft\EasiCamera_2.1.0.4410\Main')
)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'ilspy\Mono.Cecil.dll')

$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($OrigDir)
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver

function Get-AllTypes([Mono.Cecil.ModuleDefinition]$mod) {
    $all = New-Object System.Collections.Generic.List[object]
    function Add-TypeRec([object]$t, [object]$list) {
        $list.Add($t)
        foreach ($n in $t.NestedTypes) { Add-TypeRec $n $list }
    }
    foreach ($t in $mod.Types) { Add-TypeRec $t $all }
    return $all
}

function Count-Ldstr([Mono.Cecil.MethodDefinition]$m, [string]$s) {
    if (-not $m.HasBody) { return 0 }
    $n = 0
    foreach ($ins in $m.Body.Instructions) {
        if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr -and $ins.Operand -eq $s) { $n++ }
    }
    return $n
}

$fail = @()

# ========== 1. EasiCamera.Business ==========
Write-Output '== EasiCamera.Business =='
$origBiz = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $OrigDir 'EasiCamera.Business.dll.orig'), $rp)
$patBiz  = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $PatchedDir 'EasiCamera.Business.dll'), $rp)

foreach ($pair in @(@('virtual','virtual_x'), @('smartclass vcamera','smartclass vcamera_x'))) {
    $old = $pair[0]; $new = $pair[1]
    $oOld = 0; $oNew = 0; $pOld = 0; $pNew = 0
    foreach ($t in (Get-AllTypes $origBiz.MainModule)) { foreach ($m in $t.Methods) { $oOld += Count-Ldstr $m $old; $oNew += Count-Ldstr $m $new } }
    foreach ($t in (Get-AllTypes $patBiz.MainModule))  { foreach ($m in $t.Methods) { $pOld += Count-Ldstr $m $old; $pNew += Count-Ldstr $m $new } }
    $ok = ($oOld -eq $pNew -and $oNew -eq 0 -and $pOld -eq 0)
    Write-Output ("  '{0}' orig={1} patched_new('{2}')={3} | patched_old={4} orig_new={5}  -> {6}" -f $old, $oOld, $new, $pNew, $pOld, $oNew, $(if ($ok) { 'PASS' } else { 'FAIL' }))
    if (-not $ok) { $fail += "Business ldstr '$old'" }
}

# 列出补丁后含目标串的方法（即被改动的方法）
Write-Output '  patched methods carrying renamed strings:'
foreach ($t in (Get-AllTypes $patBiz.MainModule)) {
    foreach ($m in $t.Methods) {
        $nV = Count-Ldstr $m 'virtual_x'; $nS = Count-Ldstr $m 'smartclass vcamera_x'
        if ($nV -gt 0 -or $nS -gt 0) {
            Write-Output ("    {0}::{1} (virtual_x x{2}, smartclass_x x{3})" -f $t.FullName, $m.Name, $nV, $nS)
        }
    }
}
$origBiz.Dispose(); $patBiz.Dispose()

# ========== 2+3. WPFMediaKit ==========
Write-Output '== WPFMediaKit =='
$origMK = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $OrigDir 'WPFMediaKit.dll.orig'), $rp)
$patMK  = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $PatchedDir 'WPFMediaKit.dll'), $rp)

foreach ($asm in @($origMK, $patMK)) {
    $tag = if ($asm -eq $origMK) { 'orig' } else { 'patched' }
    $tp = $asm.MainModule.Types | Where-Object { $_.Name -eq 'VideoCapturePlayer' } | Select-Object -First 1
    if (-not $tp) { $fail += "WPFMediaKit[$tag] VideoCapturePlayer missing"; Write-Output "  [$tag] FAIL: VideoCapturePlayer not found"; continue }

    # (2) SetupGraph: AddLavDecoder calls
    $setup = $tp.Methods | Where-Object { $_.Name -eq 'SetupGraph' } | Select-Object -First 1
    $calls = @()
    foreach ($ins in $setup.Body.Instructions) {
        if (($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Call -or $ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Callvirt) -and
            $ins.Operand -is [Mono.Cecil.MethodReference] -and $ins.Operand.Name -eq 'AddLavDecoder') { $calls += $ins }
    }
    $lastOp = if ($calls.Count -gt 0) { $calls[$calls.Count - 1].Operand.Name } else { '<none>' }
    Write-Output ("  [{0}] SetupGraph AddLavDecoder calls={1}, last operand={2}" -f $tag, $calls.Count, $lastOp)

    # (3) SetDefaultMediaSubType: first Guid.Empty ldsfld
    $g = $tp.Methods | Where-Object { $_.Name -like '*SetDefaultMediaSubType*' } | Select-Object -First 1
    if (-not $g) { $fail += "WPFMediaKit[$tag] SetDefaultMediaSubType missing"; Write-Output "  [$tag] FAIL: SetDefaultMediaSubType not found"; continue }
    $fld = '<none>'
    foreach ($ins in $g.Body.Instructions) {
        if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldsfld -and
            $ins.Operand -is [Mono.Cecil.FieldReference] -and
            $ins.Operand.DeclaringType.Name -eq 'Guid' -and $ins.Operand.Name -eq 'Empty') { $fld = 'Guid.Empty'; break }
        if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldsfld -and
            $ins.Operand -is [Mono.Cecil.FieldReference] -and
            $ins.Operand.DeclaringType.Name -eq 'MediaSubType' -and $ins.Operand.Name -eq 'YUY2') { $fld = 'MediaSubType.YUY2'; break }
    }
    Write-Output ("  [{0}] {1}: first subtype ldsfld = {2}" -f $tag, $g.Name, $fld)
}

$patCalls = @(); $patSetup = ($patMK.MainModule.Types | Where-Object { $_.Name -eq 'VideoCapturePlayer' }).Methods | Where-Object Name -eq 'SetupGraph' | Select-Object -First 1
foreach ($ins in $patSetup.Body.Instructions) {
    if (($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Call -or $ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Callvirt) -and
        $ins.Operand -is [Mono.Cecil.MethodReference] -and $ins.Operand.Name -eq 'AddLavDecoder') { $patCalls += $ins }
}
if ($patCalls.Count -ne 1) { $fail += "WPFMediaKit SetupGraph AddLavDecoder count=$($patCalls.Count) (expect 1)" }
$gPatched = ($patMK.MainModule.Types | Where-Object { $_.Name -eq 'VideoCapturePlayer' }).Methods | Where-Object { $_.Name -like '*SetDefaultMediaSubType*' } | Select-Object -First 1
$yuy2ok = $false
foreach ($ins in $gPatched.Body.Instructions) {
    if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldsfld -and $ins.Operand -is [Mono.Cecil.FieldReference]) {
        if ($ins.Operand.DeclaringType.Name -eq 'MediaSubType' -and $ins.Operand.Name -eq 'YUY2') { $yuy2ok = $true }
        break
    }
}
if (-not $yuy2ok) { $fail += 'WPFMediaKit SetDefaultMediaSubType first ldsfld != MediaSubType.YUY2' }
Write-Output ("  verdict: AddLavDecoder-left={0} (expect 1), YUY2-first={1} (expect True)" -f ($patCalls.Count -eq 1), $yuy2ok)

$origMK.Dispose(); $patMK.Dispose()

Write-Output ''
if ($fail.Count -gt 0) { Write-Output ("RESULT: FAIL ({0})" -f ($fail -join '; ')); exit 1 }
Write-Output 'RESULT: PASS - patched DLLs match patch scripts'
