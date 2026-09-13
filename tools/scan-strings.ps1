# 在 .NET 程序集中扫描 UTF-16LE / ASCII 字符串特征（VID/PID/设备名/白名单关键词）
param(
    [string[]]$Files,
    [string[]]$Keywords
)

foreach ($f in $Files) {
    if (-not (Test-Path $f)) { Write-Output "MISSING: $f"; continue }
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $u16 = [System.Text.Encoding]::Unicode.GetString($bytes)
    $a1  = [System.Text.Encoding]::ASCII.GetString($bytes)
    Write-Output "===== $(Split-Path $f -Leaf) ($($bytes.Length) bytes) ====="
    foreach ($kw in $Keywords) {
        foreach ($enc in @(@('u16', $u16), @('asc', $a1))) {
            $name = $enc[0]; $text = $enc[1]
            $start = 0; $count = 0
            while ($count -lt 6) {
                $i = $text.IndexOf($kw, $start, [System.StringComparison]::OrdinalIgnoreCase)
                if ($i -lt 0) { break }
                $s = [Math]::Max(0, $i - 60)
                $len = [Math]::Min(160, $text.Length - $s)
                $ctx = $text.Substring($s, $len) -replace '[^\x20-\x7E]', '.'
                Write-Output ("  [{0}] {1}: ...{2}..." -f $name, $kw, $ctx)
                $start = $i + $kw.Length; $count++
            }
        }
    }
}
