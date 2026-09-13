# EasiCamera.Api.dll patcher（PowerShell + Mono.Cecil）
# IsSeewoCamera(DsDevice) -> return true
param(
    [Parameter(Mandatory=$true)][string]$InDll,
    [Parameter(Mandatory=$true)][string]$OutDll
)

Add-Type -Path 'D:\easi-connector\tools\ilspy\Mono.Cecil.dll'

$rp = New-Object Mono.Cecil.ReaderParameters
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($InDll, $rp)
$mod = $asm.MainModule

$t = $mod.Types | Where-Object { $_.Name -eq 'CameraExtension' }
if (-not $t) { Write-Output 'FAIL: type CameraExtension not found'; exit 1 }

$m = $t.Methods | Where-Object {
    $_.Name -eq 'IsSeewoCamera' -and
    $_.Parameters.Count -eq 1 -and
    $_.Parameters[0].ParameterType.Name -eq 'DsDevice' -and
    $_.HasBody -and -not $_.IsPInvokeImpl
}
if (-not $m) { Write-Output 'FAIL: method IsSeewoCamera(DsDevice) not found'; exit 1 }

Write-Output ("patching: " + $m.FullName)
$body = $m.Body
$body.Instructions.Clear()
$body.Variables.Clear()
$body.ExceptionHandlers.Clear()
$il = $body.GetILProcessor()
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$hasSn = $asm.Name.PublicKey -ne $null -and $asm.Name.PublicKey.Length -gt 0
Write-Output ("hasStrongName: " + $hasSn)

$asm.Write($OutDll)
Write-Output ("written: " + $OutDll)
