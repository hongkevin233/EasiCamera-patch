# 快速定位 NSIS firstheader（Latin1 string IndexOf）并切片，只找第一个命中
param(
    [string]$In = 'D:\easi-connector\pkg\EasiCamera-2.1.0.4410.exe',
    [string]$OutDir = 'D:\easi-connector\analysis'
)

$needle = [string][char]0xEF + [char]0xBE + [char]0xAD + [char]0xDE + 'NullsoftInst'
$enc = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
$fs = [System.IO.File]::OpenRead($In)
try {
    $buf = New-Object byte[] (4MB)
    $overlap = $needle.Length
    $fileOffset = 0L
    $carry = ''
    while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
        $text = $enc.GetString($buf, 0, $read)
        $hay = $carry + $text
        $idx = $hay.IndexOf($needle, [System.StringComparison]::Ordinal)
        if ($idx -ge 0) {
            $abs = [long]($fileOffset - $carry.Length + $idx)
            Write-Output ("NSIS firstheader @ 0x{0:X}" -f $abs)
            $slicePath = Join-Path $OutDir 'easicamera.nsis.bin'
            $src = [System.IO.File]::OpenRead($In)
            $dst = [System.IO.File]::Create($slicePath)
            $src.Seek($abs, 'Begin') | Out-Null
            $src.CopyTo($dst)
            $dst.Close(); $src.Close()
            $len = (Get-Item $In).Length - $abs
            Write-Output ("SLICED {0} bytes -> {1}" -f $len, $slicePath)
            exit 0
        }
        $carry = $hay.Substring([Math]::Max(0, $hay.Length - $overlap))
        $fileOffset += $read
    }
    Write-Output 'NO NSIS FIRSTHEADER FOUND'
    exit 1
} finally { $fs.Close() }
