# ilspycmd 包装：反编译单个程序集到 analysis\src\<name>\
param(
    [Parameter(Mandatory=$true)][string]$Assembly
)
$dotnet = 'D:\easi-connector\tools\dotnet\dotnet.exe'
$cmd = 'D:\easi-connector\tools\ilspycmd\tools\net10.0\any\ilspycmd.dll'
$name = [System.IO.Path]::GetFileNameWithoutExtension($Assembly)
$outDir = "D:\easi-connector\analysis\src\$name"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
& $dotnet $cmd $Assembly -p -o $outDir --nested-directories 2>&1 | Select-Object -Last 3
if ($LASTEXITCODE -eq 0) {
    $n = (Get-ChildItem -Recurse $outDir -Filter *.cs | Measure-Object).Count
    Write-Output "OK $name -> $n .cs files in $outDir"
} else {
    Write-Output "FAIL $name (exit $LASTEXITCODE)"
}
