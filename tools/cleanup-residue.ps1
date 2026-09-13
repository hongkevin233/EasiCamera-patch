# cleanup-residue.ps1 - remove stale DirectShow registrations for
# AkVCamVideoDevice0 ({FA39B84E-BBC3-4985-12DC-39C80A07C377}).
# This is exactly what akvcam's destroyDevice() does (Instance + CLSID keys).
# Residue exists because supportsMediaFoundationVCam() routes the manager's
# DllRegisterServer refresh to the MF plugin, so DirectShow entries for the
# old Device0 were never unregistered after prefs moved to Device1.
# Run as admin.

$R = 'D:\easi-connector\tools\cleanup-residue.txt'
$cat = '{860BB310-5D01-11d0-BD3B-00A0C911CE86}'
$dev0 = '{FA39B84E-BBC3-4985-12DC-39C80A07C377}'

"--- delete Device0 Instance (32bit view) ---" | Out-File $R -Encoding utf8
reg delete "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\$cat\Instance\$dev0" /f 2>&1 | Out-String | Out-File $R -Append -Encoding utf8

"--- delete Device0 Instance (64bit view) ---" | Out-File $R -Append -Encoding utf8
reg delete "HKLM\SOFTWARE\Classes\CLSID\$cat\Instance\$dev0" /f 2>&1 | Out-String | Out-File $R -Append -Encoding utf8

"--- delete Device0 CLSID (64bit view) ---" | Out-File $R -Append -Encoding utf8
reg delete "HKLM\SOFTWARE\Classes\CLSID\$dev0" /f 2>&1 | Out-String | Out-File $R -Append -Encoding utf8

"--- verify Device1 CLSID (32bit view) ---" | Out-File $R -Append -Encoding utf8
reg query "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{DC2C1D65-BC6C-A208-BE42-F4F40227F24A}" /s 2>&1 | Out-String | Out-File $R -Append -Encoding utf8

"--- verify capture Instances (32bit view) ---" | Out-File $R -Append -Encoding utf8
reg query "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\$cat\Instance" /s 2>&1 | Out-String | Out-File $R -Append -Encoding utf8
