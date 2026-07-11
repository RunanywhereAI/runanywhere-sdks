#!/usr/bin/env python3
"""Validate and resolve the atomically selected private QHexRT prebuilt.

Exit 0 prints the immutable version directory. Exit 3 means no selected
prebuilt exists (the public/stub build is intentional). Any partial, broken,
or identity-mismatched selection exits 1 and must fail the build preflight.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys


ABSENT = 3
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def _strict_json(path: Path) -> dict[str, object]:
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise RuntimeError(f"duplicate QHexRT manifest key: {key}")
            result[key] = value
        return result

    payload = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs)
    if not isinstance(payload, dict):
        raise RuntimeError("QHexRT prebuilt manifest must be an object")
    return payload


def validate(prebuilt: Path, abi: str) -> Path | None:
    if prebuilt.is_symlink():
        raise RuntimeError(f"QHexRT prebuilt root must not be a symlink: {prebuilt}")
    if prebuilt.exists() and not prebuilt.is_dir():
        raise RuntimeError(f"QHexRT prebuilt root must be a directory: {prebuilt}")
    current = prebuilt / "current"
    if not current.exists() and not current.is_symlink():
        legacy = [prebuilt / "include", prebuilt / "lib", prebuilt / "qhexrt-prebuilt.json"]
        if any(path.exists() or path.is_symlink() for path in legacy):
            raise RuntimeError(
                "legacy QHexRT prebuilt payload exists without atomic current selection; "
                "restage it with QHexRT/tools/scripts/stage_prebuilt_for_sdk.sh"
            )
        # Immutable versions without `current` are retained history, not a
        # selected build input; public/stub mode is intentional.
        return None
    if not current.is_symlink():
        raise RuntimeError(f"QHexRT prebuilt/current must be an atomic symlink: {current}")
    raw_target = os.readlink(current)
    target_parts = PurePosixPath(raw_target).parts
    if (
        len(target_parts) != 2
        or target_parts[0] != "versions"
        or not SHA256.fullmatch(target_parts[1])
    ):
        raise RuntimeError("QHexRT prebuilt/current must directly name versions/<64-hex-receipt>")
    selected_entry = prebuilt / raw_target
    if selected_entry.is_symlink():
        raise RuntimeError("QHexRT selected immutable version must not be a symlink")
    try:
        selected = current.resolve(strict=True)
    except FileNotFoundError as error:
        raise RuntimeError(f"QHexRT prebuilt/current is broken: {current}") from error
    versions_path = prebuilt / "versions"
    if versions_path.is_symlink() or not versions_path.is_dir():
        raise RuntimeError("QHexRT prebuilt/versions must be a regular directory")
    versions = versions_path.resolve(strict=True)
    if selected.parent != versions:
        raise RuntimeError(f"QHexRT current selection is not a direct immutable version: {selected}")
    if selected.is_symlink() or not selected.is_dir():
        raise RuntimeError(f"QHexRT current selection is not a directory: {selected}")

    manifest_path = selected / "qhexrt-prebuilt.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise RuntimeError("QHexRT current selection has no regular qhexrt-prebuilt.json")
    manifest = _strict_json(manifest_path)
    required_top = {
        "schema", "build_receipt_sha256", "qhexrt_version", "c_abi",
        "android_abi", "source", "build", "files",
    }
    if set(manifest) != required_top or manifest.get("schema") != "qhexrt-prebuilt/v2":
        raise RuntimeError("QHexRT current selection is not a strict qhexrt-prebuilt/v2 payload")
    if manifest.get("android_abi") != abi:
        raise RuntimeError(
            f"QHexRT current ABI mismatch: manifest={manifest.get('android_abi')!r} build={abi!r}"
        )
    if not isinstance(manifest.get("build_receipt_sha256"), str) or not SHA256.fullmatch(
        manifest["build_receipt_sha256"]
    ):
        raise RuntimeError("QHexRT current selection has an invalid build receipt identity")
    if selected.name != manifest["build_receipt_sha256"]:
        raise RuntimeError("QHexRT immutable version name does not match its build receipt identity")
    receipt_path = selected / "qhexrt-build-receipt.json"
    if receipt_path.is_symlink() or not receipt_path.is_file():
        raise RuntimeError("QHexRT current selection has no regular sanitized build receipt")
    receipt_bytes = receipt_path.read_bytes()
    if hashlib.sha256(receipt_bytes).hexdigest() != manifest["build_receipt_sha256"]:
        raise RuntimeError("QHexRT sanitized build receipt hash does not match its immutable identity")
    receipt = _strict_json(receipt_path)
    expected_receipt = {
        "schema": "qhexrt-build-receipt/v1",
        "qhexrt_version": manifest["qhexrt_version"],
        "c_abi": manifest["c_abi"],
        "source": manifest["source"],
        "build": manifest["build"],
        "artifacts": manifest["files"],
    }
    if receipt != expected_receipt:
        raise RuntimeError("QHexRT manifest does not exactly derive from its sanitized build receipt")
    c_abi = manifest.get("c_abi")
    if (
        not isinstance(c_abi, dict)
        or set(c_abi) != {"major", "minor"}
        or isinstance(c_abi.get("major"), bool)
        or isinstance(c_abi.get("minor"), bool)
        or not isinstance(c_abi.get("major"), int)
        or not isinstance(c_abi.get("minor"), int)
        or c_abi["major"] != 1
        or c_abi["minor"] < 0
    ):
        raise RuntimeError("QHexRT current selection has an incompatible C ABI identity")
    source = manifest.get("source")
    if (
        not isinstance(source, dict)
        or set(source) != {"git_sha", "git_dirty", "state_sha256"}
        or not isinstance(source.get("git_sha"), str)
        or not re.fullmatch(r"[0-9a-f]{40}", source["git_sha"])
        or not isinstance(source.get("git_dirty"), bool)
        or not isinstance(source.get("state_sha256"), str)
        or not SHA256.fullmatch(source["state_sha256"])
    ):
        raise RuntimeError("QHexRT current selection has an invalid source identity")
    build = manifest.get("build")
    expected_build_keys = {
        "android_abi", "build_type", "cmake_cache_sha256", "cmake_system",
        "compiler", "ndk", "qnn_sdk", "archive_evidence",
    }
    if not isinstance(build, dict) or set(build) != expected_build_keys:
        raise RuntimeError("QHexRT current selection has an invalid build identity")
    if build.get("android_abi") != abi or not isinstance(build.get("build_type"), str):
        raise RuntimeError("QHexRT current selection build target identity is invalid")
    for key in ("cmake_cache_sha256",):
        if not isinstance(build.get(key), str) or not SHA256.fullmatch(build[key]):
            raise RuntimeError(f"QHexRT current selection has invalid build digest {key}")
    compiler = build.get("compiler")
    if not isinstance(compiler, dict) or set(compiler) != {
        "id", "version", "state_file_sha256", "sha256", "version_output_sha256"
    }:
        raise RuntimeError("QHexRT current selection has an invalid compiler identity")
    for key in ("state_file_sha256", "sha256", "version_output_sha256"):
        if not isinstance(compiler.get(key), str) or not SHA256.fullmatch(compiler[key]):
            raise RuntimeError(f"QHexRT current selection has invalid compiler digest {key}")
    if not all(isinstance(compiler.get(key), str) and compiler[key] for key in ("id", "version")):
        raise RuntimeError("QHexRT current selection has incomplete compiler identity")
    system = build.get("cmake_system")
    if not isinstance(system, dict) or set(system) != {
        "name", "processor", "crosscompiling", "state_file_sha256"
    } or system.get("name") != "Android" or system.get("processor") not in {"aarch64", "arm64"}:
        raise RuntimeError("QHexRT current selection has an invalid Android system identity")
    if not isinstance(system.get("state_file_sha256"), str) or not SHA256.fullmatch(system["state_file_sha256"]):
        raise RuntimeError("QHexRT current selection has invalid CMake system-state digest")
    for key in ("ndk", "qnn_sdk"):
        identity = build.get(key)
        if not isinstance(identity, dict) or set(identity) != {"metadata_file", "metadata_sha256"}:
            raise RuntimeError(f"QHexRT current selection has invalid {key} identity")
        metadata_file = identity.get("metadata_file")
        if (
            not isinstance(metadata_file, str)
            or not metadata_file
            or metadata_file in {".", ".."}
            or "/" in metadata_file
            or "\\" in metadata_file
        ):
            raise RuntimeError(f"QHexRT current selection has incomplete {key} identity")
        if not isinstance(identity.get("metadata_sha256"), str) or not SHA256.fullmatch(identity["metadata_sha256"]):
            raise RuntimeError(f"QHexRT current selection has invalid {key} digest")
    archive = build.get("archive_evidence")
    if not isinstance(archive, dict) or set(archive) != {
        "llvm_ar_sha256", "llvm_readelf_sha256", "core", "host"
    }:
        raise RuntimeError("QHexRT current selection has invalid archive evidence")
    for key in ("llvm_ar_sha256", "llvm_readelf_sha256"):
        if not isinstance(archive.get(key), str) or not SHA256.fullmatch(archive[key]):
            raise RuntimeError(f"QHexRT current selection has invalid archive-tool digest {key}")
    for key in ("core", "host"):
        entry = archive.get(key)
        if (
            not isinstance(entry, dict)
            or set(entry) != {"member_count"}
            or isinstance(entry.get("member_count"), bool)
            or not isinstance(entry.get("member_count"), int)
            or entry["member_count"] <= 0
        ):
            raise RuntimeError(f"QHexRT current selection has invalid {key} archive evidence")

    expected = {
        "include/qhexrt/qhexrt_c.h",
        f"lib/{abi}/libqhexrt_core.a",
        f"lib/{abi}/libqhexrt_host.a",
    }
    files = manifest.get("files")
    if not isinstance(files, dict) or set(files) != expected:
        raise RuntimeError("QHexRT current selection has an invalid file inventory")
    for relative, identity in files.items():
        if (
            not isinstance(identity, dict)
            or set(identity) != {"sha256", "size_bytes"}
            or not isinstance(identity.get("sha256"), str)
            or not SHA256.fullmatch(identity["sha256"])
            or isinstance(identity.get("size_bytes"), bool)
            or not isinstance(identity.get("size_bytes"), int)
            or identity["size_bytes"] <= 0
        ):
            raise RuntimeError(f"QHexRT current selection has invalid identity for {relative}")
        path = selected / relative
        cursor = selected
        if any((cursor := cursor / part).is_symlink() for part in PurePosixPath(relative).parts):
            raise RuntimeError(f"QHexRT current selection payload traverses a symlink: {relative}")
        if not path.is_file():
            raise RuntimeError(f"QHexRT current selection payload is missing/not regular: {relative}")
        digest = hashlib.sha256()
        size = 0
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
                size += len(chunk)
        if size != identity["size_bytes"] or digest.hexdigest() != identity["sha256"]:
            raise RuntimeError(f"QHexRT current selection identity mismatch: {relative}")
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prebuilt", type=Path, required=True)
    parser.add_argument("--android-abi", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9._+-]+", args.android_abi):
        raise SystemExit("unsafe Android ABI")
    try:
        selected = validate(args.prebuilt, args.android_abi)
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if selected is None:
        return ABSENT
    print(os.fspath(selected))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
