# -*- coding: utf-8 -*-
# 崩溃线程栈精查：IID_IClassFactory / CLSID 参数 / 0x41400000 垃圾指针槽位
# 已知现场：tid=13256 EIP=combase+0xA1D4E ESP=0x09F1DCD8 EBP=0x09F1DD5C EAX=0x41400000
import struct

path = r'D:\easi-connector\tools\dumps\EasiCamera.exe_260913_021916.dmp'
raw = open(path, 'rb').read()

n_streams = struct.unpack_from('<I', raw, 8)[0]
dir_rva = struct.unpack_from('<I', raw, 12)[0]
streams = {}
for i in range(n_streams):
    off = dir_rva + i * 12
    stype, dsz, rva = struct.unpack_from('<III', raw, off)
    if stype:
        streams[stype] = (rva, dsz)

# 内存范围
ranges = []
rva, dsz = streams[9]
n = struct.unpack_from('<Q', raw, rva)[0]
cur = struct.unpack_from('<Q', raw, rva + 8)[0]
p = rva + 16
for i in range(n):
    va, sz = struct.unpack_from('<QQ', raw, p)
    ranges.append((va, cur, sz))
    cur += sz
    p += 16

def va_read(va, n):
    off = None
    for mva, r, sz in ranges:
        if mva <= va < mva + sz:
            off = r + (va - mva)
            break
    if off is None:
        return None
    return raw[off:off + n]

def mod_of(va):
    # 模块表
    mods = []
    r4, _ = streams[4]
    cnt = struct.unpack_from('<I', raw, r4)[0]
    p = r4 + 4
    for i in range(cnt):
        base = struct.unpack_from('<Q', raw, p)[0]
        msize = struct.unpack_from('<I', raw, p + 8)[0]
        nameRva = struct.unpack_from('<I', raw, p + 20)[0]
        nlen = struct.unpack_from('<I', raw, nameRva)[0]
        name = raw[nameRva + 4:nameRva + 4 + nlen].decode('utf-16-le', 'ignore')
        mods.append((base, base + msize, name))
        p += 108
    for lo, hi, name in mods:
        if lo <= va < hi:
            return '%s+0x%X' % (name.split('\\')[-1], va - lo)
    return 'heap/stack'

ESP = 0x09F1DCD8
lo_va, hi_va = ESP - 0x3000, ESP + 0x6000
stack = va_read(lo_va, hi_va - lo_va)
print('crash stack window 0x%X-0x%X got %d bytes' % (lo_va, hi_va, len(stack) if stack else 0))

def dump_ctx(va, before=24, after=40):
    b = va_read(va - before, before + after)
    if b is None:
        print('  (unreadable)')
        return
    for i in range(0, len(b), 16):
        chunk = b[i:i + 16]
        print('  0x%08X: %s' % (va - before + i, ' '.join('%02X' % x for x in chunk)))

# 1) IID_IClassFactory = 00000001-0000-0000-C000-000000000046
iid = bytes.fromhex('0100000000000000c000000000000046')
print('\n===== IID_IClassFactory 在崩溃栈窗口 =====')
pos = 0
while True:
    idx = stack.find(iid, pos)
    if idx < 0:
        break
    va = lo_va + idx
    print('hit VA=0x%08X (ESP%+d)' % (va, va - ESP))
    dump_ctx(va, 16, 48)
    pos = idx + 1

# 2) 三个设备 CLSID 在栈窗口
GUIDS = {
    'AKV(DC2C1D65)': bytes.fromhex('651d2cdc6cbc08a2be42f4f40227f24a'),
    'AMD(99621C9D)': bytes.fromhex('9d1c6299667c704b86d1e0ce7a8d7463'),
    'OBS(A3FCE0F5)': bytes.fromhex('f5e0fca393349f41958aaba1250ec20b'),
}
for gname, gpat in GUIDS.items():
    print('\n===== %s 在崩溃栈窗口 =====' % gname)
    pos = 0
    while True:
        idx = stack.find(gpat, pos)
        if idx < 0:
            break
        va = lo_va + idx
        print('hit VA=0x%08X (ESP%+d)' % (va, va - ESP))
        dump_ctx(va, 16, 32)
        pos = idx + 1

# 3) 0x41400000 存放槽位
pat = struct.pack('<I', 0x41400000)
print('\n===== 0x41400000 存放位置（崩溃栈窗口）=====')
pos = 0
while True:
    idx = stack.find(pat, pos)
    if idx < 0:
        break
    va = lo_va + idx
    print('stored VA=0x%08X (ESP%+d)' % (va, va - ESP))
    dump_ctx(va, 20, 20)
    pos = idx + 1

# 4) 栈窗口内指向 AkVirtualCamera.dll 的指针
AKV_LO, AKV_HI = 0x5A350000, 0x5A350000 + 0xE0000
print('\n===== 指向 AkVirtualCamera.dll 的栈值 =====')
for i in range(0, len(stack) - 4, 4):
    v = struct.unpack_from('<I', stack, i)[0]
    if AKV_LO <= v < AKV_HI:
        va = lo_va + i
        print('  VA=0x%08X (ESP%+d) -> AkVCam+0x%X' % (va, va - ESP, v - AKV_LO))
