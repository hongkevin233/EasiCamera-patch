# -*- coding: utf-8 -*-
# dumpprobe.py — 从 minidump 提取 C0000005 异常记录链 + UTF-16 异常消息
#   用法: python dumpprobe.py <dump> [stack_base] [stack_size]
import sys, struct, bisect

path = sys.argv[1]
raw = open(path, 'rb').read()

n_streams = u32s = struct.unpack_from('<I', raw, 8)[0]
dir_rva = struct.unpack_from('<I', raw, 12)[0]
streams = {}
for i in range(n_streams):
    st, dsz, rva = struct.unpack_from('<III', raw, dir_rva + i * 12)
    if st:
        streams[st] = (rva, dsz)

# ---- modules ----
mods = []
if 4 in streams:
    rva = streams[4][0]
    n = struct.unpack_from('<I', raw, rva)[0]
    p = rva + 4
    for _ in range(n):
        base = struct.unpack_from('<Q', raw, p)[0]
        size = struct.unpack_from('<I', raw, p + 8)[0]
        nrva = struct.unpack_from('<I', raw, p + 20)[0]
        ln = struct.unpack_from('<I', raw, nrva)[0]
        name = raw[nrva + 4:nrva + 4 + ln].decode('utf-16-le', 'ignore')
        mods.append((base, base + size, name.split('\\')[-1]))
        p += 108

def mod_of(va):
    for lo, hi, nm in mods:
        if lo <= va < hi:
            return f'{nm}+0x{va-lo:X}'
    return None

# ---- memory map (Memory64 or Memory list) ----
ranges = []
if 9 in streams:
    rva = streams[9][0]
    n = struct.unpack_from('<Q', raw, rva)[0]
    cur = struct.unpack_from('<Q', raw, rva + 8)[0]
    p = rva + 16
    for _ in range(n):
        va, sz = struct.unpack_from('<QQ', raw, p)
        if sz:
            ranges.append((va, cur, sz))
        cur += sz
        p += 16
else:
    rva = streams[5][0]
    n = struct.unpack_from('<I', raw, rva)[0]
    p = rva + 4
    for _ in range(n):
        va, r, sz = struct.unpack_from('<QII', raw, p)
        if sz:
            ranges.append((va, r, sz))
        p += 16
ranges.sort()
starts = [r[0] for r in ranges]

def read_va(va, ln):
    i = bisect.bisect_right(starts, va) - 1
    if i < 0:
        return None
    base, ro, sz = ranges[i]
    if va + ln > base + sz:
        return None
    off = ro + (va - base)
    return raw[off:off + ln]

# ---- exception stream ----
print('=== exception stream ===')
if 6 in streams:
    rva, dsz = streams[6]
    tid = struct.unpack_from('<I', raw, rva)[0]
    code, flags = struct.unpack_from('<II', raw, rva + 8)
    inner, addr = struct.unpack_from('<QQ', raw, rva + 16)
    nparams = struct.unpack_from('<I', raw, rva + 32)[0]
    print(f'tid={tid} code=0x{code:08X} addr=0x{addr:X} ({mod_of(addr)}) inner=0x{inner:X} nparams={nparams}')
    for k in range(min(nparams, 15)):
        v = struct.unpack_from('<Q', raw, rva + 40 + k * 8)[0]
        print(f'  param[{k}]=0x{v:X}')

# ---- scan for C0000005 EXCEPTION_RECORD (x86 layout) on the crash stack ----
# x86 EXCEPTION_RECORD: Code(4) Flags(4) Next(4) Address(4) NumParams(4) Info[15](4)
print('=== C0000005 records (stack region) ===')
if len(sys.argv) >= 4 and sys.argv[2].lower().startswith('0x'):
    sb = int(sys.argv[2], 16)
    ss = int(sys.argv[3], 16)
    blob = read_va(sb, ss)
    if blob:
        for off in range(0, len(blob) - 32, 4):
            code = struct.unpack_from('<I', blob, off)[0]
            if code != 0xC0000005:
                continue
            fl, nx, ad, np_ = struct.unpack_from('<IIII', blob, off + 4)
            if np_ > 15 or np_ == 0:
                continue
            i0, i1 = struct.unpack_from('<II', blob, off + 20)
            va = sb + off
            rw = {0: 'READ', 1: 'WRITE', 8: 'EXEC'}.get(i0, str(i0))
            print(f'  @stack 0x{va:X}: addr=0x{ad:X} ({mod_of(ad) or "not-module"}) '
                  f'{rw} target=0x{i1:X} ({mod_of(i1) or ""}) flags={fl} next=0x{nx:X}')

# ---- object peek mode ----
if len(sys.argv) >= 3 and sys.argv[2] == 'obj':
    def u32va(va):
        b = read_va(va, 4)
        return struct.unpack('<I', b)[0] if b else None
    for arg in sys.argv[3:]:
        obj = int(arg, 16)
        vbptr = u32va(obj)
        print(f'--- obj 0x{obj:X}: [+0]=0x{vbptr:X}' if vbptr is not None else f'--- obj 0x{obj:X}: unmapped')
        if vbptr is None:
            continue
        m = mod_of(vbptr)
        print(f'    table 0x{vbptr:X} -> {m}')
        # dump table entries (vbtable: offsets; vtable: code ptrs)
        for k in range(1, 8):
            e = u32va(vbptr + 4 * k)
            if e is None:
                break
            print(f'    [{k}] 0x{e:X} ({mod_of(e) or "offset?"})')
        # dump raw object bytes
        blob = read_va(obj, 64)
        if blob:
            for row in range(4):
                vals = struct.unpack_from('<4I', blob, row * 16)
                print('    ' + ' '.join(f'{v:08X}' for v in vals))
        # follow each vbase-looking pointer: [+0x8] etc
        for off in (4, 8, 0xC, 0x10, 0x14):
            v = u32va(obj + off)
            if v is None:
                continue
            mm = mod_of(v)
            if mm and ('AkVirtualCamera' in mm or 'offset' not in mm):
                print(f'    [+0x{off:X}] ptr 0x{v:X} -> {mm}')
                t2 = u32va(v)
                if t2:
                    print(f'        [+0]=0x{t2:X} ({mod_of(t2)})')
                    for k in range(0, 4):
                        s = u32va(t2 + 4 * k)
                        if s:
                            print(f'        slot[{k}]=0x{s:X} ({mod_of(s)})')
                    # vtordisp @ [v-4]
                    vm = u32va(v - 4)
                    print(f'        [v-4]=0x{vm:X}' if vm is not None else '        [v-4] unmapped')
    sys.exit(0)

# ---- full UTF-16 message windows ----
if len(sys.argv) >= 3 and sys.argv[2] == 'msg':
    for needle in sys.argv[3:]:
        pat = needle.encode('utf-16-le')
        pos = 0
        count = 0
        while count < 8:
            idx = raw.find(pat, pos)
            if idx < 0:
                break
            lo = max(0, idx - 200)
            hi = min(len(raw), idx + 1400)
            txt = raw[lo:hi].decode('utf-16-le', 'ignore')
            txt = ''.join(c if 0x20 <= ord(c) < 0xFFFD else '\x01' for c in txt)
            segs = [s for s in txt.split('\x01') if needle in s]
            if segs:
                print(f'--- [{needle}] @file 0x{idx:X}')
                for s in segs[:3]:
                    print('   ', s[:1500])
            pos = idx + len(pat)
            count += 1
    sys.exit(0)

# ---- UTF-16 exception messages ----
print('=== UTF-16 exception messages ===')
needles = ['无法将类型', 'IAMStreamConfig', 'InvalidCastException', 'AccessViolationException',
           '尝试读取或写入受保护的内存'.encode('utf-16-le').decode('utf-16-le')]
for needle in needles:
    pat = needle.encode('utf-16-le')
    pos = 0
    count = 0
    while count < 6:
        idx = raw.find(pat, pos)
        if idx < 0:
            break
        lo = max(0, idx - 400)
        hi = min(len(raw), idx + 800)
        window = raw[lo:hi]
        # 提取可打印 UTF-16 文本
        txt = window.decode('utf-16-le', 'ignore')
        txt = ''.join(c if 0x20 <= ord(c) < 0xFFFD else '\n' for c in txt)
        line = max((l for l in txt.split('\n') if needle in l or len(l) > 20), key=len, default='')
        print(f'--- [{needle}] @file 0x{idx:X}')
        print('   ', line.strip()[:600])
        pos = idx + len(pat)
        count += 1
