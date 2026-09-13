# 把希沃展台窗口带到前台并截图 + 抓取设备过滤相关日志
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
$p = Get-Process EasiCamera -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($p) {
    [Win32]::ShowWindow($p.MainWindowHandle, 9) | Out-Null   # SW_RESTORE
    [Win32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    Start-Sleep -Seconds 2
}
$b = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen(0, 0, 0, 0, $b.Size)
$b.Save('D:\easi-connector\analysis\screen-orig2.png')
$g.Dispose(); $b.Dispose()
Write-Output 'screenshot saved'
Get-ChildItem 'C:\Users\diamo\AppData\Roaming\Seewo\EasiCamera\Log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 3 Name, LastWriteTime
