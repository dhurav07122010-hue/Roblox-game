import apply_to_place, struct

p2 = r"C:\Users\HP\AppData\Local\Roblox\RobloxStudio\AutoSaves\Steal An ETC_AutoRecovery_0.rbxl"
h2, chunks = apply_to_place.unpack_rbxl(p2)

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
parent_of = {}
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
    elif c['name'] == 'PRNT':
        cdata = c['data']
        ver = cdata[0]
        count, = struct.unpack_from('<I', cdata, 1)
        children = apply_to_place.untransform_int_array(cdata[5 : 5 + count*4], count)
        parents = apply_to_place.untransform_int_array(cdata[5 + count*4 : 5 + count*8], count)
        for ch, p in zip(children, parents):
            parent_of[ch] = p

sizes = {}
positions = {}
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
        if pname == 'size' and ptype == 14:
            p = pos
            for r in refs:
                x, y, z = struct.unpack_from('<fff', cdata, p)
                p += 12
                sizes[r] = (x, y, z)
        elif pname == 'CFrame' and ptype == 16:
            # rbxl binary CFrame: rot type byte, then pos (3 floats)
            p = pos
            for r in refs:
                rot_type = cdata[p]
                p += 1
                if rot_type == 0:
                    # 9 floats rotation + 3 floats pos
                    rot = struct.unpack_from('<9f', cdata, p)
                    p += 36
                # 3 floats pos
                px, py, pz = struct.unpack_from('<fff', cdata, p)
                p += 12
                positions[r] = (px, py, pz)

for r, n in names.items():
    if n == 'egg spawn':
        p_name = names.get(parent_of.get(r), 'None')
        s = sizes.get(r, (0, 0, 0))
        pos = positions.get(r, (0, 0, 0))
        print(f"{p_name} -> egg spawn: Size=({s[0]:.1f}, {s[1]:.1f}, {s[2]:.1f}), Pos=({pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f})")
