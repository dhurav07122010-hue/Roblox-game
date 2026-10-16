import os
import struct
import shutil
import zstandard as zstd
import apply_to_place

def dynamic_apply(target_file):
    print(f"=== Applying updates dynamically to {target_file} ===")
    header, chunks = apply_to_place.unpack_rbxl(target_file)

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

    # Find target refs
    player_data_ref = next((r for r, n in names.items() if n == 'PlayerData' and class_names.get(r) == 'Script'), None)
    gameplay_mgr_ref = next((r for r, n in names.items() if n == 'GameplayManager' and class_names.get(r) == 'Script'), None)
    stats_hud_ref = next((r for r, n in names.items() if n == 'StatsHUDController' and class_names.get(r) == 'LocalScript'), None)

    print(f"Found refs: PlayerData={player_data_ref}, GameplayManager={gameplay_mgr_ref}, StatsHUDController={stats_hud_ref}")
    if not (player_data_ref and gameplay_mgr_ref and stats_hud_ref):
        raise ValueError(f"Could not find all script refs in {target_file}")

    with open("PlayerData.server.luau", "r", encoding="utf-8") as f:
        player_data_src = f.read().encode("utf-8")
    with open("GameplayManager.server.luau", "r", encoding="utf-8") as f:
        gameplay_mgr_src = f.read().encode("utf-8")
    with open("StatsHUDController.client.luau", "r", encoding="utf-8") as f:
        stats_hud_src = f.read().encode("utf-8")

    target_sources = {
        player_data_ref: player_data_src,
        gameplay_mgr_ref: gameplay_mgr_src,
        stats_hud_ref: stats_hud_src,
    }

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
            if pname == 'Source' and ptype == 1:
                sources = {}
                p = pos
                for r in refs:
                    s_len, = struct.unpack_from('<I', cdata, p)
                    p += 4
                    sources[r] = cdata[p:p+s_len]
                    p += s_len

                modified = False
                for r, new_src in target_sources.items():
                    if r in refs:
                        sources[r] = new_src
                        modified = True
                        print(f"PROP: Updated Source for Ref {r} ({names.get(r)}) -> {len(new_src)} bytes")

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

    apply_to_place.pack_rbxl(header, chunks, target_file)
    print(f"Successfully updated {target_file}!\n")

if __name__ == '__main__':
    target = "Steal An ETC.rbxl"
    dynamic_apply(target)
    print("Updated Steal An ETC.rbxl successfully!")
