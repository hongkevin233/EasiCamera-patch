// EasiCamera.Api.dll patcher：IsSeewoCamera(DsDevice) -> return true
// 用法: Patcher.exe <in.dll> <out.dll>
using System;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

class Patcher
{
    static int Main(string[] args)
    {
        if (args.Length < 2) { Console.WriteLine("usage: Patcher <in.dll> <out.dll>"); return 2; }
        var asm = AssemblyDefinition.ReadAssembly(args[0]);
        var mod = asm.MainModule;

        var ext = mod.Types.FirstOrDefault(t => t.Name == "CameraExtension");
        if (ext == null) { Console.WriteLine("type CameraExtension not found"); return 1; }

        var m = ext.Methods.FirstOrDefault(x =>
            x.Name == "IsSeewoCamera" &&
            x.Parameters.Count == 1 &&
            x.Parameters[0].ParameterType.Name == "DsDevice" &&
            x.HasBody && !x.IsPInvokeImpl);
        if (m == null) { Console.WriteLine("method IsSeewoCamera(DsDevice) not found"); return 1; }

        Console.WriteLine("patching: " + m.FullName);
        var body = m.Body;
        body.Instructions.Clear();
        body.Variables.Clear();
        body.ExceptionHandlers.Clear();
        var il = body.GetILProcessor();
        il.Append(il.Create(OpCodes.Ldc_I4_1));
        il.Append(il.Create(OpCodes.Ret));
        Console.WriteLine("hasStrongName: " + (asm.Name.PublicKey != null && asm.Name.PublicKey.Length > 0));

        asm.Write(args[1]);
        Console.WriteLine("written: " + args[1]);
        return 0;
    }
}
