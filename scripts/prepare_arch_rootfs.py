#!/usr/bin/env python3
"""Prepare deterministic minimal Arch Linux rootfs bundle for ARCH Linux Runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
import io
import lzma
import os
import posixpath
import shutil
import stat
import tarfile
import tempfile
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DISTRO = "archlinux"
DISTRO_NAME = "Arch Linux"
DISTRO_VERSION = "proot-distro-v4.29.0"
SOURCE_URL = "https://github.com/termux/proot-distro/releases/download/v4.29.0/archlinux-aarch64-pd-v4.29.0.tar.xz"
SOURCE_SHA256 = "08d74365213e647c558e561b0a2a7afb6fa3dfe345a1994c62ccac5af1a1cdc6"
SOURCE_SIZE = 151_744_988
SOURCE_PREFIX = "archlinux-aarch64"
PROOT_VERSION = "termux-proot-ab2e3464"
PROOT_SOURCE_URL = "https://github.com/termux/proot"
PROOT_SOURCE_COMMIT = "ab2e3464d04483b98a0614b470f3f8950d5a6468"
RUNTIME_VERSION = "arch-linux-runtime-v1"
BUNDLE_FORMAT_VERSION = 2
ARCHITECTURE = "aarch64"
DEFAULT_ARCHIVE = ROOT / "build" / "archlinux-aarch64-pd-v4.29.0.tar.xz"
DEFAULT_OUT = ROOT / "assets" / "runtime" / "arch-linux-rootfs-v1.bundle"
PAYLOAD_NAME = "rootfs.tar.xz"
FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)
MINIMAL_PACKAGES = [
    "bash",
    "pacman",
    "pacman-mirrorlist",
    "archlinux-keyring",
    "archlinuxarm-keyring",
    "coreutils",
    "ca-certificates",
    "ca-certificates-mozilla",
    "curl",
    "findutils",
    "grep",
    "sed",
    "gawk",
    "tar",
    "gzip",
    "xz",
    "zstd",
]
REQUIRED_PATHS = [
    "bin/sh",
    "bin/bash",
    "usr/bin/sh",
    "usr/bin/bash",
    "usr/bin/pacman",
    "usr/bin/ls",
    "usr/bin/curl",
    "usr/bin/find",
    "usr/bin/grep",
    "usr/bin/sed",
    "usr/bin/awk",
    "usr/bin/tar",
    "usr/bin/gzip",
    "usr/bin/xz",
    "usr/bin/zstd",
    "etc/os-release",
    "etc/pacman.conf",
    "etc/ssl/certs/ca-certificates.crt",
    "usr/share/pacman/keyrings/archlinuxarm.gpg",
    "usr/lib/ld-linux-aarch64.so.1",
    "usr/lib/libc.so.6",
]
EXTRA_KEEP_PREFIXES = [
    "etc/ca-certificates",
    "etc/ssl/certs",
]
USR_MERGE_PATHS = ["bin", "sbin", "lib", "lib64"]
KNOWN_HARDLINKS: dict[str, str] = {}
ALPM_LOCAL_DB_VERSION = "9\n"
SYNTHETIC_DIRECTORIES = [
    "etc/pacman.d/gnupg",
    "var/cache/pacman/pkg",
    "var/lib/pacman/sync",
]
SYNTHETIC_FILES = {
    "var/lib/pacman/local/ALPM_DB_VERSION": ALPM_LOCAL_DB_VERSION.encode("utf-8"),
}
GCC_SPLIT_SOURCE_PATHS = {
    "usr/lib/libgcc_s.so",
    "usr/lib/libgcc_s.so.1",
    "usr/lib/libstdc++.so",
    "usr/lib/libstdc++.so.6",
    "usr/lib/libstdc++.so.6.0.33",
    "usr/share/locale/de/LC_MESSAGES/libstdc++.mo",
    "usr/share/locale/fr/LC_MESSAGES/libstdc++.mo",
}
OVERLAY_PACKAGES = [
    {
        "name": "libgcc",
        "filename": "libgcc-16.1.1+r12+g301eb08fa2c5-1-aarch64.pkg.tar.xz",
        "sha256": "0f98bdf94a6e2f6758b9ffe98cbc9391a109326ed23bd264cabe0a81a04d7ae4",
        "size": 55_204,
        "repo": "core",
    },
    {
        "name": "libstdc++",
        "filename": "libstdc++-16.1.1+r12+g301eb08fa2c5-1-aarch64.pkg.tar.xz",
        "sha256": "19832a38b2c4820695d28289f1c4f371955586d39fb893d8cbc0d8dbb09a4383",
        "size": 694_148,
        "repo": "core",
    },
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as input_file:
        for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def download_if_missing(archive: Path) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    if archive.exists() and archive.stat().st_size == SOURCE_SIZE and sha256_file(archive) == SOURCE_SHA256:
        return
    partial = archive.with_suffix(archive.suffix + ".part")
    if partial.exists():
        partial.unlink()
    with urllib.request.urlopen(SOURCE_URL) as response, partial.open("wb") as output:
        shutil.copyfileobj(response, output)
    partial.replace(archive)


def verify_source_archive(archive: Path) -> None:
    if not archive.exists():
        raise FileNotFoundError(f"archive_missing: {archive}")
    actual_size = archive.stat().st_size
    if actual_size != SOURCE_SIZE:
        raise ValueError(f"source_size_mismatch: {actual_size} != {SOURCE_SIZE}")
    actual_sha = sha256_file(archive)
    if actual_sha != SOURCE_SHA256:
        raise ValueError(f"source_sha_mismatch: {actual_sha} != {SOURCE_SHA256}")

def normalize_archive_path(path: str) -> str:
    if path.replace("\\", "/").startswith("/"):
        raise ValueError(f"unsafe_path: {path}")
    raw = path.replace("\\", "/").strip("/")
    parts: list[str] = []
    for part in raw.split("/"):
        if not part or part == ".":
            continue
        if part == "..":
            raise ValueError(f"unsafe_path: {path}")
        parts.append(part)
    if not parts:
        raise ValueError(f"empty_path: {path}")
    return "/".join(parts)


def normalize_optional_target(target: str) -> str:
    return normalize_archive_path(target)


def stripped_member_path(member_name: str, is_dir: bool) -> str | None:
    name = member_name.rstrip("/") if is_dir else member_name
    prefix = f"{SOURCE_PREFIX}/"
    if name == SOURCE_PREFIX:
        return None
    if not name.startswith(prefix):
        raise ValueError(f"unexpected_prefix: {member_name}")
    normalized = name[len(prefix):]
    if not normalized:
        return None
    return normalize_archive_path(normalized)


def clean_output_member(member: tarfile.TarInfo, path: str) -> tarfile.TarInfo:
    output_member = member.replace(name=path, uid=0, gid=0, uname="root", gname="root", mtime=0)
    output_member.pax_headers = {}
    return output_member


def normalize_payload_path(path: str) -> str:
    raw = path.replace("\\", "/")
    if raw.startswith("/"):
        raise ValueError(f"unsafe_payload_path: {path}")
    normalized = normalize_archive_path(raw)
    if normalized == SOURCE_PREFIX or normalized.startswith(f"{SOURCE_PREFIX}/"):
        raise ValueError(f"payload_prefix_not_stripped: {path}")
    return normalized


@dataclass(frozen=True)
class PreparedBundle:
    manifest: dict[str, Any]
    payload: Path



@dataclass(frozen=True)
class OverlayPackage:
    name: str
    version: str
    local_dir: str
    path: Path
    pkginfo: dict[str, list[str]]
    files: list[str]
    mtree: bytes | None


def download_overlay_package(spec: dict[str, Any]) -> Path:
    cache = ROOT / "build" / "rootfs-overlay-packages"
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / spec["filename"]
    if not target.exists():
        url = f"http://mirror.archlinuxarm.org/aarch64/{spec['repo']}/{spec['filename']}"
        partial = target.with_suffix(target.suffix + ".part")
        if partial.exists():
            partial.unlink()
        with urllib.request.urlopen(url, timeout=120) as response:
            partial.write_bytes(response.read())
        partial.replace(target)
    if target.stat().st_size != spec["size"]:
        raise ValueError(f"overlay_size_mismatch: {spec['name']}: {target.stat().st_size}")
    actual = sha256_file(target)
    if actual != spec["sha256"]:
        raise ValueError(f"overlay_sha_mismatch: {spec['name']}: {actual}")
    return target


def parse_pkginfo(text: str) -> dict[str, list[str]]:
    fields: dict[str, list[str]] = {}
    for line in text.splitlines():
        if not line or line.startswith("#") or " = " not in line:
            continue
        key, value = line.split(" = ", 1)
        fields.setdefault(key, []).append(value)
    return fields


def local_desc_from_pkginfo(fields: dict[str, list[str]]) -> bytes:
    mapping = [
        ("NAME", "pkgname"),
        ("VERSION", "pkgver"),
        ("BASE", "pkgbase"),
        ("DESC", "pkgdesc"),
        ("URL", "url"),
        ("ARCH", "arch"),
        ("BUILDDATE", "builddate"),
        ("PACKAGER", "packager"),
        ("SIZE", "size"),
        ("REPLACES", "replaces"),
        ("DEPENDS", "depend"),
        ("OPTDEPENDS", "optdepend"),
        ("PROVIDES", "provides"),
        ("CONFLICTS", "conflict"),
        ("LICENSE", "license"),
    ]
    lines: list[str] = []
    for block, key in mapping:
        values = fields.get(key, [])
        if not values:
            continue
        lines.extend([f"%{block}%", *values, ""])
    lines.extend(["%REASON%", "1", "", "%VALIDATION%", "pgp", ""])
    return ("\n".join(lines) + "\n").encode("utf-8")


def read_overlay_package(spec: dict[str, Any]) -> OverlayPackage:
    path = download_overlay_package(spec)
    pkginfo: dict[str, list[str]] | None = None
    mtree: bytes | None = None
    files: list[str] = []
    with tarfile.open(path, "r:xz") as tar:
        for member in tar:
            if member.name == ".PKGINFO":
                extracted = tar.extractfile(member)
                if extracted is None:
                    raise ValueError(f"overlay_pkginfo_missing: {spec['name']}")
                pkginfo = parse_pkginfo(extracted.read().decode("utf-8", "replace"))
                continue
            if member.name == ".MTREE":
                extracted = tar.extractfile(member)
                mtree = extracted.read() if extracted is not None else None
                continue
            if member.name.startswith("."):
                continue
            path_name = normalize_archive_path(member.name)
            files.append(f"{path_name}/" if member.isdir() else path_name)
    if pkginfo is None:
        raise ValueError(f"overlay_pkginfo_missing: {spec['name']}")
    name = pkginfo.get("pkgname", [spec["name"]])[0]
    version = pkginfo.get("pkgver", ["unknown"])[0]
    return OverlayPackage(
        name=name,
        version=version,
        local_dir=f"var/lib/pacman/local/{name}-{version}",
        path=path,
        pkginfo=pkginfo,
        files=sorted(set(files)),
        mtree=mtree,
    )

def parse_pacman_blocks(text: str) -> dict[str, list[str]]:
    fields: dict[str, list[str]] = {}
    current: str | None = None
    values: list[str] = []
    for line in text.splitlines():
        if line.startswith("%") and line.endswith("%"):
            if current is not None:
                fields[current] = [value for value in values if value]
            current = line.strip("%")
            values = []
        elif current is not None:
            values.append(line)
    if current is not None:
        fields[current] = [value for value in values if value]
    return fields


def package_name_from_dep(dep: str) -> str:
    return dep.split("<", 1)[0].split(">", 1)[0].split("=", 1)[0]


def package_dir(member_name: str) -> str | None:
    prefix = f"{SOURCE_PREFIX}/var/lib/pacman/local/"
    if not member_name.startswith(prefix):
        return None
    rest = member_name[len(prefix):]
    if "/" not in rest:
        return None
    return rest.split("/", 1)[0]


def read_package_database(archive: Path) -> tuple[dict[str, dict[str, Any]], dict[str, str]]:
    packages: dict[str, dict[str, Any]] = {}
    files_by_dir: dict[str, list[str]] = {}
    with tarfile.open(archive, "r:xz") as tar:
        for member in tar:
            directory = package_dir(member.name)
            if directory is None:
                continue
            package_path = f"{SOURCE_PREFIX}/var/lib/pacman/local/{directory}"
            if member.name.endswith("/desc"):
                extracted = tar.extractfile(member)
                if extracted is None:
                    raise ValueError(f"missing_package_desc: {member.name}")
                fields = parse_pacman_blocks(extracted.read().decode("utf-8", "replace"))
                name = fields.get("NAME", [""])[0]
                if not name:
                    raise ValueError(f"package_name_missing: {member.name}")
                packages[name] = fields | {"_dir": package_path}
            elif member.name.endswith("/files"):
                extracted = tar.extractfile(member)
                if extracted is None:
                    raise ValueError(f"missing_package_files: {member.name}")
                fields = parse_pacman_blocks(extracted.read().decode("utf-8", "replace"))
                files_by_dir[package_path] = [normalize_archive_path(path) for path in fields.get("FILES", [])]
    for package in packages.values():
        package["_files"] = files_by_dir.get(package["_dir"], [])
    provides: dict[str, str] = {name: name for name in packages}
    for name, package in packages.items():
        for provided in package.get("PROVIDES", []):
            provides[package_name_from_dep(provided)] = name
    return packages, provides


def package_closure(packages: dict[str, dict[str, Any]], provides: dict[str, str]) -> set[str]:
    selected: set[str] = set()
    pending = list(MINIMAL_PACKAGES)
    while pending:
        dependency = pending.pop()
        key = package_name_from_dep(dependency)
        name = key if key in packages else provides.get(key)
        if name is None:
            raise ValueError(f"missing_package_dependency: {dependency}")
        if name in selected:
            continue
        selected.add(name)
        pending.extend(packages[name].get("DEPENDS", []))
    return selected


def add_ancestors(path: str, keep: set[str]) -> None:
    parts = path.split("/")
    for index in range(1, len(parts)):
        keep.add("/".join(parts[:index]))


def build_keep_set(packages: dict[str, dict[str, Any]], selected_packages: set[str]) -> set[str]:
    keep: set[str] = set()
    for name in selected_packages:
        package = packages[name]
        for package_file in package.get("_files", []):
            keep.add(package_file)
            add_ancestors(package_file, keep)
        local_dir = normalize_archive_path(package["_dir"][len(f"{SOURCE_PREFIX}/"):])
        keep.add(local_dir)
        add_ancestors(local_dir, keep)
        for local_file in ("desc", "files", "mtree", "install"):
            keep.add(f"{local_dir}/{local_file}")
    for path in REQUIRED_PATHS:
        keep.add(path)
        add_ancestors(path, keep)
    return keep

def should_keep_path(path: str, keep: set[str]) -> bool:
    return path in keep or any(path == prefix or path.startswith(f"{prefix}/") for prefix in EXTRA_KEEP_PREFIXES)



def member_kind(member: tarfile.TarInfo) -> str:
    if member.isdir():
        return "directory"
    if member.isreg():
        return "file"
    if member.issym():
        return "symlink"
    if member.islnk():
        return "hardlink"
    return "other"


def entry_for_member(member: tarfile.TarInfo, path: str, file_sha: str | None = None) -> dict[str, Any]:
    mode = f"{member.mode & 0o7777:04o}"
    kind = member_kind(member)
    if kind == "directory":
        return {"path": path, "type": kind, "mode": mode}
    if kind == "file":
        if file_sha is None:
            raise ValueError(f"missing_file_sha: {path}")
        return {"path": path, "type": kind, "mode": mode, "size": member.size, "sha256": file_sha}
    if kind == "symlink":
        return {"path": path, "type": kind, "mode": mode, "target": member.linkname}
    if kind == "hardlink":
        target = normalize_optional_target(member.linkname)
        if target.startswith(f"{SOURCE_PREFIX}/"):
            target = normalize_optional_target(target[len(SOURCE_PREFIX) + 1:])
        return {"path": path, "type": kind, "mode": mode, "target": target}
    raise ValueError(f"unsupported_archive_entry: {path}: {member.type!r}")


def add_payload_file(output: tarfile.TarFile, entries: list[dict[str, Any]], counts: dict[str, int], path: str, data: bytes, mode: int = 0o644) -> None:
    member = tarfile.TarInfo(path)
    member.uid = member.gid = 0
    member.uname = member.gname = "root"
    member.mtime = 0
    member.mode = mode
    member.size = len(data)
    output.addfile(member, io.BytesIO(data))
    entries.append({"path": path, "type": "file", "mode": f"{mode & 0o7777:04o}", "size": len(data), "sha256": sha256_bytes(data)})
    counts["regularFiles"] += 1


def add_payload_directory(output: tarfile.TarFile, entries: list[dict[str, Any]], counts: dict[str, int], path: str, mode: int = 0o755) -> None:
    member = tarfile.TarInfo(path)
    member.type = tarfile.DIRTYPE
    member.uid = member.gid = 0
    member.uname = member.gname = "root"
    member.mtime = 0
    member.mode = mode
    output.addfile(member)
    entries.append({"path": path, "type": "directory", "mode": f"{mode & 0o7777:04o}"})
    counts["directories"] += 1


def add_overlay_payload(output: tarfile.TarFile, entries: list[dict[str, Any]], counts: dict[str, int], seen_paths: set[str], package: OverlayPackage) -> None:
    with tarfile.open(package.path, "r:xz") as tar:
        for member in tar:
            if member.name.startswith("."):
                continue
            path = normalize_archive_path(member.name)
            kind = member_kind(member)
            if path in seen_paths:
                if kind == "directory":
                    continue
                raise ValueError(f"overlay_duplicate_path: {package.name}: {path}")
            seen_paths.add(path)
            output_member = clean_output_member(member, path)
            if kind == "directory":
                counts["directories"] += 1
                output.addfile(output_member)
                entries.append(entry_for_member(member, path))
            elif kind == "file":
                extracted = tar.extractfile(member)
                if extracted is None:
                    raise ValueError(f"overlay_missing_file_payload: {package.name}: {path}")
                data = extracted.read()
                file_sha = sha256_bytes(data)
                output_member.size = len(data)
                output.addfile(output_member, io.BytesIO(data))
                entries.append(entry_for_member(member, path, file_sha))
                counts["regularFiles"] += 1
            elif kind == "symlink":
                counts["symlinks"] += 1
                output.addfile(output_member)
                entries.append(entry_for_member(member, path))
            elif kind == "hardlink":
                counts["hardLinks"] += 1
                output.addfile(output_member)
                entries.append(entry_for_member(member, path))
            else:
                raise ValueError(f"overlay_unsupported_entry: {package.name}: {path}: {member.type!r}")

def inspect_archive(archive: Path) -> PreparedBundle:
    packages, provides = read_package_database(archive)
    selected_packages = package_closure(packages, provides)
    keep = build_keep_set(packages, selected_packages)
    overlay_packages = [read_overlay_package(spec) for spec in OVERLAY_PACKAGES]
    selected_packages.update(package.name for package in overlay_packages)
    gcc_libs_local_dir = normalize_archive_path(packages["gcc-libs"]["_dir"][len(f"{SOURCE_PREFIX}/"):])
    excluded_source_paths = set(GCC_SPLIT_SOURCE_PATHS) | {f"{gcc_libs_local_dir}/files", f"{gcc_libs_local_dir}/mtree"}
    entries: list[dict[str, Any]] = []
    counts = {"directories": 0, "regularFiles": 0, "symlinks": 0, "hardLinks": 0, "other": 0}
    seen_paths: set[str] = set()
    tmpdir = Path(tempfile.mkdtemp(prefix="syntac-rootfs-bundle-"))
    payload = tmpdir / PAYLOAD_NAME
    with tarfile.open(archive, "r:xz") as source, tarfile.open(payload, "w:xz", preset=6) as output:
        for member in source:
            path = stripped_member_path(member.name, member.isdir())
            if path is None or path in excluded_source_paths or not should_keep_path(path, keep):
                continue
            if path in seen_paths:
                raise ValueError(f"duplicate_source_path: {path}")
            seen_paths.add(path)
            kind = member_kind(member)
            if kind == "directory":
                counts["directories"] += 1
                output_member = clean_output_member(member, path)
                output.addfile(output_member)
                entries.append(entry_for_member(member, path))
            elif kind == "file":
                extracted = source.extractfile(member)
                if extracted is None:
                    raise ValueError(f"missing_file_payload: {path}")
                data = extracted.read()
                if len(data) != member.size:
                    raise ValueError(f"file_size_mismatch: {path}: {len(data)} != {member.size}")
                file_sha = sha256_bytes(data)
                output_member = clean_output_member(member, path)
                output_member.size = len(data)
                output.addfile(output_member, io.BytesIO(data))
                entries.append(entry_for_member(member, path, file_sha))
                counts["regularFiles"] += 1
            elif kind == "symlink":
                counts["symlinks"] += 1
                output_member = clean_output_member(member, path)
                output.addfile(output_member)
                entries.append(entry_for_member(member, path))
            elif kind == "hardlink":
                counts["hardLinks"] += 1
                output_member = clean_output_member(member, path)
                if output_member.linkname.startswith(f"{SOURCE_PREFIX}/"):
                    output_member.linkname = output_member.linkname[len(SOURCE_PREFIX) + 1:]
                output.addfile(output_member)
                entries.append(entry_for_member(member, path))
            else:
                counts["other"] += 1
                raise ValueError(f"unsupported_archive_entry: {path}: {member.type!r}")
        filtered_gcc_files = [
            path if path.endswith("/") else path
            for path in packages["gcc-libs"].get("_files", [])
            if path not in GCC_SPLIT_SOURCE_PATHS
        ]
        add_payload_file(output, entries, counts, f"{gcc_libs_local_dir}/files", ("%FILES%\n" + "\n".join(filtered_gcc_files) + "\n").encode("utf-8"))
        seen_paths.add(f"{gcc_libs_local_dir}/files")
        for package in overlay_packages:
            add_overlay_payload(output, entries, counts, seen_paths, package)
            add_payload_directory(output, entries, counts, package.local_dir)
            seen_paths.add(package.local_dir)
            add_payload_file(output, entries, counts, f"{package.local_dir}/desc", local_desc_from_pkginfo(package.pkginfo))
            seen_paths.add(f"{package.local_dir}/desc")
            add_payload_file(output, entries, counts, f"{package.local_dir}/files", ("%FILES%\n" + "\n".join(package.files) + "\n").encode("utf-8"))
            seen_paths.add(f"{package.local_dir}/files")
            if package.mtree is not None:
                add_payload_file(output, entries, counts, f"{package.local_dir}/mtree", package.mtree)
                seen_paths.add(f"{package.local_dir}/mtree")
        for directory in SYNTHETIC_DIRECTORIES:
            if directory not in seen_paths:
                add_payload_directory(output, entries, counts, directory)
                seen_paths.add(directory)
        for path, data in SYNTHETIC_FILES.items():
            if path not in seen_paths:
                add_payload_file(output, entries, counts, path, data)
                seen_paths.add(path)
    entries.sort(key=lambda item: item["path"])
    by_path = {entry["path"]: entry for entry in entries}
    usrmerge = {
        path: ({"type": by_path[path]["type"], "target": by_path[path].get("target"), "mode": by_path[path].get("mode")} if path in by_path else None)
        for path in USR_MERGE_PATHS
    }
    payload_sha = sha256_file(payload)
    payload_size = payload.stat().st_size
    installed_file_bytes = sum(entry.get("size", 0) for entry in entries if entry["type"] == "file")
    manifest = {
        "version": BUNDLE_FORMAT_VERSION,
        "runtimeVersion": RUNTIME_VERSION,
        "runtimeImplementation": "Open-source Termux PRoot",
        "distro": DISTRO,
        "distroName": DISTRO_NAME,
        "distroVersion": DISTRO_VERSION,
        "architecture": ARCHITECTURE,
        "prootVersion": PROOT_VERSION,
        "prootSource": {"url": PROOT_SOURCE_URL, "commit": PROOT_SOURCE_COMMIT},
        "source": {"url": SOURCE_URL, "sha256": SOURCE_SHA256, "size": SOURCE_SIZE},
        "sourcePrefixStripped": SOURCE_PREFIX,
        "minimalPackages": sorted(selected_packages),
        "requestedPackages": MINIMAL_PACKAGES,
        "overlayPackages": [package.name for package in overlay_packages],
        "payload": {"name": PAYLOAD_NAME, "sha256": payload_sha, "size": payload_size},
        "counts": counts | {"total": len(entries), "packages": len(selected_packages)},
        "installedSizeBytes": installed_file_bytes,
        "usrmerge": usrmerge,
        "entries": entries,
    }
    validate_manifest(manifest)
    validate_critical_paths(manifest)
    return PreparedBundle(manifest=manifest, payload=payload)


def entry_map(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for entry in manifest.get("entries", []):
        path = normalize_archive_path(str(entry.get("path", "")))
        if path in result:
            raise ValueError(f"duplicate_path: {path}")
        result[path] = entry
    return result


def validate_manifest(manifest: dict[str, Any]) -> None:
    if manifest.get("version") != BUNDLE_FORMAT_VERSION:
        raise ValueError("invalid_bundle_version")
    if manifest.get("runtimeVersion") != RUNTIME_VERSION:
        raise ValueError("invalid_runtime_version")
    if manifest.get("distro") != DISTRO:
        raise ValueError("invalid_distro")
    if manifest.get("architecture") != ARCHITECTURE:
        raise ValueError("invalid_architecture")
    if manifest.get("prootVersion") != PROOT_VERSION:
        raise ValueError("invalid_proot_version")
    payload = manifest.get("payload")
    if not isinstance(payload, dict) or payload.get("name") != PAYLOAD_NAME:
        raise ValueError("invalid_payload")
    entries = manifest.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("missing_entries")
    counts = {"directory": 0, "file": 0, "symlink": 0, "hardlink": 0}
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("invalid_entry")
        path = normalize_archive_path(str(entry.get("path", "")))
        if path in seen:
            raise ValueError(f"duplicate_path: {path}")
        seen.add(path)
        typ = entry.get("type")
        require_mode(entry)
        if typ == "directory":
            counts["directory"] += 1
        elif typ == "file":
            counts["file"] += 1
            if not isinstance(entry.get("size"), int) or entry["size"] < 0:
                raise ValueError(f"invalid_file_size: {path}")
            if not isinstance(entry.get("sha256"), str) or len(entry["sha256"]) != 64:
                raise ValueError(f"invalid_file_sha: {path}")
        elif typ == "symlink":
            counts["symlink"] += 1
            if not isinstance(entry.get("target"), str) or not entry["target"]:
                raise ValueError(f"invalid_symlink_target: {path}")
        elif typ == "hardlink":
            counts["hardlink"] += 1
            target = normalize_optional_target(str(entry.get("target", "")))
            if target not in seen and target not in {candidate.get("path") for candidate in entries if isinstance(candidate, dict)}:
                raise ValueError(f"invalid_hardlink_target: {path}")
        else:
            raise ValueError(f"invalid_entry_type: {path}: {typ}")
    manifest_counts = manifest.get("counts", {})
    expected = {
        "directories": counts["directory"],
        "regularFiles": counts["file"],
        "symlinks": counts["symlink"],
        "hardLinks": counts["hardlink"],
        "total": len(entries),
    }
    for key, value in expected.items():
        if manifest_counts.get(key) != value:
            raise ValueError(f"count_mismatch: {key}: {manifest_counts.get(key)} != {value}")


def require_mode(entry: dict[str, Any]) -> None:
    mode = entry.get("mode")
    if not isinstance(mode, str) or len(mode) != 4 or any(ch not in "01234567" for ch in mode):
        raise ValueError(f"invalid_mode: {entry.get('path')}")


def resolve_entry(entries: dict[str, dict[str, Any]], path: str) -> str | None:
    pending = [part for part in path.strip("/").split("/") if part]
    current = ""
    seen: set[str] = set()
    for _ in range(80):
        if not pending:
            entry = entries.get(current)
            if entry is None:
                return None
            if entry["type"] == "symlink":
                if current in seen:
                    return None
                seen.add(current)
                current = normalize_link_target(current, entry["target"])
                pending = [part for part in current.split("/") if part]
                current = ""
                continue
            return current
        part = pending.pop(0)
        candidate = part if not current else f"{current}/{part}"
        entry = entries.get(candidate)
        if entry is None:
            return None
        if entry["type"] == "symlink":
            if candidate in seen:
                return None
            seen.add(candidate)
            target = normalize_link_target(candidate, entry["target"])
            pending = [part for part in target.split("/") if part] + pending
            current = ""
        else:
            current = candidate
    return None


def normalize_link_target(link_path: str, target: str) -> str:
    if target.startswith("/"):
        raw = target.strip("/")
    else:
        raw = posixpath.join(posixpath.dirname(link_path), target)
    return normalize_archive_path(posixpath.normpath(raw))


def validate_critical_paths(manifest: dict[str, Any]) -> None:
    entries = entry_map(manifest)
    for path in REQUIRED_PATHS:
        resolved = resolve_entry(entries, path)
        if resolved is None:
            raise ValueError(f"critical_path_missing: {path}")
    for path, target in KNOWN_HARDLINKS.items():
        entry = entries.get(path)
        if entry is None or entry.get("type") != "hardlink" or resolve_hardlink_target(entry.get("target", ""), entries) != target:
            raise ValueError(f"known_hardlink_mismatch: {path}")


def write_bundle(bundle: PreparedBundle, output: Path) -> dict[str, Any]:
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest_bytes = json.dumps(bundle.manifest, sort_keys=True, separators=(",", ":")).encode("utf-8")
    tmp = output.with_suffix(output.suffix + ".tmp")
    if tmp.exists():
        tmp.unlink()
    with zipfile.ZipFile(tmp, "w") as archive:
        write_zip_entry(archive, "manifest.json", manifest_bytes, zipfile.ZIP_DEFLATED)
        write_zip_entry(archive, PAYLOAD_NAME, bundle.payload.read_bytes(), zipfile.ZIP_STORED)
    validation = validate_bundle(tmp)
    tmp.replace(output)
    return {
        "path": str(output),
        "size": output.stat().st_size,
        "sha256": sha256_file(output),
        "manifestSha256": sha256_bytes(manifest_bytes),
        "manifestEntryCount": len(bundle.manifest["entries"]),
        "payloadSize": bundle.manifest["payload"]["size"],
        "payloadSha256": bundle.manifest["payload"]["sha256"],
        "counts": bundle.manifest["counts"],
        "installedSizeBytes": bundle.manifest["installedSizeBytes"],
        "minimalPackages": bundle.manifest["minimalPackages"],
        "validation": validation,
    }


def write_zip_entry(archive: zipfile.ZipFile, name: str, data: bytes, compression: int) -> None:
    info = zipfile.ZipInfo(name, FIXED_ZIP_TIME)
    info.compress_type = compression
    info.external_attr = 0o100644 << 16
    archive.writestr(info, data)


def load_manifest_from_bundle(bundle_path: Path) -> dict[str, Any]:
    with zipfile.ZipFile(bundle_path) as archive:
        return json.loads(archive.read("manifest.json"))


def validate_bundle(bundle_path: Path, strict: bool = True) -> dict[str, Any]:
    with zipfile.ZipFile(bundle_path) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        validate_manifest(manifest)
        payload_info = manifest["payload"]
        payload_entry = archive.getinfo(PAYLOAD_NAME)
        payload_sha = hashlib.sha256()
        payload_paths: set[str] = set()
        duplicate_payload_paths: list[str] = []
        missing_from_manifest: list[str] = []
        type_mismatches: list[str] = []
        checksum_mismatches: list[str] = []
        target_mismatches: list[str] = []
        unsafe_paths: list[str] = []
        counts = {"directories": 0, "regularFiles": 0, "symlinks": 0, "hardLinks": 0, "other": 0}
        by_path = entry_map(manifest)
        with archive.open(payload_entry) as compressed:
            payload_data = compressed.read()
        payload_sha.update(payload_data)
        if len(payload_data) != payload_info["size"]:
            checksum_mismatches.append(f"payload:size:{len(payload_data)}")
        if payload_sha.hexdigest() != payload_info["sha256"]:
            checksum_mismatches.append(f"payload:sha256:{payload_sha.hexdigest()}")
        with lzma.LZMAFile(io.BytesIO(payload_data)) as payload_stream:
            with tarfile.open(fileobj=payload_stream, mode="r|") as tar:
                for member in tar:
                    try:
                        path = normalize_payload_path(member.name)
                    except ValueError as error:
                        unsafe_paths.append(f"{member.name}: {error}")
                        path = member.name.replace("\\", "/").strip("/") or member.name
                    if path in payload_paths:
                        duplicate_payload_paths.append(path)
                    payload_paths.add(path)
                    kind = member_kind(member)
                    if kind == "directory":
                        counts["directories"] += 1
                    elif kind == "file":
                        counts["regularFiles"] += 1
                    elif kind == "symlink":
                        counts["symlinks"] += 1
                    elif kind == "hardlink":
                        counts["hardLinks"] += 1
                    else:
                        counts["other"] += 1
                    entry = by_path.get(path)
                    if entry is None:
                        missing_from_manifest.append(path)
                        if kind == "file":
                            extracted = tar.extractfile(member)
                            if extracted is not None:
                                extracted.read()
                        continue
                    if entry["type"] != kind:
                        type_mismatches.append(f"{path}: payload={kind} manifest={entry['type']}")
                    if kind == "file":
                        extracted = tar.extractfile(member)
                        if extracted is None:
                            checksum_mismatches.append(f"{path}:missing_file_payload")
                            continue
                        data = extracted.read()
                        if len(data) != entry["size"]:
                            checksum_mismatches.append(f"{path}:size:{len(data)}!={entry['size']}")
                        actual_sha = sha256_bytes(data)
                        if actual_sha != entry["sha256"]:
                            checksum_mismatches.append(f"{path}:sha256:{actual_sha}")
                    elif kind == "symlink":
                        if member.linkname != entry.get("target"):
                            target_mismatches.append(f"{path}: {member.linkname} != {entry.get('target')}")
                    elif kind == "hardlink":
                        target = normalize_optional_target(member.linkname)
                        if target.startswith(f"{SOURCE_PREFIX}/"):
                            target = normalize_optional_target(target[len(SOURCE_PREFIX) + 1:])
                        if target != entry.get("target"):
                            target_mismatches.append(f"{path}: {target} != {entry.get('target')}")
        missing_from_payload = sorted(set(by_path) - payload_paths)
        count_mismatches = {
            key: {"payload": counts[key], "manifest": manifest["counts"].get(key)}
            for key in ("directories", "regularFiles", "symlinks", "hardLinks", "other")
            if counts[key] != manifest["counts"].get(key)
        }
        total_mismatch = len(payload_paths) != len(by_path)
        result = {
            "payloadEntries": len(payload_paths),
            "manifestEntries": len(by_path),
            "files": counts["regularFiles"],
            "directories": counts["directories"],
            "symlinks": counts["symlinks"],
            "hardlinks": counts["hardLinks"],
            "other": counts["other"],
            "missingFromManifest": len(missing_from_manifest),
            "missingFromPayload": len(missing_from_payload),
            "unsafePaths": len(unsafe_paths),
            "duplicatePayloadPaths": len(duplicate_payload_paths),
            "typeMismatches": len(type_mismatches),
            "checksumMismatches": len(checksum_mismatches),
            "targetMismatches": len(target_mismatches),
            "countMismatches": count_mismatches,
            "totalMismatch": total_mismatch,
            "examples": {
                "missingFromManifest": missing_from_manifest[:20],
                "missingFromPayload": missing_from_payload[:20],
                "unsafePaths": unsafe_paths[:20],
                "duplicatePayloadPaths": duplicate_payload_paths[:20],
                "typeMismatches": type_mismatches[:20],
                "checksumMismatches": checksum_mismatches[:20],
                "targetMismatches": target_mismatches[:20],
            },
        }
        failures = [
            result["missingFromManifest"],
            result["missingFromPayload"],
            result["unsafePaths"],
            result["duplicatePayloadPaths"],
            result["typeMismatches"],
            result["checksumMismatches"],
            result["targetMismatches"],
            len(count_mismatches),
            1 if total_mismatch else 0,
        ]
        if strict and any(failures):
            raise ValueError(f"bundle_validation_failed: {json.dumps(result, sort_keys=True)}")
        return result


def materialize_bundle(bundle_path: Path, destination: Path, force_copy_hardlinks: bool = False) -> dict[str, int]:
    manifest = load_manifest_from_bundle(bundle_path)
    validate_manifest(manifest)
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    by_path = entry_map(manifest)
    stats = {"directories": 0, "files": 0, "symlinks": 0, "hardLinks": 0, "hardLinkCopies": 0, "bytes": 0}
    final_modes: list[tuple[Path, int]] = []
    with zipfile.ZipFile(bundle_path) as archive:
        payload = archive.read(PAYLOAD_NAME)
    payload_info = manifest["payload"]
    if len(payload) != payload_info["size"] or sha256_bytes(payload) != payload_info["sha256"]:
        raise ValueError("payload_checksum_mismatch")
    with lzma.LZMAFile(io.BytesIO(payload)) as payload_stream:
        with tarfile.open(fileobj=payload_stream, mode="r|") as tar:
            seen_payload: set[str] = set()
            for member in tar:
                path = normalize_payload_path(member.name)
                if path not in by_path:
                    raise ValueError(f"payload_entry_not_in_manifest: {path}")
                if path in seen_payload:
                    raise ValueError(f"duplicate_payload_path: {path}")
                seen_payload.add(path)
                target = safe_destination(destination, path)
                mode = member.mode & 0o7777
                if member.isdir():
                    ensure_no_symlink_ancestor(destination, target.parent)
                    if target.is_symlink():
                        target.unlink()
                    target.mkdir(parents=True, exist_ok=True)
                    os.chmod(target, 0o700 | (mode & 0o700))
                    final_modes.append((target, mode & 0o777))
                    stats["directories"] += 1
                elif member.isreg():
                    ensure_no_symlink_ancestor(destination, target.parent)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    extracted = tar.extractfile(member)
                    if extracted is None:
                        raise ValueError(f"missing_payload_file: {path}")
                    data = extracted.read()
                    expected = by_path[path]
                    if len(data) != expected["size"] or sha256_bytes(data) != expected["sha256"]:
                        raise ValueError(f"corrupt_file: {path}")
                    if target.exists() or target.is_symlink():
                        target.unlink()
                    target.write_bytes(data)
                    os.chmod(target, mode & 0o777)
                    stats["files"] += 1
                    stats["bytes"] += len(data)
                elif member.issym():
                    ensure_no_symlink_ancestor(destination, target.parent)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() or target.is_symlink():
                        target.unlink()
                    os.symlink(member.linkname, target)
                    stats["symlinks"] += 1
                elif member.islnk():
                    source = safe_destination(destination, resolve_hardlink_target(member.linkname, by_path))
                    ensure_no_symlink_ancestor(destination, target.parent)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() or target.is_symlink():
                        target.unlink()
                    if force_copy_hardlinks:
                        shutil.copy2(source, target)
                        stats["hardLinkCopies"] += 1
                    else:
                        try:
                            os.link(source, target)
                            stats["hardLinks"] += 1
                        except OSError:
                            shutil.copy2(source, target)
                            stats["hardLinkCopies"] += 1
                    os.chmod(target, mode & 0o777)
                else:
                    raise ValueError(f"unsupported_payload_entry: {path}")
            missing = set(by_path) - seen_payload
            if missing:
                raise ValueError(f"manifest_entry_not_in_payload: {sorted(missing)[:5]}")
    for target, mode in sorted(final_modes, key=lambda item: len(str(item[0])), reverse=True):
        os.chmod(target, mode)
    return stats


def safe_destination(root: Path, relative: str) -> Path:
    path = normalize_payload_path(relative)
    root_absolute = Path(os.path.abspath(root))
    destination = Path(os.path.abspath(root_absolute / path))
    try:
        destination.relative_to(root_absolute)
    except ValueError as error:
        raise ValueError(f"unsafe_destination: {relative}") from error
    return destination


def ensure_no_symlink_ancestor(root: Path, parent: Path) -> None:
    root_absolute = Path(os.path.abspath(root))
    current = root_absolute
    parent_absolute = Path(os.path.abspath(parent))
    if parent_absolute == root_absolute:
        return
    for part in parent_absolute.relative_to(root_absolute).parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"symlink_parent_escape_risk: {current}")


def resolve_hardlink_target(target: str, by_path: dict[str, dict[str, Any]]) -> str:
    current = normalize_archive_path(target)
    seen: set[str] = set()
    while True:
        if current in seen:
            raise ValueError(f"hardlink_cycle: {target}")
        seen.add(current)
        entry = by_path.get(current)
        if entry is None:
            raise ValueError(f"hardlink_target_missing: {target}")
        if entry["type"] == "hardlink":
            current = normalize_archive_path(str(entry.get("target", "")))
            continue
        return current

def self_test() -> None:
    def make_entry(path: str, typ: str, data: bytes = b"", target: str | None = None, mode: str = "0644") -> dict[str, Any]:
        entry: dict[str, Any] = {"path": path, "type": typ, "mode": mode}
        if typ == "file":
            entry["size"] = len(data)
            entry["sha256"] = sha256_bytes(data)
        if target is not None:
            entry["target"] = target
        return entry

    def make_member(path: str, typ: str, data: bytes = b"", target: str | None = None, mode: int = 0o644) -> tuple[tarfile.TarInfo, bytes | None]:
        member = tarfile.TarInfo(path)
        member.uid = 0
        member.gid = 0
        member.uname = "root"
        member.gname = "root"
        member.mtime = 0
        member.mode = mode
        member.pax_headers = {}
        if typ == "directory":
            member.type = tarfile.DIRTYPE
            member.mode = mode | 0o700
            return member, None
        if typ == "file":
            member.type = tarfile.REGTYPE
            member.size = len(data)
            return member, data
        if typ == "symlink":
            member.type = tarfile.SYMTYPE
            member.linkname = target or ""
            member.mode = 0o777
            return member, None
        if typ == "hardlink":
            member.type = tarfile.LNKTYPE
            member.linkname = target or ""
            return member, None
        raise AssertionError(typ)

    def write_case(path: Path, manifest_entries: list[dict[str, Any]], payload_members: list[tuple[tarfile.TarInfo, bytes | None]]) -> None:
        payload_io = io.BytesIO()
        with tarfile.open(fileobj=payload_io, mode="w:xz", preset=1) as tar:
            for member, data in payload_members:
                tar.addfile(member, io.BytesIO(data) if data is not None else None)
        payload = payload_io.getvalue()
        counts = {
            "directories": sum(1 for entry in manifest_entries if entry["type"] == "directory"),
            "regularFiles": sum(1 for entry in manifest_entries if entry["type"] == "file"),
            "symlinks": sum(1 for entry in manifest_entries if entry["type"] == "symlink"),
            "hardLinks": sum(1 for entry in manifest_entries if entry["type"] == "hardlink"),
            "other": 0,
            "total": len(manifest_entries),
            "packages": 0,
        }
        manifest = {
            "version": BUNDLE_FORMAT_VERSION,
            "runtimeVersion": RUNTIME_VERSION,
            "runtimeImplementation": "Open-source Termux PRoot",
            "distro": DISTRO,
            "distroName": DISTRO_NAME,
            "distroVersion": DISTRO_VERSION,
            "architecture": ARCHITECTURE,
            "prootVersion": PROOT_VERSION,
            "source": {"url": SOURCE_URL, "sha256": SOURCE_SHA256, "size": SOURCE_SIZE},
            "payload": {"name": PAYLOAD_NAME, "sha256": sha256_bytes(payload), "size": len(payload)},
            "counts": counts,
            "installedSizeBytes": sum(entry.get("size", 0) for entry in manifest_entries),
            "entries": sorted(manifest_entries, key=lambda entry: entry["path"]),
        }
        with zipfile.ZipFile(path, "w") as archive:
            write_zip_entry(archive, "manifest.json", json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode("utf-8"), zipfile.ZIP_DEFLATED)
            write_zip_entry(archive, PAYLOAD_NAME, payload, zipfile.ZIP_STORED)

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        out = DEFAULT_OUT if DEFAULT_OUT.exists() else tmp / "rootfs.bundle"
        if not out.exists():
            write_bundle(inspect_archive(DEFAULT_ARCHIVE), out)
        manifest = load_manifest_from_bundle(out)
        validation = validate_bundle(out)
        assert validation["payloadEntries"] == manifest["counts"]["total"]
        assert validation["missingFromManifest"] == 0
        assert validation["missingFromPayload"] == 0
        assert validation["unsafePaths"] == 0

        long_name = "long/" + ("a" * 180) + ".txt"
        unicode_name = "unicode/Autoridad_de_Certificacion_Firmaprofesional_CIF_A62634068.pem"
        valid_entries = [
            make_entry("etc", "directory", mode="0755"),
            make_entry("etc/normal.txt", "file", b"normal"),
            make_entry("usr/bin/tool", "symlink", target="../lib/tool", mode="0777"),
            make_entry("absolute-link", "symlink", target="/usr/bin/tool", mode="0777"),
            make_entry("chain-a", "symlink", target="chain-b", mode="0777"),
            make_entry("chain-b", "symlink", target="etc/normal.txt", mode="0777"),
            make_entry("etc/ssl/certs/ca-certificates.crt", "symlink", target="../../ca-certificates/extracted/tls-ca-bundle.pem", mode="0777"),
            make_entry("root/file with spaces.txt", "file", b"spaces"),
            make_entry(long_name, "file", b"long"),
            make_entry(unicode_name, "file", b"unicode"),
            make_entry("hardlink-copy", "hardlink", target="etc/normal.txt"),
        ]
        valid_members = [
            make_member("etc", "directory", mode=0o755),
            make_member("etc/normal.txt", "file", b"normal"),
            make_member("usr/bin/tool", "symlink", target="../lib/tool"),
            make_member("absolute-link", "symlink", target="/usr/bin/tool"),
            make_member("chain-a", "symlink", target="chain-b"),
            make_member("chain-b", "symlink", target="etc/normal.txt"),
            make_member("etc/ssl/certs/ca-certificates.crt", "symlink", target="../../ca-certificates/extracted/tls-ca-bundle.pem"),
            make_member("root/file with spaces.txt", "file", b"spaces"),
            make_member(long_name, "file", b"long"),
            make_member(unicode_name, "file", b"unicode"),
            make_member("hardlink-copy", "hardlink", target="etc/normal.txt"),
        ]
        valid_bundle = tmp / "valid.bundle"
        write_case(valid_bundle, valid_entries, valid_members)
        valid = validate_bundle(valid_bundle)
        assert valid["missingFromManifest"] == 0
        assert valid["missingFromPayload"] == 0
        assert valid["unsafePaths"] == 0
        case_root = tmp / "case-root"
        case_stats = materialize_bundle(valid_bundle, case_root, force_copy_hardlinks=True)
        assert case_stats["files"] == 4
        assert (case_root / unicode_name).read_text() == "unicode"
        assert (case_root / "usr/bin/tool").is_symlink()

        invalid_cases = {
            "duplicate": (valid_entries[:1], [make_member("etc/normal.txt", "file", b"one"), make_member("etc/./normal.txt", "file", b"two")]),
            "traversal": ([], [make_member("../evil", "file", b"bad")]),
            "absolute": ([], [make_member("/evil", "file", b"bad")]),
            "payload_missing_manifest": ([], [make_member("extra", "file", b"bad")]),
            "manifest_missing_payload": ([make_entry("missing", "file", b"missing")], []),
        }
        for name, (manifest_entries, payload_members) in invalid_cases.items():
            path = tmp / f"{name}.bundle"
            write_case(path, manifest_entries, payload_members)
            try:
                validate_bundle(path)
                raise AssertionError(f"{name} not rejected")
            except ValueError:
                pass
        try:
            write_case(tmp / "manifest_traversal.bundle", [make_entry("../bad", "file", b"bad")], [make_member("../bad", "file", b"bad")])
            validate_bundle(tmp / "manifest_traversal.bundle")
            raise AssertionError("manifest traversal not rejected")
        except ValueError:
            pass
    print("self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate-bundle", action="store_true")
    args = parser.parse_args()

    if args.validate_bundle:
        manifest = load_manifest_from_bundle(args.output)
        result = validate_bundle(args.output, strict=False)
        print(json.dumps({"bundle": {"path": str(args.output), "size": args.output.stat().st_size, "sha256": sha256_file(args.output)}, "source": manifest.get("source"), "counts": manifest.get("counts"), "validation": result}, indent=2, sort_keys=True))
        if any(result[key] for key in ("missingFromManifest", "missingFromPayload", "unsafePaths", "duplicatePayloadPaths", "typeMismatches", "checksumMismatches", "targetMismatches")) or result["countMismatches"] or result["totalMismatch"]:
            return 1
        return 0
    if args.download:
        download_if_missing(args.archive)
    verify_source_archive(args.archive)
    if args.self_test:
        self_test()
        return 0
    prepared = inspect_archive(args.archive)
    if args.inspect:
        print(json.dumps({"counts": prepared.manifest["counts"], "installedSizeBytes": prepared.manifest["installedSizeBytes"], "payload": prepared.manifest["payload"], "minimalPackages": prepared.manifest["minimalPackages"]}, indent=2, sort_keys=True))
        return 0
    result = write_bundle(prepared, args.output)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
