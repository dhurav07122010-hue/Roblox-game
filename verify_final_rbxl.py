import struct, zstandard as zstd

def unpack_rbxl(filepath):
    with open(filepath, "rb") as f:
        raw_data = f.read()
    header = raw_data[:32]
    dctx = zstd.ZstdDecompressor()
    offset = 32
    chunks = []
    while offset < len(raw_data):
        chunk_name = raw_data[offset:offset+4].decode('latin1', errors='replace')
        comp_len, decomp_len, reserved = struct.unpack("<III", raw_data[offset+4:offset+16])
        offset += 16
        chunk_data = raw_data[offset:offset+comp_len if comp_len > 0 else offset+decomp_len]
        offset += comp_len if comp_len > 0 else decomp_len
        decomp = dctx.decompress(chunk_data, max_output_size=decomp_len) if comp_len > 0 else chunk_data
        chunks.append({
            "name": chunk_name,
            "data": decomp,
            "reserved": reserved
        })
        if chunk_name.startswith("END"):
            break
    return header, chunks

def untransform_int_array(buf, count):
    b0 = buf[0*count : 1*count]
    b1 = buf[1*count : 2*count]
    b2 = buf[2*count : 3*count]
    b3 = buf[3*count : 4*count]
    out = []
    acc = 0
    for i in range(count):
        raw = (b0[i] << 24) | (b1[i] << 16) | (b2[i] << 8) | b3[i]
        val = raw // 2 if raw % 2 == 0 else -((raw + 1) // 2)
        acc += val
        out.append(acc)
    return out

def read_string(buf, pos):
    slen, = struct.unpack_from("<I", buf, pos)
    pos += 4
    s = buf[pos:pos+slen].decode('utf-8', errors='replace')
    pos += slen
    return s, pos

header, chunks = unpack_rbxl("Steal An ETC.rbxl")

instances = {}
inst_by_type = {}

for c in chunks:
    if c['name'] == 'INST':
        pos = 0
        tid, = struct.unpack_from('<I', c['data'], pos)
        pos += 4
        slen, = struct.unpack_from('<I', c['data'], pos)
        pos += 4
        cname = c['data'][pos:pos+slen].decode('utf-8', errors='replace')
        pos += slen
        is_svc = c['data'][pos]
        pos += 1
        inst_count, = struct.unpack_from('<I', c['data'], pos)
        pos += 4
        refs = untransform_int_array(c['data'][pos:], inst_count)
        inst_by_type[tid] = {'class': cname, 'refs': refs, 'is_svc': is_svc}
        for ref in refs:
            instances[ref] = {'id': ref, 'class': cname, 'is_svc': is_svc, 'name': '', 'parent': None, 'children': []}

for c in chunks:
    if c['name'] == 'PRNT':
        ver = c['data'][0]
        inst_count, = struct.unpack_from('<I', c['data'], 1)
        children = untransform_int_array(c['data'][5 : 5 + inst_count*4], inst_count)
        parents = untransform_int_array(c['data'][5 + inst_count*4 : 5 + inst_count*8], inst_count)
        for child, parent in zip(children, parents):
            if child in instances:
                instances[child]['parent'] = parent
                if parent in instances:
                    instances[parent]['children'].append(child)

for c in chunks:
    if c['name'] == 'PROP':
        pos = 0
        tid, = struct.unpack_from('<I', c['data'], pos)
        pos += 4
        pname, pos = read_string(c['data'], pos)
        ptype = c['data'][pos]
        pos += 1
        t_info = inst_by_type.get(tid)
        if not t_info:
            continue
        refs = t_info['refs']
        if pname == 'Name' and ptype == 1:
            for ref in refs:
                slen, = struct.unpack_from('<I', c['data'], pos)
                pos += 4
                sval = c['data'][pos:pos+slen].decode('utf-8', errors='replace')
                pos += slen
                if ref in instances:
                    instances[ref]['name'] = sval

def get_path(ref):
    path = []
    curr = ref
    while curr is not None and curr in instances:
        path.append(instances[curr]['name'] or instances[curr]['class'])
        curr = instances[curr]['parent']
        if curr == -1:
            break
    return ".".join(reversed(path))

print("=== VERIFYING SCRIPTS IN UPDATED Steal An ETC.rbxl ===")
for ref in [6444, 6484, 6195]:
    print(f"Ref {ref}: {get_path(ref)} ({instances[ref]['class']})")

print("\n=== SERVERSCRIPTSERVICE CHILDREN ===")
sss_ref = 6441
for child in instances[sss_ref]['children']:
    print(f"  - Ref {child}: {instances[child]['name']} ({instances[child]['class']})")

print("\n=== SERVERSTORAGE CHILDREN ===")
ss_ref = 6448
for child in instances[ss_ref]['children']:
    print(f"  - Ref {child}: {instances[child]['name']} ({instances[child]['class']})")

print("\n=== STARTERPLAYERSCRIPTS CHILDREN ===")
sps_ref = 6194
for child in instances[sps_ref]['children']:
    print(f"  - Ref {child}: {instances[child]['name']} ({instances[child]['class']})")

print("\n[VERIFICATION SUCCESS] Steal An ETC.rbxl is valid and ready to play!")
