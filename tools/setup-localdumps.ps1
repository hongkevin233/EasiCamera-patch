# Configure WER LocalDumps to capture full dumps on crash
$ErrorActionPreference = 'Continue'
$out = 'D:\easi-connector\tools\dumps-setup-result.txt'
"dumps setup start $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $out -Encoding utf8

New-Item -ItemType Directory -Path 'D:\easi-connector\tools\dumps' -Force | Out-Null

$targets = @('EasiCamera.exe', 'AkVCamAssistant.exe', 'AkVCamAssistantMF.exe', 'AkVCamManager.exe')
foreach ($t in $targets) {
    $key = "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\$t"
    reg add $key /v DumpFolder /t REG_EXPAND_SZ /d 'D:\easi-connector\tools\dumps' /f 2>&1 | Out-Null
    reg add $key /v DumpType /t REG_DWORD /d 2 /f 2>&1 | Out-Null
    reg add $key /v DumpCount /t REG_DWORD /d 10 /f 2>&1 | Out-Null
    "$t -> LocalDumps configured" | Out-File $out -Append -Encoding utf8
}

# verify
foreach ($t in $targets) {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\$t"
    $v = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($v) {
        "$t OK: DumpType=$($v.DumpType) DumpFolder=$($v.DumpFolder)" | Out-File $out -Append -Encoding utf8
    } else {
        "$t MISSING" | Out-File $out -Append -Encoding utf8
    }
}

"dumps setup done $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $out -Append -Encoding utf8
