#!/usr/bin/env python3
"""Resources/icon.svg → Resources/AppIcon.icns, docs/icon.png
아이콘을 바꾸고 싶으면 icon.svg를 고친 뒤:  pip install cairosvg && python3 scripts/make-icon.py"""
import struct, pathlib, cairosvg
root = pathlib.Path(__file__).resolve().parent.parent
svg = (root / "Resources/icon.svg").read_bytes()
entries = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512),
           ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
cache, body = {}, b""
for tag, size in entries:
    if size not in cache:
        cache[size] = cairosvg.svg2png(bytestring=svg, output_width=size, output_height=size)
    body += tag.encode() + struct.pack(">I", len(cache[size]) + 8) + cache[size]
(root / "Resources/AppIcon.icns").write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
(root / "docs/icon.png").write_bytes(cache[256])
print("✅ Resources/AppIcon.icns, docs/icon.png")
