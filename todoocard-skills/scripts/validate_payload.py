#!/usr/bin/env python3
import argparse
from pathlib import Path

OLD_800_480_RAW = 800 * 480 // 2
NEW_528_792_RAW = 528 * 792 // 2
NEW_528_792_QUICKLZ_STORED = 4 + (NEW_528_792_RAW // 64) * 67


def looks_like_quicklz_stored(data: bytes) -> tuple[bool, str]:
    if len(data) != NEW_528_792_QUICKLZ_STORED:
        return False, f"length is {len(data)}, expected {NEW_528_792_QUICKLZ_STORED}"
    if data[:4] != b"\x00\x00\x00\x00":
        return False, "missing 4-byte zero prefix"
    offset = 4
    block = 0
    while offset < len(data):
        if data[offset:offset + 3] != b"\x74\x43\x40":
            return False, f"bad chunk header at block {block}, offset {offset}"
        offset += 67
        block += 1
    return True, f"{block} stored 64-byte chunks"


def classify(path: Path) -> str:
    data = path.read_bytes()
    size = len(data)
    lines = [f"{path}: {size} bytes"]
    if size == OLD_800_480_RAW:
        lines.append("match: old 800x480 six-color direct bitmap payload")
    if size == NEW_528_792_RAW:
        lines.append("match: T3 528x792 raw six-color bitmap before protocol wrapping")
    ok, reason = looks_like_quicklz_stored(data)
    if ok:
        lines.append(f"match: T3 QuickLZ-stored controller payload ({reason})")
    elif size == NEW_528_792_QUICKLZ_STORED:
        lines.append(f"warning: T3-sized payload but wrapper check failed: {reason}")
    if len(lines) == 1:
        lines.append("match: unknown; compare against expected screen/profile")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate TodooCard image-transfer payload sizes/wrappers.")
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    for index, path in enumerate(args.paths):
        if index:
            print()
        print(classify(path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
