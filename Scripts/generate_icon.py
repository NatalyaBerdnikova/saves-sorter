#!/usr/bin/env python3
"""Draw a simple 1024 icon: teal field, cream card, map pin. No third-party marks."""

import struct
import zlib
from pathlib import Path

W = 1024


def png(path: Path, pixels: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + pixels[y * W * 4 : (y + 1) * W * 4] for y in range(W))
    ihdr = struct.pack(">IIBBBBB", W, W, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    )


def inside_pin(x: float, y: float) -> str | None:
    cx, cy, r = 512, 400, 170
    dx, dy = x - cx, y - cy
    in_circle = dx * dx + dy * dy <= r * r
    in_dot = dx * dx + dy * dy <= 58 * 58
    in_tail = False
    if 360 <= y <= 860:
        half = 210 * ((860 - y) / 500)
        in_tail = abs(x - 512) <= half
    if in_dot:
        return "cream"
    if in_circle or in_tail:
        return "white"
    return None


def main() -> None:
    buf = bytearray(W * W * 4)
    for y in range(W):
        for x in range(W):
            kind = inside_pin(x + 0.5, y + 0.5)
            if kind == "white":
                color = (255, 255, 255, 255)
            elif kind == "cream":
                color = (232, 168, 74, 255)
            else:
                color = (15, 91, 84, 255)
            i = (y * W + x) * 4
            buf[i : i + 4] = bytes(color)
    out = Path(__file__).resolve().parents[1] / "SavesSorter/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    png(out, bytes(buf))
    print(out, out.stat().st_size)


if __name__ == "__main__":
    main()
