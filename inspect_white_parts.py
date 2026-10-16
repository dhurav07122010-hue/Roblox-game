import apply_to_place, struct

header, chunks = apply_to_place.unpack_rbxl('Steal An ETC.rbxl')

inst_by_class = {}
for c in chunks:
    if c['name'] == 'INST':
        cdata = c['data']
        cid, = struct.unpack_from('<I', cdata, 0)
        slen, = struct.unpack_from('<I', cdata, 4)
        pos = 8 + slen + 1
        count, = struct.unpack_from('<I', cdata, pos)
        pos += 4
        ref_bytes = cdata[pos:pos+count*4]
        inst_by_class[cid] = apply_to_place.untransform_int_array(ref_bytes, count)

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

print("--- WHITE MODEL (Ref 853) PARTS ---")
for ch, p in parent_of.items():
    if p == 853:
        print(f"Part Ref {ch}: {names.get(ch)}")
