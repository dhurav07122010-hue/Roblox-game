import apply_to_place, struct

header, chunks = apply_to_place.unpack_rbxl('Steal An ETC.rbxl')

inst_by_class = {}
class_names = {}
for c in chunks:
    if c['name'] == 'INST':
        cdata = c['data']
        cid, = struct.unpack_from('<I', cdata, 0)
        slen, = struct.unpack_from('<I', cdata, 4)
        cname = cdata[8:8+slen].decode('latin1')
        pos = 8 + slen + 1
        count, = struct.unpack_from('<I', cdata, pos)
        pos += 4
        ref_bytes = cdata[pos:pos+count*4]
        inst_by_class[cid] = apply_to_place.untransform_int_array(ref_bytes, count)
        for r in inst_by_class[cid]:
            class_names[r] = cname

names = {}
sources = {}
for c in chunks:
    if c['name'] == 'PROP':
        cdata = c['data']
        cid, = struct.unpack_from('<I', cdata, 0)
        slen, = struct.unpack_from('<I', cdata, 4)
        pos = 8
        pname = cdata[pos:pos+slen].decode('utf-8', errors='replace')
        pos += slen
        ptype = cdata[pos]
        pos += 1
        refs = inst_by_class.get(cid, [])
        if pname == 'Name' and ptype == 1:
            p = pos
            for r in refs:
                s_len, = struct.unpack_from('<I', cdata, p)
                p += 4
                names[r] = cdata[p:p+s_len].decode('utf-8', errors='replace')
                p += s_len
        elif pname == 'Source' and ptype == 1:
            p = pos
            for r in refs:
                s_len, = struct.unpack_from('<I', cdata, p)
                p += 4
                sources[r] = s_len
                p += s_len

parent_of = {}
for c in chunks:
    if c['name'] == 'PRNT':
        cdata = c['data']
        ver = cdata[0]
        count, = struct.unpack_from('<I', cdata, 1)
        children = apply_to_place.untransform_int_array(cdata[5 : 5 + count*4], count)
        parents = apply_to_place.untransform_int_array(cdata[5 + count*4 : 5 + count*8], count)
        for ch, p in zip(children, parents):
            parent_of[ch] = p

print("=== VERIFYING Steal An ETC.rbxl ===")
egg_spawns = [r for r, n in names.items() if n == "egg spawn"]
print(f"Total 'egg spawn' parts found: {len(egg_spawns)}")
for r in egg_spawns:
    print(f"  - egg spawn (Ref {r}) under parent {names.get(parent_of.get(r))}")

for n_target in ['PlayerData', 'GameplayManager', 'StatsHUDController', 'DayNightCycle', 'NarutoEggGenerator']:
    r = next((k for k, v in names.items() if v == n_target), None)
    print(f"Script {n_target} (Ref {r}): Class={class_names.get(r)}, SourceLen={sources.get(r)}")
