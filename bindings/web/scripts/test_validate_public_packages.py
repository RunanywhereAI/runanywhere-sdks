#!/usr/bin/env python3
"""Focused synthetic coverage for Web release package validation."""

from __future__ import annotations

import io
import json
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "release"))

from rewrite_npm_package import rewrite_packed_manifest
from validate_public_packages import (
    PROTO_LICENSE_METADATA,
    PROTO_LICENSE_PATH,
    PackageValidationError,
    validate_public_packages,
)


PROTO_NAME = "@runanywhere/proto-ts"
PROTO_LICENSE = PROTO_LICENSE_PATH.read_bytes()
PACKAGE_NAMES = {
    "proto-ts": PROTO_NAME,
    "web": "@runanywhere/web",
    "web-llamacpp": "@runanywhere/web-llamacpp",
    "web-onnx": "@runanywhere/web-onnx",
}
# Diffusion is exposed through `@runanywhere/web` core — there is no separate
# publishable diffusion workspace package.
UNPUBLISHED_WORKSPACE_PACKAGES: set[str] = set()
PROTO_FILES = {
    "package.json": json.dumps(
        {
            "name": PROTO_NAME,
            "version": "1.0.0",
            "license": PROTO_LICENSE_METADATA,
        }
    ).encode(),
    "LICENSE": PROTO_LICENSE,
    "dist/index.js": b"export {};",
    "dist/index.d.ts": b"export {};",
}


def _add_bytes(bundle: tarfile.TarFile, name: str, payload: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(payload)
    info.mtime = 0
    bundle.addfile(info, io.BytesIO(payload))


def _write_package(
    dist: Path,
    slug: str,
    name: str,
    *,
    bundle_proto: bool = False,
    metadata: dict[str, object] | None = None,
    extra_entries: dict[str, bytes] | None = None,
    proto_license: bytes | None = PROTO_LICENSE,
) -> Path:
    manifest: dict[str, object] = {"name": name, "version": "1.0.0"}
    if name == PROTO_NAME:
        manifest["license"] = PROTO_LICENSE_METADATA
    if name in {"@runanywhere/web", "@runanywhere/web-llamacpp"}:
        manifest["dependencies"] = {
            "@bufbuild/protobuf": "^2.12.1",
            PROTO_NAME: "1.0.0",
        }
        manifest["bundledDependencies"] = [PROTO_NAME]
    manifest.update(metadata or {})
    archive = dist / f"runanywhere-{slug}-1.0.0.tgz"
    with tarfile.open(archive, "w:gz") as bundle:
        _add_bytes(bundle, "package/package.json", json.dumps(manifest).encode())
        if name == PROTO_NAME:
            for relative_path, payload in PROTO_FILES.items():
                if relative_path == "package.json":
                    continue
                if relative_path == "LICENSE":
                    if proto_license is None:
                        continue
                    payload = proto_license
                _add_bytes(bundle, f"package/{relative_path}", payload)
        else:
            _add_bytes(bundle, "package/dist/index.js", b"export {};")
        if bundle_proto:
            for relative_path, payload in PROTO_FILES.items():
                _add_bytes(
                    bundle,
                    f"package/node_modules/@runanywhere/proto-ts/{relative_path}",
                    payload,
                )
        for member_name, payload in (extra_entries or {}).items():
            _add_bytes(bundle, member_name, payload)
    return archive


def _write_valid_set(dist: Path) -> None:
    for slug, name in PACKAGE_NAMES.items():
        _write_package(
            dist,
            slug,
            name,
            bundle_proto=name in {"@runanywhere/web", "@runanywhere/web-llamacpp"},
        )


class WebPackageValidationTest(unittest.TestCase):
    def test_diffusion_shell_is_not_a_release_artifact_until_its_wasm_exists(self) -> None:
        self.assertTrue(UNPUBLISHED_WORKSPACE_PACKAGES.isdisjoint(PACKAGE_NAMES.values()))

    def test_accepts_exact_self_contained_package_set(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_valid_set(dist)
            validate_public_packages(dist, "1.0.0")

    def test_rewriter_pins_and_bundles_proto(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            proto = _write_package(dist, "proto-ts", PROTO_NAME)
            core = _write_package(
                dist,
                "web",
                "@runanywhere/web",
                metadata={
                    "dependencies": {
                        "@bufbuild/protobuf": "^2.12.1",
                        PROTO_NAME: "^1.0.0",
                    },
                    "bundledDependencies": [],
                },
            )

            self.assertEqual(
                rewrite_packed_manifest(core, "1.0.0", {PROTO_NAME: proto}), 0
            )
            with tarfile.open(core, "r:gz") as bundle:
                manifest_file = bundle.extractfile("package/package.json")
                self.assertIsNotNone(manifest_file)
                assert manifest_file is not None
                manifest = json.load(manifest_file)
                self.assertIsNotNone(
                    bundle.extractfile(
                        "package/node_modules/@runanywhere/proto-ts/package.json"
                    )
                )
            self.assertEqual(manifest["dependencies"][PROTO_NAME], "1.0.0")
            self.assertEqual(manifest["bundledDependencies"], [PROTO_NAME])

    def test_rejects_missing_or_changed_bundled_proto(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_valid_set(dist)
            (dist / "runanywhere-web-llamacpp-1.0.0.tgz").unlink()
            _write_package(
                dist, "web-llamacpp", "@runanywhere/web-llamacpp", bundle_proto=False,
            )
            with self.assertRaisesRegex(
                PackageValidationError, "bundled proto-ts inventory mismatch"
            ):
                validate_public_packages(dist)

    def test_rejects_incorrect_proto_license_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_valid_set(dist)
            (dist / "runanywhere-proto-ts-1.0.0.tgz").unlink()
            _write_package(
                dist,
                "proto-ts",
                PROTO_NAME,
                metadata={"license": "MIT"},
            )
            with self.assertRaisesRegex(
                PackageValidationError, "proto-ts license metadata"
            ):
                validate_public_packages(dist)

    def test_rejects_missing_or_changed_proto_license_notice(self) -> None:
        cases = (
            (None, "proto-ts package is missing LICENSE"),
            (
                b"not the RunAnywhere license notice",
                "proto-ts LICENSE does not match",
            ),
        )
        for proto_license, error_pattern in cases:
            with self.subTest(
                error_pattern=error_pattern
            ), tempfile.TemporaryDirectory() as temporary:
                dist = Path(temporary)
                _write_valid_set(dist)
                (dist / "runanywhere-proto-ts-1.0.0.tgz").unlink()
                _write_package(
                    dist,
                    "proto-ts",
                    PROTO_NAME,
                    proto_license=proto_license,
                )
                with self.assertRaisesRegex(PackageValidationError, error_pattern):
                    validate_public_packages(dist)

    def test_rejects_workspace_protocol_and_extra_package(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_valid_set(dist)
            (dist / "runanywhere-web-1.0.0.tgz").unlink()
            _write_package(
                dist,
                "web",
                "@runanywhere/web",
                bundle_proto=True,
                metadata={
                    "dependencies": {
                        "@bufbuild/protobuf": "^2.12.1",
                        PROTO_NAME: "workspace:*",
                    }
                },
            )
            with self.assertRaisesRegex(PackageValidationError, "workspace protocol"):
                validate_public_packages(dist)

            (dist / "runanywhere-web-1.0.0.tgz").unlink()
            _write_package(
                dist, "web", "@runanywhere/web", bundle_proto=True,
            )
            _write_package(dist, "extra", "@runanywhere/extra")
            with self.assertRaisesRegex(PackageValidationError, "package set mismatch"):
                validate_public_packages(dist)

    def test_rejects_unsafe_or_host_specific_payloads(self) -> None:
        cases = (
            ({"../escape.txt": b"escape"}, "unsafe archive entry"),
            (
                {"package/private/qhexrt/runtime.wasm": b"private"},
                "private QHexRT/QNN entry",
            ),
            (
                {
                    "package/wasm/runtime.wasm": b"\x00asm/Users/release-builder/private/source.cpp"
                },
                "absolute host build path",
            ),
            (
                {"package/README.md": b"https://github.com/Siddhesh2377/private-build"},
                "personal GitHub repository",
            ),
        )
        for extra_entries, error_pattern in cases:
            with self.subTest(
                error_pattern=error_pattern
            ), tempfile.TemporaryDirectory() as temporary:
                dist = Path(temporary)
                _write_valid_set(dist)
                (dist / "runanywhere-web-onnx-1.0.0.tgz").unlink()
                _write_package(
                    dist,
                    "web-onnx",
                    "@runanywhere/web-onnx",
                    extra_entries=extra_entries,
                )
                with self.assertRaisesRegex(PackageValidationError, error_pattern):
                    validate_public_packages(dist)

    def test_allows_only_exact_emscripten_virtual_home(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_valid_set(dist)
            (dist / "runanywhere-web-onnx-1.0.0.tgz").unlink()
            _write_package(
                dist,
                "web-onnx",
                "@runanywhere/web-onnx",
                extra_entries={
                    "package/wasm/runtime.js": (
                        b'FS.mkdir("/home/web_user"); HOME:"/home/web_user"'
                    )
                },
            )
            validate_public_packages(dist)

        for leaked_path in (
            b"/home/release-builder/project/source.cpp",
            b"/home/web_user/project/source.cpp",
            b"/home/web_user2/project/source.cpp",
        ):
            with self.subTest(
                leaked_path=leaked_path
            ), tempfile.TemporaryDirectory() as temporary:
                dist = Path(temporary)
                _write_valid_set(dist)
                (dist / "runanywhere-web-onnx-1.0.0.tgz").unlink()
                _write_package(
                    dist,
                    "web-onnx",
                    "@runanywhere/web-onnx",
                    extra_entries={"package/wasm/runtime.js": leaked_path},
                )
                with self.assertRaisesRegex(
                    PackageValidationError, "absolute host build path"
                ):
                    validate_public_packages(dist)


if __name__ == "__main__":
    unittest.main()
