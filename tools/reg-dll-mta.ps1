# 在 MTA 线程中直接调用 DLL 的 DllRegisterServer/DllUnregisterServer（绕开 regsvr32 的 STA 宿主限制）
# 用法: powershell -MTA -File reg-dll-mta.ps1 -DllPath <dll> -OutFile <结果文件> [-Unregister]
param(
    [Parameter(Mandatory = $true)][string]$DllPath,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

$src = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class RegDllMta
{
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibrary(string fileName);

    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string procName);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int DllRegisterServerDelegate();

    public static int Run(string dllPath, bool unregister)
    {
        int hr = -99;
        Exception err = null;

        // 独立 MTA 线程：保证与 DllRegisterServer 内部 CoInitializeEx(MTA) 兼容
        var t = new Thread(() =>
        {
            try
            {
                IntPtr h = LoadLibrary(dllPath);
                if (h == IntPtr.Zero) { hr = -1; return; }

                IntPtr p = GetProcAddress(h, unregister ? "DllUnregisterServer" : "DllRegisterServer");
                if (p == IntPtr.Zero) { hr = -2; return; }

                var fn = (DllRegisterServerDelegate)Marshal.GetDelegateForFunctionPointer(
                    p, typeof(DllRegisterServerDelegate));
                hr = fn();
            }
            catch (Exception e) { err = e; }
        });
        t.SetApartmentState(ApartmentState.MTA);
        t.Start();
        t.Join();

        if (err != null) throw err;
        return hr;
    }
}
'@

Add-Type -TypeDefinition $src
$hr = [RegDllMta]::Run($DllPath, [bool]$Unregister)
Set-Content -Path $OutFile -Value $hr
'DllPath={0} HRESULT={1} (0x{2:X8})' -f $DllPath, $hr, $hr
