# fix-prefs.ps1 - rebuild akvcam prefs cleanly (9.4.1 IPC mode)
# Root cause v3: "add-device -i AkVCamVideoDevice0" FAILS because Device0's
# DirectShow COM CLSID is still registered from a previous deployment and
# isDeviceIdTaken() checks listAllCameras() (COM) too - wiping prefs can't
# free it. Fix: let add-device auto-allocate (Device0 is taken, so it
# deterministically gets Device1) and add-format on the ACTUAL id.
# NOTE: run add-device ONCE only (x64 and x86 managers share the same
# 64-view prefs via KEY_WOW64_64KEY; a 2nd add creates a twin device).
# Run as admin. Writes result to fix-prefs-result.txt (same dir).

$R = "D:\easi-connector\tools\fix-prefs-result.txt"
$m = "D:\easi-connector\tools\akvcam\x86\AkVCamManager.exe"

reg delete "HKLM\SOFTWARE\Webcamoid" /f 2>&1 | Out-Null

"--- add-device (auto id) ---" | Out-File $R -Encoding utf8
& $m add-device 'EASI-Bridge Camera' 2>&1 | Out-File $R -Append -Encoding utf8

"--- allocated id ---" | Out-File $R -Append -Encoding utf8
$id = (& $m devices 2>&1 | Select-Object -First 1)
$id | Out-File $R -Append -Encoding utf8

if (-not $id -or $id -notmatch '^AkVCamVideoDevice') {
    "ERROR: no device allocated" | Out-File $R -Append -Encoding utf8
    exit 1
}

"--- add-format on $id ---" | Out-File $R -Append -Encoding utf8
& $m add-format $id RGB24 1920 1080 30 2>&1 | Out-File $R -Append -Encoding utf8

"--- prefs after rebuild ---" | Out-File $R -Append -Encoding utf8
reg query "HKLM\SOFTWARE\Webcamoid\VirtualCamera" /s 2>&1 | Out-File $R -Append -Encoding utf8

"--- devices ---" | Out-File $R -Append -Encoding utf8
& $m devices 2>&1 | Out-File $R -Append -Encoding utf8
