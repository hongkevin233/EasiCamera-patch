import sys
import struct
from minidump.minidumpfile import MinidumpFile

path = sys.argv[1] if len(sys.argv) > 1 else r'D:\easi-connector\tools\dumps\EasiCamera.exe_260913_021916.dmp'
mf = MinidumpFile.parse(path)

print('=== Exception Stream ===')
rec = mf.exception.exception_records[0]
er = rec.ExceptionRecord
code = er.ExceptionCode_raw if hasattr(er, 'ExceptionCode_raw') else er.ExceptionCode
print('code: 0x%08X  addr: 0x%X  nparams: %d' % (int(code), int(er.ExceptionAddress), er.NumberParameters))
for i, p in enumerate(er.ExceptionInformation or []):
    print('  param[%d] = 0x%X' % (i, int(p)))
exc_tid = rec.ThreadId
print('exception thread: %d' % exc_tid)

print()
print('=== Modules ===')
mods = []
for m in mf.modules.modules:
    mods.append((m.baseaddress, m.baseaddress + m.size, m.name))


def find_mod(addr):
    for lo, hi, name in mods:
        if lo <= addr < hi:
            return '%s+0x%X' % (name.replace('\\', '/').split('/')[-1], addr - lo)
    return '?'


# memory reader
reader = mf.get_reader()


def va_read(va, n):
    try:
        return reader.read(va, n)
    except Exception:
        return None


def va_u32(va):
    b = va_read(va, 4)
    if b and len(b) == 4:
        return struct.unpack('<I', b)[0]
    return None


# thread context — procdump on WOW64 stores AMD64 CONTEXT (1232 bytes)
tc = rec.ThreadContext
mf.file_handle.seek(tc.Rva)
ctx = mf.file_handle.read(tc.DataSize)
print('ctx size: 0x%X' % len(ctx))

if len(ctx) == 1232:
    Rax, Rcx, Rdx, Rbx, Rsp, Rbp, Rsi, Rdi = struct.unpack_from('<8Q', ctx, 0x78)
    Rip = struct.unpack_from('<Q', ctx, 0xF8)[0]
    M32 = 0xFFFFFFFF
    eax, ecx, edx, ebx = Rax & M32, Rcx & M32, Rdx & M32, Rbx & M32
    esp, ebp, esi, edi = Rsp & M32, Rbp & M32, Rsi & M32, Rdi & M32
    eip = Rip & M32
else:
    edi = struct.unpack_from('<I', ctx, 0x9C)[0]
    esi = struct.unpack_from('<I', ctx, 0xA0)[0]
    ebx = struct.unpack_from('<I', ctx, 0xA4)[0]
    edx = struct.unpack_from('<I', ctx, 0xA8)[0]
    ecx = struct.unpack_from('<I', ctx, 0xAC)[0]
    eax = struct.unpack_from('<I', ctx, 0xB0)[0]
    ebp = struct.unpack_from('<I', ctx, 0xB4)[0]
    eip = struct.unpack_from('<I', ctx, 0xB8)[0]
    esp = struct.unpack_from('<I', ctx, 0xC4)[0]

print()
print('=== Registers ===')
print('EIP=0x%08X (%s)' % (eip, find_mod(eip)))
print('EAX=0x%08X (%s)' % (eax, find_mod(eax)))
print('EBX=0x%08X (%s)' % (ebx, find_mod(ebx)))
print('ECX=0x%08X (%s)' % (ecx, find_mod(ecx)))
print('EDX=0x%08X (%s)' % (edx, find_mod(edx)))
print('ESI=0x%08X (%s)' % (esi, find_mod(esi)))
print('EDI=0x%08X (%s)' % (edi, find_mod(edi)))
print('EBP=0x%08X  ESP=0x%08X' % (ebp, esp))

print()
print('=== EBP walk ===')
n = 0
f = ebp
while f and n < 32:
    ret = va_u32(f + 4)
    nxt = va_u32(f)
    if ret is None:
        print('  [0x%08X] <unreadable>' % f)
        break
    print('  [ebp 0x%08X] ret -> 0x%08X (%s)' % (f, ret, find_mod(ret)))
    if nxt is None or nxt <= f or nxt > f + 0x10000:
        break
    f = nxt
    n += 1

print()
print('=== Stack scan (code pointers near ESP) ===')
stack_data = va_read(esp, 0x2000)
if stack_data:
    out = []
    for i in range(0, len(stack_data) - 4, 4):
        (v,) = struct.unpack_from('<I', stack_data, i)
        m = find_mod(v)
        if m != '?':
            out.append('  [esp+0x%04X = 0x%08X] -> %s' % (i, esp + i, m))
    for line in out[:80]:
        print(line)
