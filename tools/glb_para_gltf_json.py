#!/usr/bin/env python3
"""Converte .glb em glTF JSON com o buffer embutido (data URI). Uso: glb_para_gltf_json.py entrada.glb saida.json"""
import base64, json, struct, sys
src, dst = sys.argv[1], sys.argv[2]
b = open(src, "rb").read()
assert b[:4] == b"glTF", "não é GLB"
off, gltf, binc = 12, None, b""
while off < len(b):
    ln, typ = struct.unpack("<II", b[off:off + 8]); data = b[off + 8: off + 8 + ln]
    if typ == 0x4E4F534A: gltf = json.loads(data)
    elif typ == 0x004E4942: binc = data
    off += 8 + ln
gltf["buffers"][0]["uri"] = "data:application/octet-stream;base64," + base64.b64encode(binc).decode()
json.dump(gltf, open(dst, "w"), separators=(",", ":"))
