#!/usr/bin/env python3
"""Verify packaged open-source Termux PRoot runtime binaries."""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JNI = ROOT / "android" / "app" / "src" / "main" / "jniLibs" / "arm64-v8a"
FILES = {
    "libsyntac_proot.so": "2d278e9a3f96ca275776909551c63eb878fb96a6d1b7a6b0c6f94e7f9a2e056a",
    "libsyntac_proot_loader.so": "cf4f87772e1baf5950e35af9a729a1402898a81492e0aa011bcde3007455ddc8",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    for name, expected_sha in FILES.items():
        target = JNI / name
        if not target.exists():
            raise FileNotFoundError(target)
        actual_sha = sha256(target)
        if actual_sha != expected_sha:
            raise ValueError(f"proot_checksum_mismatch: {name}: {actual_sha}")
        print(f"Verified {target} sha256={actual_sha} size={target.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
