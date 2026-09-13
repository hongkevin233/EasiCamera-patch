# kill-mf-assistant.ps1
$R = 'D:\easi-connector\tools\kill-mf-result.txt'
"=== kill AkVCamAssistantMF $(Get-Date) ===" | Out-File $R -Encoding utf8
Get-Process AkVCamAssistantMF -ErrorAction SilentlyContinue | ForEach-Object {
    "killing PID $($_.Id)" | Out-File $R -Append -Encoding utf8
    $_.Kill()
}
Start-Sleep 1
try {
    Copy-Item 'D:\easi-connector\build941-x64\build\x64\Release\AkVCamAssistantMF.exe' 'D:\easi-connector\tools\akvcam\x64\AkVCamAssistantMF.exe' -Force -ErrorAction Stop
    'COPY OK' | Out-File $R -Append -Encoding utf8
} catch {
    "COPY FAIL: $_" | Out-File $R -Append -Encoding utf8
}
Get-Item 'D:\easi-connector\tools\akvcam\x64\AkVCamAssistantMF.exe' | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 120 | Out-File $R -Append -Encoding utf8
'DONE' | Out-File $R -Append -Encoding utf8
