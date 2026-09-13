Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32b {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@
$p = Get-Process EasiCamera -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output 'no EasiCamera window'; exit 1 }
# 最大化 + 置顶（TOPMOST 再取消，绕过前台锁定）
[W32b]::ShowWindow($p.MainWindowHandle, 3) | Out-Null
[W32b]::SetWindowPos($p.MainWindowHandle, [IntPtr]-1, 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null
Start-Sleep -Seconds 3
$b = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen(0, 0, 0, 0, $b.Size)
$b.Save('D:\easi-connector\analysis\seewo-max.png')
$g.Dispose(); $b.Dispose()
[W32b]::SetWindowPos($p.MainWindowHandle, [IntPtr]-2, 0, 0, 0, 0, 0x0001 -bor 0x0002) | Out-Null
Write-Output 'saved seewo-max.png'
