"""
Roblox Place Sync Utility (Hardened & Safe)
Syncs Luau script files in `src/` to and from `+1 speed simulator.rbxl`.
Protects pristine backups and matches scripts strictly by Name.
"""

import os
import sys
import shutil
import struct
import datetime
import zstandard as zstd

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PLACE_FILE = os.path.join(BASE_DIR, "+1 speed simulator.rbxl")
PRISTINE_BACKUP = os.path.join(BASE_DIR, "+1 speed simulator.pristine.bak")
BACKUP_DIR = os.path.join(BASE_DIR, "backups")
SRC_DIR = os.path.join(BASE_DIR, "src")

SERVER_SCRIPT = os.path.join(SRC_DIR, "server", "GameManager.server.luau")
CLIENT_SCRIPT = os.path.join(SRC_DIR, "client", "SpeedHUD.client.luau")

def unpack_rbxl(filepath):
    with open(filepath, "rb") as f:
        data = f.read()
    
    header = data[:32]
    dctx = zstd.ZstdDecompressor()
    offset = 32
    chunks = []
    
    while offset < len(data):
        chunk_name = data[offset:offset+4].decode('latin1', errors='replace')
        comp_len, decomp_len, reserved = struct.unpack("<III", data[offset+4:offset+16])
        offset += 16
        chunk_data = data[offset:offset+comp_len if comp_len > 0 else offset+decomp_len]
        offset += comp_len if comp_len > 0 else decomp_len
        if comp_len > 0:
            decomp = dctx.decompress(chunk_data, max_output_size=decomp_len)
        else:
            decomp = chunk_data
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

def read_string(buf, pos):
    slen, = struct.unpack_from("<I", buf, pos)
    pos += 4
    s = buf[pos:pos+slen].decode('utf-8', errors='replace')
    pos += slen
    return s, pos

def map_types_and_names(chunks):
    types = {}
    for c in chunks:
        if c["name"] == "INST":
            pos = 0
            tid, = struct.unpack_from("<I", c["data"], pos)
            pos += 4
            cname, _ = read_string(c["data"], pos)
            types[tid] = cname

    names = {}
    for c in chunks:
        if c["name"] == "PROP":
            pos = 0
            tid, = struct.unpack_from("<I", c["data"], pos)
            pos += 4
            pname, pos = read_string(c["data"], pos)
            ptype = c["data"][pos]
            pos += 1
            if pname == "Name" and ptype == 1:
                slen, = struct.unpack_from("<I", c["data"], pos)
                sname = c["data"][pos+4:pos+4+slen].decode('utf-8', errors='replace')
                names[tid] = sname

    return types, names

def extract_scripts():
    header, chunks = unpack_rbxl(PLACE_FILE)
    types, names = map_types_and_names(chunks)
            
    os.makedirs(os.path.dirname(SERVER_SCRIPT), exist_ok=True)
    os.makedirs(os.path.dirname(CLIENT_SCRIPT), exist_ok=True)
    
    for c in chunks:
        if c["name"] == "PROP":
            pos = 0
            tid, = struct.unpack_from("<I", c["data"], pos)
            pos += 4
            pname, pos = read_string(c["data"], pos)
            ptype = c["data"][pos]
            pos += 1
            inst_name = names.get(tid, "")
            if pname == "Source" and ptype == 1:
                slen, = struct.unpack_from("<I", c["data"], pos)
                pos += 4
                source = c["data"][pos:pos+slen].decode('utf-8', errors='replace')
                if inst_name == "GameManager":
                    with open(SERVER_SCRIPT, "w", encoding="utf-8") as f:
                        f.write(source)
                    print(f"Extracted GameManager -> {SERVER_SCRIPT}")
                elif inst_name == "SpeedHUD":
                    with open(CLIENT_SCRIPT, "w", encoding="utf-8") as f:
                        f.write(source)
                    print(f"Extracted SpeedHUD -> {CLIENT_SCRIPT}")

def sync_to_rbxl(target_path=None):
    if target_path is None:
        target_path = PLACE_FILE
    elif not os.path.isabs(target_path):
        target_path = os.path.join(BASE_DIR, target_path)

    is_test_run = (os.path.abspath(target_path) != os.path.abspath(PLACE_FILE))
    if is_test_run:
        print(f"[TEST RUN] Targeting custom place file: {target_path}")
        print(f"[TEST RUN] Main place file '{PLACE_FILE}' is protected and will NOT be touched.")

    header, chunks = unpack_rbxl(target_path)
    types, names = map_types_and_names(chunks)

    with open(SERVER_SCRIPT, "r", encoding="utf-8") as f:
        server_source = f.read().encode('utf-8')
    with open(CLIENT_SCRIPT, "r", encoding="utf-8") as f:
        client_source = f.read().encode('utf-8')

    modified = False
    for c in chunks:
        if c["name"] == "PROP":
            pos = 0
            tid, = struct.unpack_from("<I", c["data"], pos)
            pos += 4
            pname, pos = read_string(c["data"], pos)
            ptype = c["data"][pos]
            pos += 1
            inst_name = names.get(tid, "")
            
            if pname == "Source" and ptype == 1:
                new_src = None
                if inst_name == "GameManager":
                    new_src = server_source
                elif inst_name == "SpeedHUD":
                    new_src = client_source
                
                if new_src is not None:
                    new_prop_data = bytearray()
                    new_prop_data += struct.pack("<I", tid)
                    pname_bytes = pname.encode('utf-8')
                    new_prop_data += struct.pack("<I", len(pname_bytes)) + pname_bytes
                    new_prop_data += bytes([ptype])
                    new_prop_data += struct.pack("<I", len(new_src)) + new_src
                    c["data"] = bytes(new_prop_data)
                    modified = True
                    print(f"Updated '{inst_name}' source ({len(new_src)} bytes)")

    if modified:
        if not is_test_run:
            # Guarantee pristine backup is never overwritten
            if not os.path.exists(PRISTINE_BACKUP):
                shutil.copy2(PLACE_FILE, PRISTINE_BACKUP)
                print(f"Permanent pristine backup preserved at: {PRISTINE_BACKUP}")
                
            # Create timestamped backup for main file
            os.makedirs(BACKUP_DIR, exist_ok=True)
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            ts_backup = os.path.join(BACKUP_DIR, f"+1 speed simulator_{timestamp}.rbxl")
            shutil.copy2(PLACE_FILE, ts_backup)
            print(f"Timestamped backup archived at: {ts_backup}")
        
        # Write to target place file
        pack_rbxl(header, chunks, target_path)
        print(f"Successfully synced scripts to {target_path}")

if __name__ == "__main__":
    args = sys.argv[1:]
    command = "sync" if not args else args[0]
    target = None

    if "--target" in args:
        t_idx = args.index("--target")
        if t_idx + 1 < len(args):
            target = args[t_idx + 1]
    elif len(args) > 1 and not args[1].startswith("--"):
        target = args[1]

    if command == "extract":
        extract_scripts()
    elif command == "sync":
        sync_to_rbxl(target)
    else:
        if not os.path.exists(SRC_DIR):
            extract_scripts()
        else:
            sync_to_rbxl(target)
