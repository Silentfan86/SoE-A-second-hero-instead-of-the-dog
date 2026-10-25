#!/usr/bin/env python3
"""Build the SoE_A-second-hero-instead-of-the-dog patch on top of a Casual Run 2.0 ROM and create the add-on patch.

The add-on patch contains only the SoE_A-second-hero-instead-of-the-dog changes. Casual Run itself is not included:
players apply the official Casual Run 2.0 patch first, then the add-on patch.

Usage:
  python3 Build/make_addon.py CASUAL_RUN_2.0_ROM OUTPUT_FOLDER --asar PATH_TO_ASAR_1.91

Accepted base ROMs (both are Casual Run 2.0 from the official IPS):
  - 4,194,304 bytes, SHA-256 7186145722...ecbef0e6 (as documented in the Casual Run README)
  - 4,193,504 bytes: the same ROM as produced by Floating IPS, which ignores the size field
    at the end of the official IPS and leaves out the zero-filled last 800 bytes.
"""
import argparse
import hashlib
import shutil
import subprocess
import sys
import zlib
from pathlib import Path

NAME = "SoE_A-second-hero-instead-of-the-dog_beta1"
ROM_SIZE = 0x400000
BASE_SHA256 = "718614572208aec79b28e2287a09369bd3c9b64d3b1e87a17be26b56ecbef0e6"
PATCHES = ["fix_p2_signature.asm", "fix_ring_pad.asm", "coop_hero.asm"]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def crc32(data: bytes) -> str:
    return f"{zlib.crc32(data) & 0xFFFFFFFF:08X}"


def load_base(path: Path) -> bytes:
    data = path.read_bytes()
    if len(data) < ROM_SIZE:
        data = data + b"\x00" * (ROM_SIZE - len(data))
    if len(data) != ROM_SIZE or sha256(data) != BASE_SHA256:
        sys.exit(f"{path}: not a Casual Run 2.0 ROM (expected SHA-256 {BASE_SHA256} after padding to 4 MiB)")
    return data


def make_ips(base: bytes, target: bytes) -> bytes:
    """IPS with only the changed bytes, plus explicit records for the zero-filled ROM tail.

    The tail records make the result 4 MiB even when the patch is applied to the 4,193,504-byte
    variant of the Casual Run 2.0 ROM."""
    assert len(base) == len(target) <= 0x1000000
    out = bytearray(b"PATCH")
    i = 0
    while i < len(target):
        if base[i] == target[i]:
            i += 1
            continue
        start = i
        while i < len(target) and base[i] != target[i] and i - start < 0xFFFF:
            i += 1
        if start == 0x454F46:  # offset would read as "EOF"
            start -= 1
        out += start.to_bytes(3, "big") + (i - start).to_bytes(2, "big") + target[start:i]
    tail = len(target)
    while tail > 0 and target[tail - 1] == 0:
        tail -= 1
    pos = tail
    while pos < len(target):
        n = min(0xFFFF, len(target) - pos)
        out += pos.to_bytes(3, "big") + b"\x00\x00" + n.to_bytes(2, "big") + b"\x00"
        pos += n
    out += b"EOF"
    return bytes(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("casual_run_rom", type=Path, help="Casual Run 2.0 ROM (official IPS applied to the clean U.S. ROM)")
    ap.add_argument("out", type=Path, help="output folder")
    ap.add_argument("--asar", default="asar", help="asar 1.91 executable")
    args = ap.parse_args()

    here = Path(__file__).resolve().parent
    args.out.mkdir(parents=True, exist_ok=True)
    base = load_base(args.casual_run_rom)
    base_path = args.out / "Secret_of_Evermore_Casual_Run_v2.0.sfc"
    rom_path = args.out / f"{NAME}.sfc"
    base_path.write_bytes(base)
    shutil.copyfile(base_path, rom_path)
    for patch in PATCHES:
        subprocess.run([args.asar, str(here / patch), str(rom_path)], check=True)
    target = rom_path.read_bytes()
    if len(target) != ROM_SIZE:
        sys.exit("asar changed the ROM size")

    ips_path = args.out / f"{NAME}.ips"
    ips_path.write_bytes(make_ips(base, target))
    print(f"ROM: {rom_path}  CRC32 {crc32(target)}  SHA-256 {sha256(target)}")
    print(f"IPS: {ips_path}")
    print(f"Base: Casual Run 2.0  CRC32 {crc32(base)}  SHA-256 {sha256(base)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
