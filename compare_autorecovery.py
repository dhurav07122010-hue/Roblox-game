import apply_to_place, struct

p1 = "Steal An ETC.rbxl"
p2 = r"C:\Users\HP\AppData\Local\Roblox\RobloxStudio\AutoSaves\Steal An ETC_AutoRecovery_0.rbxl"

h1, c1 = apply_to_place.unpack_rbxl(p1)
h2, c2 = apply_to_place.unpack_rbxl(p2)

print(f"p1 chunks: {len(c1)}, p2 chunks: {len(c2)}")

# Let's inspect names in p2 that were not in p1
def get_names(chunks):
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
    return names

n1 = get_names(c1)
n2 = get_names(c2)

print(f"Total instances in p1: {len(n1)}, in p2: {len(n2)}")
diff = set(n2.values()) - set(n1.values())
print(f"Names unique to p2: {diff}")
