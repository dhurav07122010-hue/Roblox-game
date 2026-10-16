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

# Let's inspect the position of the 5 egg spawn parts
# Part cid is 65
part_refs = inst_by_class.get(65, [])
egg_spawns = [r for r, n in names.items() if n == "egg spawn"]

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
        if cid == 65 and pname == 'size':
            # read sizes
            p = pos
            # ptype 14: count x 3 floats
            # In roblox binary format, Vector3 is 3 float arrays: all Xs, all Ys, all Zs!
            count = len(part_refs)
            xs = struct.unpack_from(f'<{count}f', cdata, p)
            ys = struct.unpack_from(f'<{count}f', cdata, p + count*4)
            zs = struct.unpack_from(f'<{count}f', cdata, p + count*8)
            for r in egg_spawns:
                idx = part_refs.index(r)
                print(f"egg spawn Ref {r} ({names.get(parent_of.get(r))}): Size = ({xs[idx]:.1f}, {ys[idx]:.1f}, {zs[idx]:.1f})")
