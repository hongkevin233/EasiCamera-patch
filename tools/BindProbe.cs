// BindProbe: 逐设备 DirectShow BindToObject 诊断
// csc /r:DirectShowLib.dll BindProbe.cs
using System;
using DirectShowLib;

class BindProbe
{
    static int Main()
    {
        var devices = DsDevice.GetDevicesOfCat(FilterCategory.VideoInputDevice);
        Console.WriteLine("devices: " + devices.Length);
        foreach (var d in devices)
        {
            Console.WriteLine("== " + d.Name);
            Console.WriteLine("   path: " + d.DevicePath);
            try
            {
                var guid = new Guid("083886C1-5ADE-4B5C-BA08-60B4F0B2D278"); // IBaseFilter
                object obj = d.Mon.BindToObject(null, null, ref guid);
                var filter = (IBaseFilter)obj;
                Console.WriteLine("   bind: OK");
                // capabilities
                var pin = DsFindPin.ByCategory(filter, PinCategory.Capture, 0);
                if (pin == null) { Console.WriteLine("   no capture pin"); }
                else
                {
                    var sc = pin as IAMStreamConfig;
                    if (sc == null) Console.WriteLine("   pin has NO IAMStreamConfig");
                    else
                    {
                        int count = 0, size = 0;
                        sc.GetNumberOfCapabilities(ref count, ref size);
                        Console.WriteLine("   caps: " + count);
                        var mt = new AMMediaType();
                        var capBuf = new byte[size];
                        for (int i = 0; i < Math.Min(count, 8); i++)
                        {
                            if (sc.GetStreamCaps(i, mt, capBuf) == 0)
                            {
                                Console.WriteLine("     subtype=" + mt.subType.ToString("B"));
                                DsUtils.FreeAMMediaType(mt);
                                mt = new AMMediaType();
                            }
                        }
                    }
                    MarshalRelease(pin);
                }
                MarshalRelease(obj);
            }
            catch (Exception e)
            {
                Console.WriteLine("   bind FAILED: " + e.Message);
            }
        }
        return 0;
    }

    static void MarshalRelease(object o)
    {
        try { System.Runtime.InteropServices.Marshal.ReleaseComObject(o); } catch { }
    }
}
