#!/usr/bin/env python3
"""Focused synthetic coverage for public React Native package validation."""

from __future__ import annotations

import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "release"))

from rewrite_npm_package import rewrite_packed_manifest
from validate_public_packages import PackageValidationError, validate_public_packages


PACKAGE_DIRS = {
    "core": "@runanywhere/core",
    "llamacpp": "@runanywhere/llamacpp",
    "onnx": "@runanywhere/onnx",
}
PROTO_NAME = "@runanywhere/proto-ts"
PRIVACY_MANIFEST_BYTES = b"canonical Apple privacy manifest"
PRIVACY_RESOURCE_MARKER = (
    b'\"RunAnywhereCorePrivacy\" => [\"ios/PrivacyInfo.xcprivacy\"]'
)
PROTO_FILES = {
    "package.json": json.dumps(
        {"name": PROTO_NAME, "version": "1.0.0"}
    ).encode(),
    "dist/index.js": b"export {};",
    "dist/index.d.ts": b"export {};",
}


def _add_bytes(bundle: tarfile.TarFile, name: str, payload: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(payload)
    info.mtime = 0
    bundle.addfile(info, io.BytesIO(payload))


def _write_proto_package(path: Path) -> None:
    with tarfile.open(path, "w:gz") as bundle:
        for relative_path, payload in PROTO_FILES.items():
            _add_bytes(bundle, f"package/{relative_path}", payload)


def _write_privacy_manifest(root: Path) -> Path:
    manifest = root / "PrivacyInfo.xcprivacy"
    manifest.write_bytes(PRIVACY_MANIFEST_BYTES)
    return manifest


def _write_package(
    dist: Path,
    slug: str,
    package_name: str,
    headers: dict[str, bytes] | None = None,
    metadata: dict[str, object] | None = None,
    include_proto: bool = True,
    core_privacy_payload: bytes | None = PRIVACY_MANIFEST_BYTES,
    include_backend_privacy: bool = False,
    wire_core_privacy: bool = True,
    extra_entries: dict[str, bytes] | None = None,
) -> None:
    manifest: dict[str, object] = {
        "name": package_name,
        "version": "1.0.0",
        "dependencies": {
            "@bufbuild/protobuf": "^2.12.1",
            PROTO_NAME: "1.0.0",
        },
        "bundledDependencies": [PROTO_NAME],
    }
    manifest.update(metadata or {})
    with tarfile.open(dist / f"runanywhere-{slug}-1.0.0.tgz", "w:gz") as bundle:
        _add_bytes(bundle, "package/package.json", json.dumps(manifest).encode())
        for relative_path, payload in (headers or {}).items():
            _add_bytes(
                bundle,
                f"package/android/src/main/jniLibs/include/rac/{relative_path}",
                payload,
            )
        if include_proto:
            for relative_path, payload in PROTO_FILES.items():
                _add_bytes(
                    bundle,
                    f"package/node_modules/@runanywhere/proto-ts/{relative_path}",
                    payload,
                )
        if package_name == "@runanywhere/core":
            if core_privacy_payload is not None:
                _add_bytes(
                    bundle,
                    "package/ios/PrivacyInfo.xcprivacy",
                    core_privacy_payload,
                )
            podspec = (
                b"s.resource_bundles = {\n  "
                + PRIVACY_RESOURCE_MARKER
                + b",\n}\n"
                if wire_core_privacy
                else b"Pod::Spec.new do |s|\nend\n"
            )
            _add_bytes(bundle, "package/RunAnywhereCore.podspec", podspec)
        elif include_backend_privacy:
            _add_bytes(
                bundle,
                "package/ios/PrivacyInfo.xcprivacy",
                PRIVACY_MANIFEST_BYTES,
            )
        for name, payload in (extra_entries or {}).items():
            _add_bytes(bundle, name, payload)


class PublicPackageValidationTest(unittest.TestCase):
    def test_rewrites_workspace_specs_and_bundles_exact_proto_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            proto_archive = dist / "proto.tgz"
            _write_proto_package(proto_archive)
            _write_package(
                dist,
                "llamacpp",
                "@runanywhere/llamacpp",
                metadata={
                    "dependencies": {
                        "@bufbuild/protobuf": "^2.12.1",
                        PROTO_NAME: "workspace:*",
                    },
                    "peerDependencies": {"@runanywhere/core": "workspace:^"},
                },
                include_proto=False,
            )
            archive = dist / "runanywhere-llamacpp-1.0.0.tgz"

            self.assertEqual(
                rewrite_packed_manifest(
                    archive, "1.0.0", {PROTO_NAME: proto_archive}
                ),
                2,
            )

            with tarfile.open(archive, "r:gz") as bundle:
                manifest_file = bundle.extractfile("package/package.json")
                self.assertIsNotNone(manifest_file)
                assert manifest_file is not None
                manifest = json.load(manifest_file)
                bundled_manifest = bundle.extractfile(
                    "package/node_modules/@runanywhere/proto-ts/package.json"
                )
                self.assertIsNotNone(bundled_manifest)
            self.assertEqual(manifest["dependencies"][PROTO_NAME], "1.0.0")
            self.assertEqual(
                manifest["peerDependencies"]["@runanywhere/core"], "1.0.0"
            )
            self.assertEqual(manifest["bundledDependencies"], [PROTO_NAME])

    def test_accepts_exact_public_set_with_proto_and_core_headers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            dist = root / "dist"
            headers = root / "include" / "rac"
            proto_archive = root / "proto.tgz"
            privacy_manifest = _write_privacy_manifest(root)
            dist.mkdir()
            (headers / "core").mkdir(parents=True)
            (headers / "core" / "rac_types.h").write_text("types", encoding="utf-8")
            (headers / "rac.h").write_text("api", encoding="utf-8")
            _write_proto_package(proto_archive)
            header_payloads = {"core/rac_types.h": b"types", "rac.h": b"api"}
            for slug, package_name in PACKAGE_DIRS.items():
                _write_package(
                    dist,
                    slug,
                    package_name,
                    header_payloads if slug == "core" else None,
                )

            validate_public_packages(
                dist, headers, proto_archive, privacy_manifest
            )

    def test_rejects_missing_bundled_proto_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            dist = root / "dist"
            headers = root / "include" / "rac"
            proto_archive = root / "proto.tgz"
            privacy_manifest = _write_privacy_manifest(root)
            dist.mkdir()
            headers.mkdir(parents=True)
            (headers / "rac.h").write_text("api", encoding="utf-8")
            _write_proto_package(proto_archive)
            for slug, package_name in PACKAGE_DIRS.items():
                _write_package(
                    dist,
                    slug,
                    package_name,
                    {"rac.h": b"api"} if slug == "core" else None,
                    include_proto=slug != "onnx",
                )

            with self.assertRaisesRegex(
                PackageValidationError, "bundled proto-ts inventory mismatch"
            ):
                validate_public_packages(
                    dist, headers, proto_archive, privacy_manifest
                )

    def test_rejects_missing_public_package_or_private_package(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            dist = root / "dist"
            headers = root / "include" / "rac"
            proto_archive = root / "proto.tgz"
            privacy_manifest = _write_privacy_manifest(root)
            dist.mkdir()
            headers.mkdir(parents=True)
            (headers / "rac.h").write_text("api", encoding="utf-8")
            _write_proto_package(proto_archive)
            for slug, package_name in PACKAGE_DIRS.items():
                _write_package(
                    dist,
                    slug,
                    package_name,
                    {"rac.h": b"api"} if slug == "core" else None,
                )
            (dist / "runanywhere-onnx-1.0.0.tgz").unlink()
            _write_package(dist, "qhexrt", "@runanywhere/qhexrt")

            with self.assertRaisesRegex(PackageValidationError, "package set mismatch"):
                validate_public_packages(
                    dist, headers, proto_archive, privacy_manifest
                )

    def test_rejects_workspace_protocol_in_any_manifest_section(self) -> None:
        for section in (
            "dependencies",
            "devDependencies",
            "optionalDependencies",
            "peerDependencies",
            "overrides",
        ):
            with self.subTest(section=section), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                dist = root / "dist"
                headers = root / "include" / "rac"
                proto_archive = root / "proto.tgz"
                privacy_manifest = _write_privacy_manifest(root)
                dist.mkdir()
                headers.mkdir(parents=True)
                (headers / "rac.h").write_text("api", encoding="utf-8")
                _write_proto_package(proto_archive)
                for slug, package_name in PACKAGE_DIRS.items():
                    override = None
                    if slug == "core":
                        override = {section: {PROTO_NAME: "workspace:*"}}
                        if section == "dependencies":
                            override = {
                                section: {
                                    "@bufbuild/protobuf": "^2.12.1",
                                    PROTO_NAME: "workspace:*",
                                }
                            }
                    _write_package(
                        dist,
                        slug,
                        package_name,
                        {"rac.h": b"api"} if slug == "core" else None,
                        override,
                    )

                with self.assertRaisesRegex(
                    PackageValidationError, "workspace protocol"
                ):
                    validate_public_packages(
                        dist, headers, proto_archive, privacy_manifest
                    )

    def test_rejects_non_exact_proto_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            dist = root / "dist"
            headers = root / "include" / "rac"
            proto_archive = root / "proto.tgz"
            privacy_manifest = _write_privacy_manifest(root)
            dist.mkdir()
            headers.mkdir(parents=True)
            (headers / "rac.h").write_text("api", encoding="utf-8")
            _write_proto_package(proto_archive)
            for slug, package_name in PACKAGE_DIRS.items():
                metadata = (
                    {
                        "dependencies": {
                            "@bufbuild/protobuf": "^2.12.1",
                            PROTO_NAME: "^1.0.0",
                        }
                    }
                    if slug == "onnx"
                    else None
                )
                _write_package(
                    dist,
                    slug,
                    package_name,
                    {"rac.h": b"api"} if slug == "core" else None,
                    metadata,
                )

            with self.assertRaisesRegex(
                PackageValidationError, "exact release version"
            ):
                validate_public_packages(
                    dist, headers, proto_archive, privacy_manifest
                )

    def test_rejects_divergent_duplicate_or_unwired_privacy_manifest(self) -> None:
        cases = (
            (
                "divergent core manifest",
                {"core_privacy_payload": b"divergent"},
                {},
                "Apple privacy manifest inventory mismatch",
            ),
            (
                "backend duplicate",
                {},
                {"include_backend_privacy": True},
                "Apple privacy manifest inventory mismatch",
            ),
            (
                "missing CocoaPods resource wiring",
                {"wire_core_privacy": False},
                {},
                "does not wire ios/PrivacyInfo.xcprivacy",
            ),
        )
        for label, core_options, onnx_options, error_pattern in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                dist = root / "dist"
                headers = root / "include" / "rac"
                proto_archive = root / "proto.tgz"
                privacy_manifest = _write_privacy_manifest(root)
                dist.mkdir()
                headers.mkdir(parents=True)
                (headers / "rac.h").write_text("api", encoding="utf-8")
                _write_proto_package(proto_archive)
                for slug, package_name in PACKAGE_DIRS.items():
                    options = core_options if slug == "core" else {}
                    if slug == "onnx":
                        options = onnx_options
                    _write_package(
                        dist,
                        slug,
                        package_name,
                        {"rac.h": b"api"} if slug == "core" else None,
                        **options,
                    )

                with self.assertRaisesRegex(
                    PackageValidationError, error_pattern
                ):
                    validate_public_packages(
                        dist, headers, proto_archive, privacy_manifest
                    )

    def test_rejects_unsafe_or_private_release_payloads(self) -> None:
        cases = (
            (
                "path traversal",
                {"../escape.txt": b"escape"},
                "unsafe archive entry",
            ),
            (
                "private backend path",
                {"package/private/qhexrt/bridge.bin": b"private"},
                "private QHexRT/QNN entry",
            ),
            (
                "host build path",
                {
                    "package/android/src/main/jniLibs/arm64-v8a/libpublic.so":
                        b"\x7fELF/Users/release-builder/private/source.cpp"
                },
                "absolute host build path",
            ),
            (
                "personal source repository",
                {
                    "package/README.md":
                        b"https://github.com/Siddhesh2377/private-build"
                },
                "personal GitHub repository",
            ),
        )
        for label, extra_entries, error_pattern in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                dist = root / "dist"
                headers = root / "include" / "rac"
                proto_archive = root / "proto.tgz"
                privacy_manifest = _write_privacy_manifest(root)
                dist.mkdir()
                headers.mkdir(parents=True)
                (headers / "rac.h").write_text("api", encoding="utf-8")
                _write_proto_package(proto_archive)
                for slug, package_name in PACKAGE_DIRS.items():
                    _write_package(
                        dist,
                        slug,
                        package_name,
                        {"rac.h": b"api"} if slug == "core" else None,
                        extra_entries=extra_entries if slug == "onnx" else None,
                    )

                with self.assertRaisesRegex(
                    PackageValidationError, error_pattern
                ):
                    validate_public_packages(
                        dist, headers, proto_archive, privacy_manifest
                    )


if __name__ == "__main__":
    unittest.main()
