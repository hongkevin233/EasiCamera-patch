# -*- coding: utf-8 -*-
# 在 full dump 中定位崩溃时正在实例化的 DirectShow 设备：
# 1) 解析目录/模块/Memory64List/线程表（手工解析，绕开 minidump 库 API 陷阱）
# 2) 全内存搜设备 GUID 字节 + moniker/FriendlyName UTF-16 字符串
# 3) 重点扫崩溃线程栈：GUID 上下文 + 0x41400000 垃圾指针踪迹
# 4) 检查 0x41400000 是否有映射及其内容
import sys, struct

path = sys.argv[1]
raw = open(path, 'rb').read()

# ---------- 目录 ----------
n_streams = struct.unpack_from('<I', raw, 8)[0]
dir_rva = struct.unpack_from('<I', raw, 12)[0]
streams = {}
for i in range(n_streams):
    off = dir_rva + i * 12
    stype, dsz, rva = struct.unpack_from('<III', raw, off)
    if stype:
        streams[stype] = (rva, dsz)

# ---------- 模块表 (stream 4) ----------
mods = []
rva, _ = streams[4]
n = struct.unpack_from('<I', raw, rva)[0]
p = rva + 4
for i in range(n):
    base = struct.unpack_from('<Q', raw, p)[0]
    msize = struct.unpack_from('<I', raw, p + 8)[0]
    nameRva = struct.unpack_from('<I', raw, p + 20)[0]
    nlen = struct.unpack_from('<I', raw, nameRva)[0]
    name = raw[nameRva + 4:nameRva + 4 + nlen].decode('utf-16-le', 'ignore')
    mods.append((base, base + msize, name))
    p += 108

def mod_of(va):
    for lo, hi, name in mods:
        if lo <= va < hi:
            return name, va - lo
    return None, None

# ---------- 内存范围 (优先 Memory64List=9, 否则 MemoryList=5) ----------
ranges = []  # (va, fileRva, size)
if 9 in streams:
    rva, _ = streams[9]
    n = struct.unpack_from('<Q', raw, rva)[0]
    cur = struct.unpack_from('<Q', raw, rva + 8)[0]
    p = rva + 16
    for i in range(n):
        va, sz = struct.unpack_from('<QQ', raw, p)
        ranges.append((va, cur, sz))
        cur += sz
        p += 16
elif 5 in streams:
    rva, _ = streams[5]
    n = struct.unpack_from('<I', raw, rva)[0]
    p = rva + 4
    for i in range(n):
        va, r, sz = struct.unpack_from('<III', raw, p)
        ranges.append((va, r, sz))
        p += 16

print('mem ranges: %d, modules: %d' % (len(ranges), len(mods)))

def va_off(va):
    for mva, r, sz in ranges:
        if mva <= va < mva + sz:
            return r + (va - mva)
    return None

# ---------- 线程表 (stream 3) ----------
threads = []  # (tid, stackVa, stackRva, stackSz)
rva, _ = streams[3]
n = struct.unpack_from('<I', raw, rva)[0]
p = rva + 4
for i in range(n):
    tid, susp, pcls, pri = struct.unpack_from('<4I', raw, p)
    teb = struct.unpack_from('<Q', raw, p + 16)[0]
    st_va = struct.unpack_from('<Q', raw, p + 24)[0]
    st_rva, st_sz = struct.unpack_from('<II', raw, p + 32)
    threads.append((tid, st_va, st_rva, st_sz))
    p += 48

print('threads: %d' % len(threads))

# ---------- 目标证据 ----------
GUIDS = {
    'AMD(99621C9D)': bytes.fromhex('9d1c6299667c704b86d1e0ce7a8d7463'),
    'OBS(A3FCE0F5)': bytes.fromhex('f5e0fca393349f41958aaba1250ec20b'),
    'AKV(DC2C1D65)': bytes.fromhex('651d2cdc6cbc08a2be42f4f40227f24a'),
    'CAT(860BB310)': bytes.fromhex('10b30b86015dd011bd3b00a0c911ce86'),
}
STRS = {
    '@device:sw:': '@device:sw:'.encode('utf-16-le'),
    '@device:pnp:': '@device:pnp:'.encode('utf-16-le'),
    'AMD Privacy View': 'AMD Privacy View'.encode('utf-16-le'),
    'OBS Virtual Camera': 'OBS Virtual Camera'.encode('utf-16-le'),
    'EASI-Bridge': 'EASI-Bridge'.encode('utf-16-le'),
    'AkVCamVideoDevice': 'AkVCamVideoDevice'.encode('utf-16-le'),
}

def find_all(pat, limit=200):
    hits, pos = [], 0
    while len(hits) < limit:
        idx = raw.find(pat, pos)
        if idx < 0:
            break
        hits.append(idx)
        pos = idx + 1
    return hits

def off_desc(off):
    va = None
    for mva, r, sz in ranges:
        if r <= off < r + sz:
            va = mva + (off - r)
            break
    if va is None:
        return 'file_off=0x%X (no VA)' % off
    mname, delta = mod_of(va)
    seg = 'heap/data'
    for tid, st_va, st_rva, st_sz in threads:
        if st_va - st_sz <= va < st_va:  # stack grows down: start=high
            seg = 'stack(tid=%d)' % tid
    if mname:
        return 'VA=0x%08X %s+0x%X' % (va, mname, delta)
    return 'VA=0x%08X %s' % (va, seg)

print('\n===== 全内存 GUID 命中 =====')
for gname, gpat in GUIDS.items():
    hits = find_all(gpat, 60)
    print('%s : %d hits' % (gname, len(hits)))
    for h in hits[:20]:
        print('   ', off_desc(h))

print('\n===== 全内存 字符串命中 =====')
for sname, spat in STRS.items():
    hits = find_all(spat, 40)
    print('%s : %d hits' % (sname, len(hits)))
    for h in hits[:15]:
        blob = raw[h:h + 160].decode('utf-16-le', 'ignore')
        # 截断到不可打印
        out = ''
        for ch in blob:
            if ch == '\x00' or ord(ch) < 0x20:
                break
            out += ch
        print('   %s -> "%s"' % (off_desc(h), out[:70]))

# ---------- 崩溃线程栈深扫 ----------
CRASH_TID = None
try:
    CRASH_TID = int(sys.argv[2])
except IndexError:
    pass

if CRASH_TID:
    for tid, st_va, st_rva, st_sz in threads:
        if tid != CRASH_TID:
            continue
        lo, hi = st_va - st_sz, st_va
        print('\n===== 崩溃线程 %d 栈 [0x%X-0x%X] size=0x%X =====' % (tid, lo, hi, st_sz))
        stack = raw[st_rva:st_rva + st_sz]
        for gname, gpat in GUIDS.items():
            pos = 0
            found = []
            while True:
                idx = stack.find(gpat, pos)
                if idx < 0:
                    break
                found.append(lo + idx)
                pos = idx + 1
            if found:
                print('  GUID %s @ %s' % (gname, ', '.join('0x%08X' % x for x in found)))
        # 垃圾指针 0x41400000 踪迹
        pat = struct.pack('<I', 0x41400000)
        pos, cnt = 0, 0
        while cnt < 30:
            idx = stack.find(pat, pos)
            if idx < 0:
                break
            va = lo + idx
            print('  [0x41400000 stored] VA=0x%08X (stack+0x%X)' % (va, idx))
            # 打印前后 5 个槽
            s0 = max(0, idx - 20)
            vals = struct.unpack_from('<10I', stack, s0) if idx + 20 <= len(stack) else ()
            print('     ctx: %s' % ' '.join('%08X' % v for v in vals))
            pos, cnt = idx + 1, cnt + 1

# ---------- 0x41400000 映射检查 ----------
for target in (0x41400000, 0x4140000C):
    off = va_off(target)
    if off is None:
        print('\nVA 0x%08X : NOT MAPPED' % target)
    else:
        blob = raw[off:off + 64]
        print('\nVA 0x%08X : MAPPED, first 64 bytes: %s' % (target, blob.hex()))
        print('   ascii: %r' % blob[:32])
