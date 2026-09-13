# -*- coding: utf-8 -*-
# avstack.py — EasiCamera dump 取证
#   outer     异常流 + 崩溃线程栈模块命中（64 位侧，WOW64 下意义有限）
#   scan [N]  暴力扫 32 位私有 RW 区找栈候选
#   wow  [N]  解析 WOW64 内嵌 32 位子 dump（流 0xFFF3/4/5/6）：
#             真实 32 位异常上下文 + 崩溃栈 + 0x41400000 标记 + 存活 AkVCam 对象
import sys, struct, bisect

def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def u64(b, o): return struct.unpack_from('<Q', b, o)[0]

path = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else 'outer'
NARG = 150
raw = open(path, 'rb').read()

n_streams = u32(raw, 8); dir_rva = u32(raw, 12)
streams = {}
for i in range(n_streams):
    st, dsz, rva = struct.unpack_from('<III', raw, dir_rva + i * 12)
    if st: streams[st] = (rva, dsz)

def parse_modules(stype):
    if stype not in streams: return []
    rva = streams[stype][0]
    n = u32(raw, rva); p = rva + 4; out = []
    for _ in range(n):
        base = u64(raw, p); size = u32(raw, p + 8); nrva = u32(raw, p + 20)
        ln = u32(raw, nrva)
        name = raw[nrva + 4:nrva + 4 + ln].decode('utf-16-le', 'ignore')
        out.append((base, base + size, name)); p += 108
    return out

def make_map(stype):
    """[(va_start, file_off, size)]"""
    if stype not in streams: return []
    rva = streams[stype][0]; out = []
    if stype == 9:  # Memory64List: n(8) baseRva(8) then {start(8) size(8)}
        n = u64(raw, rva); cur = u64(raw, rva + 8); p = rva + 16
        for _ in range(n):
            va, sz = u64(raw, p), u64(raw, p + 8)
            if sz: out.append((va, cur, sz))
            cur += sz; p += 16
    else:           # MemoryList: n(4) then {start(8) dataSize(4) rva(4)}
        n = u32(raw, rva); p = rva + 4
        for _ in range(n):
            va, r, sz = struct.unpack_from('<QII', raw, p)
            if sz: out.append((va, r, sz))
            p += 16
    return out

def resolver(mods, maps):
    maps = sorted(maps); starts = [m[0] for m in maps]
    def mod_of(va):
        for lo, hi, nm in mods:
            if lo <= va < hi: return nm, va - lo
        return None, None
    def va_off(va):
        i = bisect.bisect_right(starts, va) - 1
        if i >= 0:
            base, r, sz = maps[i]
            if va < base + sz: return r + (va - base)
        return None
    return mod_of, va_off

def short(nm): return nm.split('\\')[-1]
FOCUS = ('qcap.dll', 'quartz.dll', 'akvirtualcamera.dll',
         'akvirtualcameramf.dll', 'combase.dll', 'easicamera.exe')

def walk(blob, lo, mod_of):
    hits = []
    for off in range(0, len(blob) - 3, 4):
        v = u32(blob, off)
        m, d = mod_of(v)
        if m: hits.append((lo + off, v, m, d))
    return hits

# ---------------- wow: 异常流 i386 CONTEXT + 真实 32 位崩溃栈 ----------------
if mode == 'wow':
    NARG = int(sys.argv[3]) if len(sys.argv) > 3 else 150
    mods = parse_modules(4)
    maps = make_map(9) + make_map(5)
    mod_of, va_off = resolver(mods, maps)
    print('modules=%d mem-ranges=%d' % (len(mods), len(maps)))

    er = streams[6][0]
    tid = u32(raw, er); code = u32(raw, er + 8); eaddr = u64(raw, er + 24)
    np = u32(raw, er + 32); p0 = u64(raw, er + 40); p1 = u64(raw, er + 48)
    csz = u32(raw, er + 160); crva = u32(raw, er + 164)

    mn, md = mod_of(eaddr)
    print('EXCEPTION tid=%d code=0x%08X addr=0x%08X %s' % (
        tid, code, eaddr, ('-> %s+0x%X' % (short(mn), md)) if mn else ''))
    if code == 0xC0000005:
        print('  fault: %s VA=0x%X %s' % ({0: 'READ', 1: 'WRITE', 8: 'DEP'}.get(p0, p0),
              p1, 'MAPPED' if va_off(p1) is not None else 'NOT MAPPED'))
    print('ctx size=%d rva=0x%X' % (csz, crva))

    ctx = raw[crva:crva + csz]
    if csz == 716:      # i386 CONTEXT
        R = dict(Eax=u32(ctx, 0xB0), Ebx=u32(ctx, 0xA4), Ecx=u32(ctx, 0xAC),
                 Edx=u32(ctx, 0xA8), Esi=u32(ctx, 0xA0), Edi=u32(ctx, 0x9C),
                 Ebp=u32(ctx, 0xB4), Eip=u32(ctx, 0xB8), Esp=u32(ctx, 0xC4))
    else:               # x64 CONTEXT
        R64 = dict(Rax=u64(ctx, 0x78), Rcx=u64(ctx, 0x80), Rdx=u64(ctx, 0x88),
                   Rbx=u64(ctx, 0x90), Rsp=u64(ctx, 0x98), Rbp=u64(ctx, 0xA0),
                   Rsi=u64(ctx, 0xA8), Rdi=u64(ctx, 0xB0), Rip=u64(ctx, 0xF0))
        R = dict(Eax=R64['Rax'] & 0xFFFFFFFF, Ebx=R64['Rbx'] & 0xFFFFFFFF,
                 Ecx=R64['Rcx'] & 0xFFFFFFFF, Edx=R64['Rdx'] & 0xFFFFFFFF,
                 Esi=R64['Rsi'] & 0xFFFFFFFF, Edi=R64['Rdi'] & 0xFFFFFFFF,
                 Ebp=R64['Rbp'] & 0xFFFFFFFF, Eip=R64['Rip'] & 0xFFFFFFFF,
                 Esp=R64['Rsp'] & 0xFFFFFFFF)
        print('  (x64 context!) Rip=0x%X Rsp=0x%X' % (R64['Rip'], R64['Rsp']))
    print('  regs: %s' % ' '.join('%s=0x%08X' % (k, R[k]) for k in
          ('Eax', 'Ebx', 'Ecx', 'Edx', 'Esi', 'Edi', 'Ebp', 'Eip', 'Esp')))
    mn, md = mod_of(R['Eip'])
    print('  EIP: %s+0x%X' % (short(mn), md) if mn else '  EIP: unmapped 0x%08X' % R['Eip'])
    eo = va_off(R['Eip'])
    if eo is not None:
        print('  bytes@EIP: %s' % ' '.join('%02X' % b for b in raw[eo:eo + 16]))

    print('--- register peeks (deref) ---')
    for nm in ('Eax', 'Ebx', 'Ecx', 'Edx', 'Esi', 'Edi', 'Ebp'):
        v = R[nm]
        if not (0x10000 <= v < 0x7FFE0000):
            continue
        o = va_off(v)
        if o is None:
            print('  [%s]=0x%08X -> not mapped' % (nm, v)); continue
        vt = u32(raw, o)
        vm, vd = mod_of(vt)
        print('  [%s]=0x%08X vtable=0x%08X %s | %s' % (
            nm, v, vt,
            ('(%s+0x%X)' % (short(vm), vd)) if vm else 'NOT-module',
            ' '.join('%02X' % b for b in raw[o:o + 32])))

    # 从 ESP 向上拼栈页
    lo = R['Esp'] & ~0xFFF; blob = b''; a = lo
    while a < lo + 0x10000:
        oo = va_off(a)
        if oo is None: break
        blob += raw[oo:oo + 0x1000]; a += 0x1000
    print('stack from ESP=0x%X, base=0x%X len=0x%X' % (R['Esp'], lo, len(blob)))

    hits = walk(blob, lo, mod_of)
    esp = R['Esp']
    sel = [h for h in hits if h[0] >= esp - 8]
    print('--- 32-bit crash chain (asc stack addr, innermost first) %d hits ---' % len(sel))
    for sva, v, nm, d in sel[:NARG]:
        mark = '   <<<' if short(nm).lower() in FOCUS else ''
        print('  [0x%08X] %s+0x%X%s' % (sva, nm, d, mark))

    print('--- stack scan: 0x41400000 marker / live AkVCam objects ---')
    for off in range(0, len(blob) - 3, 4):
        sva = lo + off; v = u32(blob, off)
        if v in (0x41400000, 0x4140000C):
            print('  [0x%08X] = 0x%08X  !!! marker' % (sva, v))
        elif 0x10000 <= v < 0x7FFE0000:
            o = va_off(v)
            if o is None: continue
            vt = u32(raw, o); vm, vd = mod_of(vt)
            if vm and 'akvirtualcamera' in short(vm).lower():
                print('  [0x%08X] obj=0x%08X vtable %s+0x%X' % (sva, v, short(vm), vd))
    sys.exit(0)

# ---------------- mem: 打印某 VA 周边内存区域布局 ----------------
if mode == 'mem':
    mods = parse_modules(4)
    maps = make_map(9) + make_map(5)
    mod_of, va_off = resolver(mods, maps)
    va = int(sys.argv[3], 16)
    for nm, lo, hi in [(n, l, h) for l, h, n in mods if l <= va < h]:
        print('module: %s base=0x%08X size=0x%X' % (nm, lo, hi - lo))
    for st in (9, 5):
        for s, o, sz in sorted(maps):
            if s - 0x40000 <= va < s + sz + 0x40000:
                mark = '  <<< contains VA' if s <= va < s + sz else ''
                print('stream%d: start=0x%08X size=0x%06X end=0x%08X off=0x%08X%s'
                      % (st, s, sz, s + sz, o, mark))
    if 16 in streams:
        rva = streams[16][0]
        hdr, ent, nmi = struct.unpack_from('<IIQ', raw, rva)
        p = rva + hdr
        for _ in range(nmi):
            base, ab, ap, _a1, rsz, state, prot, typ, _a2 = \
                struct.unpack_from('<QQIIQIIII', raw, p)
            if base - 0x40000 <= va < base + rsz + 0x40000:
                mark = '  <<< contains VA' if base <= va < base + rsz else ''
                print('meminfo: base=0x%08X size=0x%06X state=0x%X prot=0x%X type=0x%X%s'
                      % (base, rsz, state, prot, typ, mark))
            p += ent
    sys.exit(0)

# ---------------- find / peek ----------------
if mode in ('find', 'peek'):
    mods = parse_modules(4)
    maps = make_map(9) + make_map(5)
    mod_of, va_off = resolver(mods, maps)

    if mode == 'peek':
        va = int(sys.argv[3], 16)
        nb = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x80
        mn, md = mod_of(va)
        print('peek 0x%08X %s' % (va, ('%s+0x%X' % (short(mn), md)) if mn else ''))
        o = va_off(va)
        if o is None:
            print('  not mapped'); sys.exit(1)
        blob = raw[o:o + nb]
        for i in range(0, len(blob), 16):
            row = blob[i:i + 16]
            print('  +0x%02X: %-47s %s' % (i,
                  ' '.join('%02X' % b for b in row),
                  ''.join(chr(b) if 32 <= b < 127 else '.' for b in row)))
        dwords = [u32(blob, i) for i in range(0, len(blob) - 3, 4)]
        for i, v in enumerate(dwords):
            m, d = mod_of(v)
            if m:
                print('  +0x%02X dword=0x%08X -> %s+0x%X' % (i * 4, v, short(m), d))
        sys.exit(0)

    # find: 搜 4 字节值的所有出现
    val = int(sys.argv[3], 16)
    pat = struct.pack('<I', val)
    off_sorted = sorted((m[1], m[0], m[2]) for m in maps)
    fstarts = [m[0] for m in off_sorted]
    print('searching value 0x%08X ...' % val)
    pos = 0; found = 0
    while True:
        i = raw.find(pat, pos)
        if i < 0: break
        pos = i + 1; found += 1
        j = bisect.bisect_right(fstarts, i) - 1
        va = -1
        if j >= 0:
            fo, va0, sz = off_sorted[j]
            if fo <= i < fo + sz:
                va = va0 + (i - fo)
        print('  file@0x%08X va=%s' % (i, ('0x%08X' % va) if va >= 0 else '??'))
        if found >= NARG:
            print('  ...(capped at %d)' % NARG); break
    print('total=%d' % found)
    sys.exit(0)

# ---------------- scan: 锚定 combase+0xA1D4E 找崩溃线程 32 位栈 ----------------
if mode == 'scan':
    meminfo = []
    if 16 in streams:
        rva = streams[16][0]
        hdr, ent, nmi = struct.unpack_from('<IIQ', raw, rva)
        p = rva + hdr
        for _ in range(nmi):
            base, ab, ap, _a1, rsz, state, prot, typ, _a2 = \
                struct.unpack_from('<QQIIQIIII', raw, p)
            meminfo.append((base, rsz, state, prot, typ)); p += ent
    maps = make_map(9) + make_map(5)
    mods = parse_modules(4)
    mod_of, va_off = resolver(mods, maps)

    # 关键模块范围（32 位侧）
    rng = {}
    for lo, hi, nm in mods:
        s = short(nm).lower()
        if s in ('combase.dll', 'qcap.dll', 'quartz.dll', 'akvirtualcamera.dll'):
            rng[s] = (lo, hi)

    def inmod(v, name):
        if name not in rng: return False
        lo, hi = rng[name]
        return lo <= v < hi

    print('module ranges: %s' % {k: '0x%X-0x%X' % v for k, v in rng.items()})
    print('scanning %d memory-info regions ...' % len(meminfo))
    cands = []   # (ncb, base, hits)
    for base, rsz, state, prot, typ in meminfo:
        if base >= 0x100000000 or typ != 0x20000 or state != 0x1000 or prot != 4:
            continue
        o = va_off(base)
        if o is None: continue
        take = min(rsz, 0x40000)
        blob = raw[o:o + take]
        hits = walk(blob, base, mod_of)
        if len(hits) < 20: continue
        ncb = sum(1 for h in hits if inmod(h[1], 'combase.dll') and 0xA0000 <= h[3] < 0xB0000)
        nq = sum(1 for h in hits if inmod(h[1], 'qcap.dll'))
        if ncb and nq:
            cands.append((ncb + nq, base, hits, blob))
    print('anchored stack candidates: %d' % len(cands))
    cands.sort(key=lambda c: c[0], reverse=True)
    for score, base, hits, _b in cands[:3]:
        ncb = sum(1 for h in hits if inmod(h[1], 'combase.dll') and 0xA0000 <= h[3] < 0xB0000)
        print('  base=0x%08X hits=%d combase-window=%d qcap=%d' % (
            base, len(hits), ncb,
            sum(1 for h in hits if inmod(h[1], 'qcap.dll'))))
    if cands:
        score, base, hits, blob = cands[0]
        # 以 combase 窗口第一次出现位置为中心打印上下文
        pivot = next(i for i, h in enumerate(hits)
                     if inmod(h[1], 'combase.dll') and 0xA0000 <= h[3] < 0xB0000)
        lo_va = hits[pivot][0]
        print('--- crash window around first combase(A0000-B0000) hit @0x%08X ---' % lo_va)
        i0 = 0
        for i, h in enumerate(hits):
            if h[0] >= lo_va - 0x400:
                i0 = i; break
        for sva, v, nm, d in hits[i0:i0 + 60]:
            mark = ''
            s = short(nm).lower()
            if s in ('qcap.dll', 'quartz.dll', 'akvirtualcamera.dll'): mark = '   <<<'
            print('  [0x%08X] %s+0x%X%s' % (sva, nm, d, mark))
        # 栈上 0x41400000 标记与存活 akvcam 对象
        print('--- marker / live AkVCam objects on this stack ---')
        cnt = 0
        for off in range(0, len(blob) - 3, 4):
            sva = base + off; v = u32(blob, off)
            if v in (0x41400000, 0x4140000C):
                print('  [0x%08X] = 0x%08X  !!! marker' % (sva, v)); cnt += 1
                if cnt > 40: break
    sys.exit(0)

# ---------------- outer（旧行为）----------------
NARG = int(sys.argv[3]) if len(sys.argv) > 3 else 150
mods = parse_modules(4)
maps = make_map(9) + make_map(5)
mod_of, va_off = resolver(mods, maps)
er = streams[6][0]
tid = u32(raw, er); code = u32(raw, er + 8); addr = u64(raw, er + 24)
np = u32(raw, er + 32)
info = [u64(raw, er + 40 + 8 * i) for i in range(min(np, 2))]
mn, md = mod_of(addr)
print('EXCEPTION tid=%d code=0x%08X addr=%s+0x%s' % (
    tid, code, mn or '?', ('%X' % md) if md is not None else '?'))
if code == 0xC0000005 and info:
    print('  fault: %s VA=0x%X %s' % ({0: 'READ', 1: 'WRITE', 8: 'DEP'}.get(info[0], info[0]),
          info[1], 'MAPPED' if va_off(info[1] & 0xFFFFFFFF) is not None else 'NOT MAPPED'))

threads = {}
if 3 in streams:
    rva = streams[3][0]
    n = u32(raw, rva); p = rva + 4
    for _ in range(n):
        threads[u32(raw, p)] = (u64(raw, p + 24), u32(raw, p + 32), u32(raw, p + 36))
        p += 48
st_va, st_rva, st_sz = threads.get(tid, (0, 0, 0))
if not st_sz:
    st_va = u64(raw, er + 160); st_rva, st_sz = u32(raw, er + 164), u32(raw, er + 168)
hits = walk(raw[st_rva:st_rva + st_sz], st_va - st_sz, mod_of)
print('--- outer stack newest %d (old -> new) ---' % NARG)
for sva, v, nm, d in hits[-NARG:]:
    print('  [0x%08X] %s+0x%X' % (sva, nm, d))
