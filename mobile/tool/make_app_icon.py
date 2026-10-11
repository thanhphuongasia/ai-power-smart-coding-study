"""Sinh app icon tạm cho iOS (TestFlight).

Chạy từ thư mục mobile/:  python3 tool/make_app_icon.py

- Chỉ dùng thư viện chuẩn (zlib, struct, json, subprocess).
- Render 1024x1024 RGB (không alpha) rồi dùng sips (macOS) để resize ra các size
  đã khai trong AppIcon.appiconset/Contents.json.
"""

import json
import math
import os
import struct
import subprocess
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
MOBILE = os.path.dirname(HERE)
ICONSET = os.path.join(MOBILE, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
CONTENTS = os.path.join(ICONSET, "Contents.json")

SIZE = 1024
BG = (0x15, 0x17, 0x1C)
ACCENT = (0x5D, 0xCA, 0xA5)
STROKE_R = 32.0  # stroke width 64 px

# Các đoạn của biểu tượng </>, toạ độ theo pixel trên canvas 1024.
SEGMENTS = [
    # chevron trái <
    ((330.0, 360.0), (190.0, 512.0)),
    ((190.0, 512.0), (330.0, 664.0)),
    # dấu /
    ((568.0, 350.0), (456.0, 674.0)),
    # chevron phải >
    ((694.0, 360.0), (834.0, 512.0)),
    ((834.0, 512.0), (694.0, 664.0)),
]


def _prep(seg):
    (ax, ay), (bx, by) = seg
    vx, vy = bx - ax, by - ay
    return ax, ay, vx, vy, 1.0 / (vx * vx + vy * vy)


PREPPED = [_prep(s) for s in SEGMENTS]


def render_rgb():
    """Trả về bytes RGB (3 byte/pixel), không alpha."""
    out = bytearray(SIZE * SIZE * 3)
    bg_r, bg_g, bg_b = BG
    ac_r, ac_g, ac_b = ACCENT
    idx = 0
    for y in range(SIZE):
        py = y + 0.5
        for x in range(SIZE):
            px = x + 0.5
            best = 1e9
            for ax, ay, vx, vy, inv_len2 in PREPPED:
                wx, wy = px - ax, py - ay
                t = (wx * vx + wy * vy) * inv_len2
                if t < 0.0:
                    t = 0.0
                elif t > 1.0:
                    t = 1.0
                dx = wx - t * vx
                dy = wy - t * vy
                d = math.sqrt(dx * dx + dy * dy)
                if d < best:
                    best = d
            # anti-alias: coverage 1 trong nét, giảm dần trong 1px viền
            cov = STROKE_R + 0.5 - best
            if cov <= 0.0:
                a = 0.0
            elif cov >= 1.0:
                a = 1.0
            else:
                a = cov
            out[idx] = int(bg_r + (ac_r - bg_r) * a + 0.5)
            out[idx + 1] = int(bg_g + (ac_g - bg_g) * a + 0.5)
            out[idx + 2] = int(bg_b + (ac_b - bg_b) * a + 0.5)
            idx += 3
    return bytes(out)


def write_png_rgb(path, width, height, rgb):
    """PNG color type 2 (RGB, 8-bit), không có alpha."""

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    stride = width * 3
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type None
        raw += rgb[y * stride:(y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def target_files():
    """Map filename -> pixel size, lấy từ Contents.json (không sửa file này)."""
    with open(CONTENTS, encoding="utf-8") as f:
        images = json.load(f)["images"]
    targets = {}
    for img in images:
        pt = float(img["size"].split("x")[0])
        scale = float(img["scale"].rstrip("x"))
        px = int(round(pt * scale))
        targets[img["filename"]] = px
    return targets


def main():
    master = os.path.join(ICONSET, "Icon-App-1024x1024@1x.png")
    print("render 1024x1024 ...", flush=True)
    write_png_rgb(master, SIZE, SIZE, render_rgb())
    print("wrote", master, flush=True)

    for name, px in sorted(target_files().items()):
        if name == "Icon-App-1024x1024@1x.png":
            continue
        dst = os.path.join(ICONSET, name)
        subprocess.run(["sips", "-z", str(px), str(px), master, "--out", dst],
                       check=True, stdout=subprocess.DEVNULL)
        print("resized", name, px, flush=True)


if __name__ == "__main__":
    main()
