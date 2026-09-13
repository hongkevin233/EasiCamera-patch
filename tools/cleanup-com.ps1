# Cleanup COM registration (run in ELEVATED PowerShell)
# 1) Remove junk keys created by previous encoding-bug run
# 2) Remove ghost device instance {C293D0EE-...} (AkVCamVideoDevice2, stale)
# 3) Ensure FilterMapper2 machine-wide registration (both views -> quartz.dll)

$ErrorActionPreference = 'Continue'
Start-Transcript D:\easi-connector\tools\cleanup-com.log -Force

Write-Host '===== 1. Remove junk keys ====='
Remove-Item 'HKLM:\SOFTWARE\Classes\CLSID\InprocServer32' -Recurse -Force
Remove-Item 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\InprocServer32' -Recurse -Force
Write-Host "junk64 still exists: $(Test-Path 'HKLM:\SOFTWARE\Classes\CLSID\InprocServer32')"
Write-Host "junk32 still exists: $(Test-Path 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\InprocServer32')"

Write-Host '===== 2. Remove ghost device instance ====='
Remove-Item 'HKLM:\SOFTWARE\Classes\CLSID\{860BB310-5D01-11D0-BD3B-00A0C911CE86}\Instance\{C293D0EE-673F-CB17-9052-CAAD5288DFCB}' -Recurse -Force
Write-Host "ghost still exists: $(Test-Path 'HKLM:\SOFTWARE\Classes\CLSID\{860BB310-5D01-11D0-BD3B-00A0C911CE86}\Instance\{C293D0EE-673F-CB17-9052-CAAD5288DFCB}')"

Write-Host '===== 3. Ensure FilterMapper2 machine-wide ====='
New-Item 'HKLM:\SOFTWARE\Classes\CLSID\{C1D403C6-D3D4-11D0-9DBE-0000F8004573}\InprocServer32' -Force | Out-Null
New-Item 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\{C1D403C6-D3D4-11D0-9DBE-0000F8004573}\InprocServer32' -Force | Out-Null
Set-Item 'HKLM:\SOFTWARE\Classes\CLSID\{C1D403C6-D3D4-11D0-9DBE-0000F8004573}' -Value 'Filter Mapper 2'
Set-Item 'HKLM:\SOFTWARE\Classes\CLSID\{C1D403C6-D3D4-11D0-9DBE-0000F8004573}\InprocServer32' -Value 'C:\Windows\System32\quartz.dll'
New-ItemProperty 'HKLM:\SOFTWARE\Classes\CLSID\{C1D403C6-D3D4-11D0-9DBE-0000F8004573}\InprocServer32' -Name ThreadingModel -Value Both -PropertyType String -Force | Out-Null
Set-Item 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\{C1D403C6-D3D4-11D0-9DBE-0000F8004573}\InprocServer32' -Value 'C:\Windows\SysWOW64\quartz.dll'
New-ItemProperty 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\{C1D403C6-D3D4-11D0-9DBE-0000F8004573}\InprocServer32' -Name ThreadingModel -Value Both -PropertyType String -Force | Out-Null

Write-Host '===== 4. Verify ====='
reg.exe query 'HKLM\SOFTWARE\Classes\CLSID\{860BB310-5D01-11D0-BD3B-00A0C911CE86}\Instance' /s /reg:64
reg.exe query 'HKLM\SOFTWARE\Classes\CLSID\{C1D403C6-D3D4-11D0-9DBE-0000F8004573}' /s /reg:64

Stop-Transcript
Set-Content D:\easi-connector\tools\cleanup-com.done 'done'
Write-Host ''
Write-Host 'DONE. Tell Trae it finished.'
