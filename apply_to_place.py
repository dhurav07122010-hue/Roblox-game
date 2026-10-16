import os
import struct
import shutil
import zstandard as zstd

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

def transform_int_array(ints):
    count = len(ints)
    deltas = []
    prev = 0
    for v in ints:
        deltas.append(v - prev)
        prev = v
    zigzags = []
    for d in deltas:
        if d >= 0:
            zig = d * 2
        else:
            zig = (-d) * 2 - 1
        zigzags.append(zig)
    b0 = bytearray(count)
    b1 = bytearray(count)
    b2 = bytearray(count)
    b3 = bytearray(count)
    for i, z in enumerate(zigzags):
        b0[i] = (z >> 24) & 0xFF
        b1[i] = (z >> 16) & 0xFF
        b2[i] = (z >> 8) & 0xFF
        b3[i] = z & 0xFF
    return bytes(b0 + b1 + b2 + b3)

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

def pack_rbxl(header, chunks, out_path):
    cctx = zstd.ZstdCompressor()
    out = bytearray(header)
    for c in chunks:
        name_bytes = c["name"].encode('latin1')
        decomp_data = c["data"]
        decomp_len = len(decomp_data)
        if c["name"].startswith("END"):
            comp_len = 0
            out += name_bytes
            out += struct.pack("<III", comp_len, decomp_len, c["reserved"])
            out += decomp_data
        else:
            comp_data = cctx.compress(decomp_data)
            comp_len = len(comp_data)
            out += name_bytes
            out += struct.pack("<III", comp_len, decomp_len, c["reserved"])
            out += comp_data
    temp_path = out_path + ".tmp"
    with open(temp_path, "wb") as f:
        f.write(out)
    shutil.move(temp_path, out_path)

def apply_updates():
    PLACE_FILE = "Steal An ETC.rbxl"

    header, chunks = unpack_rbxl(PLACE_FILE)

    # 1. Map INST
    inst_by_class = {}
    class_names = {}
    for c in chunks:
        if c["name"] == "INST":
            cdata = c["data"]
            cid, = struct.unpack_from("<I", cdata, 0)
            slen, = struct.unpack_from("<I", cdata, 4)
            class_names[cid] = cdata[8:8+slen].decode('latin1')
            pos = 8 + slen + 1
            count, = struct.unpack_from("<I", cdata, pos)
            pos += 4
            ref_bytes = cdata[pos:pos+count*4]
            inst_by_class[cid] = untransform_int_array(ref_bytes, count)

    # 2. Modify PRNT
    # Ensure:
    #   Ref 6484 (NarutoEggGenerator) -> parent 6448 (ServerStorage)
    #   Ref 6443 (PlayerData) -> parent 6441 (ServerScriptService)
    #   Ref 6444 (DayNightCycle) -> parent 6441 (ServerScriptService)
    #   Ref 6447 (GameplayManager) -> parent 6441 (ServerScriptService)
    #   Ref 6195 (StatsHUDController) -> parent 6194 (StarterPlayerScripts)
    parent_map = {
        6484: 6448,
        6443: 6441,
        6444: 6441,
        6447: 6441,
        6195: 6194,
    }

    for c in chunks:
        if c["name"] == "PRNT":
            cdata = c["data"]
            ver = cdata[0]
            count, = struct.unpack_from("<I", cdata, 1)
            children = untransform_int_array(cdata[5 : 5 + count*4], count)
            parents = untransform_int_array(cdata[5 + count*4 : 5 + count*8], count)
            
            for child_ref, target_parent in parent_map.items():
                if child_ref in children:
                    idx = children.index(child_ref)
                    print(f"PRNT: Child {child_ref} parent set from {parents[idx]} -> {target_parent}")
                    parents[idx] = target_parent
            
            new_cdata = bytes([ver]) + struct.pack("<I", count) + transform_int_array(children) + transform_int_array(parents)
            c["data"] = new_cdata

    # Load source files
    with open("PlayerData.server.luau", "r", encoding="utf-8") as f:
        player_data_src = f.read().encode("utf-8")

    with open("GameplayManager.server.luau", "r", encoding="utf-8") as f:
        gameplay_mgr_src = f.read().encode("utf-8")

    with open("StatsHUDController.client.luau", "r", encoding="utf-8") as f:
        stats_hud_src = f.read().encode("utf-8")

    # Name mapping
    target_names = {
        6484: b"NarutoEggGenerator",
        6443: b"PlayerData",
        6444: b"DayNightCycle",
        6447: b"GameplayManager",
        6195: b"StatsHUDController",
    }

    # Source mapping
    target_sources = {
        6443: player_data_src,
        6447: gameplay_mgr_src,
        6195: stats_hud_src,
    }

    # 3. Modify PROP
    for c in chunks:
        if c["name"] == "PROP":
            cdata = c["data"]
            cid, = struct.unpack_from("<I", cdata, 0)
            slen, = struct.unpack_from("<I", cdata, 4)
            pos = 8
            pname = cdata[pos:pos+slen].decode('utf-8', errors='replace')
            pos += slen
            ptype = cdata[pos]
            pos += 1
            refs = inst_by_class.get(cid, [])
            
            if pname == "Name" and ptype == 1:
                names = {}
                p = pos
                for r in refs:
                    s_len, = struct.unpack_from("<I", cdata, p)
                    p += 4
                    names[r] = cdata[p:p+s_len]
                    p += s_len
                
                modified = False
                for r, new_name in target_names.items():
                    if r in refs:
                        names[r] = new_name
                        modified = True
                        print(f"PROP: Set Name for Ref {r} -> {new_name.decode('latin1')}")
                
                if modified:
                    new_prop_data = bytearray()
                    new_prop_data += struct.pack("<I", cid)
                    pname_bytes = b"Name"
                    new_prop_data += struct.pack("<I", len(pname_bytes)) + pname_bytes
                    new_prop_data += bytes([ptype])
                    for r in refs:
                        s_bytes = names[r]
                        new_prop_data += struct.pack("<I", len(s_bytes)) + s_bytes
                    c["data"] = bytes(new_prop_data)
                    
            elif pname == "Source" and ptype == 1:
                sources = {}
                p = pos
                for r in refs:
                    s_len, = struct.unpack_from("<I", cdata, p)
                    p += 4
                    sources[r] = cdata[p:p+s_len]
                    p += s_len
                
                modified = False
                for r, new_src in target_sources.items():
                    if r in refs:
                        sources[r] = new_src
                        modified = True
                        print(f"PROP: Set Source for Ref {r} -> {len(new_src)} bytes")
                    
                if modified:
                    new_prop_data = bytearray()
                    new_prop_data += struct.pack("<I", cid)
                    pname_bytes = b"Source"
                    new_prop_data += struct.pack("<I", len(pname_bytes)) + pname_bytes
                    new_prop_data += bytes([ptype])
                    for r in refs:
                        s_bytes = sources[r]
                        new_prop_data += struct.pack("<I", len(s_bytes)) + s_bytes
                    c["data"] = bytes(new_prop_data)

    pack_rbxl(header, chunks, PLACE_FILE)
    print(f"Successfully packed clean updates into {PLACE_FILE}!")

if __name__ == "__main__":
    apply_updates()
