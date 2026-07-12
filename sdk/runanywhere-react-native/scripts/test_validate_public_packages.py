#!/usr/bin/env python3
"""Focused synthetic coverage for public React Native package validation."""

from __future__ import annotations

import io
import json
import plistlib
import struct
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
    "mlx": "@runanywhere/mlx",
    "onnx": "@runanywhere/onnx",
}
MLX_FRAMEWORKS = (
    "RABackendMLX",
    "RunAnywhereMLXRuntime",
    "RunAnywhereMLXMetal",
)
MLX_SLICES = ("ios-arm64", "ios-arm64-simulator")
MLX_LIFECYCLE_SYMBOLS = (
    "_ra_mlx_register_runtime",
    "_ra_mlx_unregister_runtime",
    "_ra_mlx_runtime_is_registered",
    "_ra_mlx_runtime_is_available",
)
MLX_METAL_ANCHOR_SYMBOL = "_ra_mlx_metal_resource_anchor"
MLX_DEVICE_UNDEFINED_SYMBOLS = (
    "_ra_mlx_set_clear_cancel_callback",
    "_rac_backend_mlx_register",
    "_rac_backend_mlx_unregister",
    "_rac_error_message",
    "_rac_mlx_set_callbacks",
)
PROTO_NAME = "@runanywhere/proto-ts"
PRIVACY_MANIFEST_BYTES = b"canonical Apple privacy manifest"
PRIVACY_RESOURCE_MARKER = (
    b'"RunAnywhereCorePrivacy" => ["ios/PrivacyInfo.xcprivacy"]'
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


def _macho(
    *,
    file_type: int,
    defined: tuple[str, ...] = (),
    undefined: tuple[str, ...] = (),
    install_name: str | None = None,
    markers: tuple[bytes, ...] = (),
    cpu_type: int = 0x0100000C,
    include_uuid: bool | None = None,
) -> bytes:
    strings = bytearray(b"\0")
    symbols: list[tuple[int, int, int, int, int]] = []
    for name in defined:
        string_index = len(strings)
        strings.extend(name.encode() + b"\0")
        symbols.append((string_index, 0x0F, 1, 0, 1))
    for name in undefined:
        string_index = len(strings)
        strings.extend(name.encode() + b"\0")
        symbols.append((string_index, 0x01, 0, 0, 0))

    dylib_command = b""
    if install_name is not None:
        encoded_name = install_name.encode() + b"\0"
        command_size = (24 + len(encoded_name) + 7) & ~7
        dylib_command = struct.pack(
            "<6I", 0xD, command_size, 24, 0, 0, 0
        ) + encoded_name.ljust(command_size - 24, b"\0")

    if include_uuid is None:
        include_uuid = file_type == 6
    uuid_command = (
        struct.pack("<2I16s", 0x1B, 24, bytes(range(16)))
        if include_uuid
        else b""
    )

    symbol_offset = 32 + len(dylib_command) + len(uuid_command) + 24
    symbol_payload = b"".join(struct.pack("<IBBHQ", *symbol) for symbol in symbols)
    strings_offset = symbol_offset + len(symbol_payload)
    symbol_command = struct.pack(
        "<6I",
        0x2,
        24,
        symbol_offset,
        len(symbols),
        strings_offset,
        len(strings),
    )
    commands = dylib_command + uuid_command + symbol_command
    header = struct.pack(
        "<8I",
        0xFEEDFACF,
        cpu_type,
        0,
        file_type,
        1 + bool(dylib_command) + bool(uuid_command),
        len(commands),
        0,
        0,
    )
    return header + commands + symbol_payload + bytes(strings) + b"".join(markers)


def _static_archive(object_payload: bytes) -> bytes:
    name = "fixture.o/".ljust(16)
    header = (
        name
        + "0".ljust(12)
        + "0".ljust(6)
        + "0".ljust(6)
        + "100644".ljust(8)
        + str(len(object_payload)).ljust(10)
        + "`\n"
    ).encode("ascii")
    padding = b"\n" if len(object_payload) % 2 else b""
    return b"!<arch>\n" + header + object_payload + padding


def _framework_plist(name: str, identifier: str, supported_platform: str) -> bytes:
    return plistlib.dumps(
        {
            "CFBundleName": name,
            "CFBundlePackageType": "FMWK",
            "CFBundleExecutable": name,
            "CFBundleIdentifier": identifier,
            "CFBundleSupportedPlatforms": [supported_platform],
            "MinimumOSVersion": "17.5",
        }
    )


def _mlx_package_files(
    frameworks: tuple[str, ...],
    slices: tuple[str, ...],
    wire_podspec: bool,
    mutation: str | None,
) -> dict[str, bytes]:
    files: dict[str, bytes] = {}
    library_paths = {
        "RABackendMLX": "librac_backend_mlx.a",
        "RunAnywhereMLXRuntime": "RunAnywhereMLXRuntime.framework",
        "RunAnywhereMLXMetal": "RunAnywhereMLXMetal.framework",
    }
    for framework in frameworks:
        libraries: list[dict[str, object]] = []
        for mlx_slice in slices:
            if mlx_slice == "ios-arm64":
                platform = "ios"
                supported_platform = "iPhoneOS"
                variant = None
            elif mlx_slice == "ios-arm64-simulator":
                platform = "ios"
                supported_platform = "iPhoneSimulator"
                variant = "simulator"
            else:
                platform = "macos"
                supported_platform = "MacOSX"
                variant = None
            entry: dict[str, object] = {
                "LibraryIdentifier": mlx_slice,
                "LibraryPath": library_paths[framework],
                "SupportedArchitectures": ["arm64"],
                "SupportedPlatform": platform,
            }
            if variant is not None:
                entry["SupportedPlatformVariant"] = variant
            libraries.append(entry)

            root = f"package/ios/Binaries/{framework}.xcframework/{mlx_slice}"
            if framework == "RABackendMLX":
                files[f"{root}/librac_backend_mlx.a"] = _static_archive(
                    _macho(file_type=1, defined=("_rac_backend_mlx_fixture",))
                )
                continue

            framework_root = f"{root}/{framework}.framework"
            identifier = (
                "ai.runanywhere.mlx.runtime"
                if framework == "RunAnywhereMLXRuntime"
                else "ai.runanywhere.mlx.metal"
            )
            files[f"{framework_root}/Info.plist"] = _framework_plist(
                framework, identifier, supported_platform
            )
            if framework == "RunAnywhereMLXRuntime":
                runtime_defined = MLX_LIFECYCLE_SYMBOLS
                runtime_undefined = (MLX_METAL_ANCHOR_SYMBOL,)
                if mlx_slice == "ios-arm64":
                    runtime_undefined += MLX_DEVICE_UNDEFINED_SYMBOLS
                elif mlx_slice == "ios-arm64-simulator":
                    runtime_undefined += ("_rac_backend_mlx_unregister",)
                if (
                    mutation == "simulator_shell_references"
                    and mlx_slice == "ios-arm64-simulator"
                ):
                    runtime_undefined += MLX_DEVICE_UNDEFINED_SYMBOLS
                if mutation == "runtime_missing_anchor":
                    runtime_undefined = tuple(
                        symbol
                        for symbol in runtime_undefined
                        if symbol != MLX_METAL_ANCHOR_SYMBOL
                    )
                if (
                    mutation == "device_missing_error_message"
                    and mlx_slice == "ios-arm64"
                ):
                    runtime_undefined = tuple(
                        symbol
                        for symbol in runtime_undefined
                        if symbol != "_rac_error_message"
                    )
                if mutation == "runtime_defines_anchor":
                    runtime_defined += (MLX_METAL_ANCHOR_SYMBOL,)
                if mutation == "runtime_defines_commons":
                    runtime_defined += ("_rac_duplicate_registry",)
                markers = (
                    b"ai.runanywhere.mlx.metal",
                    b"swift-transformers_Hub.bundle",
                )
                if mutation == "runtime_obsolete_lookup":
                    markers += (b"RunAnywhereMLXMetalDevice",)
                host_path_markers = {
                    "runtime_host_path_users": b"/Users/release-builder/private",
                    "runtime_host_path_home": b"/home/release-builder/private",
                    "runtime_host_path_var": b"/var/folders/release-builder/private",
                    "runtime_host_path_windows": b"\\Users\\builder\\private",
                    "runtime_host_path_tmp": b"/tmp/runanywhere-mlx-runtime-device",
                    "runtime_host_path_private_tmp": (
                        b"/private/tmp/runanywhere-mlx-runtime-simulator"
                    ),
                }
                if mutation in host_path_markers:
                    markers += (host_path_markers[mutation],)
                cpu_type = (
                    0x01000007 if mutation == "runtime_wrong_arch" else 0x0100000C
                )
                files[f"{framework_root}/{framework}"] = _static_archive(
                    _macho(
                        file_type=1,
                        defined=runtime_defined,
                        undefined=runtime_undefined,
                        markers=markers,
                        cpu_type=cpu_type,
                    )
                )
                continue

            metal_type = 1 if mutation == "metal_static" else 6
            install_name = (
                "@rpath/Wrong.framework/Wrong"
                if mutation == "metal_wrong_install_name"
                else "@rpath/RunAnywhereMLXMetal.framework/RunAnywhereMLXMetal"
            )
            files[f"{framework_root}/{framework}"] = _macho(
                file_type=metal_type,
                defined=("_ra_mlx_metal_resource_anchor",),
                install_name=install_name,
                include_uuid=mutation != "metal_missing_uuid",
            )
            files[f"{framework_root}/Headers/RunAnywhereMLXMetal.h"] = b"anchor"
            files[f"{framework_root}/Modules/module.modulemap"] = b"framework module"
            files[f"{framework_root}/default.metallib"] = (
                b"invalid" if mutation == "invalid_metallib" else b"MTLBsynthetic"
            )

        files[
            f"package/ios/Binaries/{framework}.xcframework/Info.plist"
        ] = plistlib.dumps({"AvailableLibraries": libraries})

    files[
        "package/ios/Resources/swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy"
    ] = b"privacy"
    files[
        "package/ios/Resources/swift-transformers_Hub.bundle/gpt2_tokenizer_config.json"
    ] = b"{}"
    files[
        "package/ios/Resources/swift-transformers_Hub.bundle/t5_tokenizer_config.json"
    ] = b"{}"
    files["package/ios/ThirdPartyNotices/swift-mlx-LICENSE"] = b"third-party license"

    podspec = b'"RABackendMLX.xcframework"\n'
    if wire_podspec:
        podspec += (
            b'"RunAnywhereMLXRuntime.xcframework"\n'
            b'"RunAnywhereMLXMetal.xcframework"\n'
            b'"ios/Resources/swift-crypto_Crypto.bundle"\n'
            b'"ios/Resources/swift-transformers_Hub.bundle"\n'
            b's.homepage      = "https://runanywhere.ai"\n'
            b's.license       = { type: "RunAnywhere License", file: "LICENSE" }\n'
            b's.swift_version = "6.2"\n'
            b'"Accelerate", "AVFoundation", "CoreGraphics", "CoreImage", "CoreML"\n'
            b'"Foundation", "Metal", "MetalKit", "NaturalLanguage", "UIKit"\n'
            b's.libraries = "c++"\n'
            b"s.user_target_xcconfig\n"
            b'"-Wl,-u,_ra_mlx_runtime_is_available"\n'
        )
    if mutation == "podspec_broad_resources":
        podspec += b'"ios/Resources/*.bundle"\n'
    if mutation == "podspec_all_load":
        podspec += b'"-all_load"\n'
    if mutation == "podspec_wrong_swift":
        podspec = podspec.replace(
            b's.swift_version = "6.2"', b's.swift_version = "6.0"'
        )
    files["package/RunAnywhereMLX.podspec"] = podspec

    removals = {
        "missing_metal_info": (
            "package/ios/Binaries/RunAnywhereMLXMetal.xcframework/Info.plist"
        ),
        "missing_metallib": (
            "package/ios/Binaries/RunAnywhereMLXMetal.xcframework/"
            "ios-arm64/RunAnywhereMLXMetal.framework/default.metallib"
        ),
        "missing_hub_resource": (
            "package/ios/Resources/swift-transformers_Hub.bundle/"
            "gpt2_tokenizer_config.json"
        ),
        "missing_notices": "package/ios/ThirdPartyNotices/swift-mlx-LICENSE",
    }
    removal = removals.get(mutation or "")
    if removal is not None:
        files.pop(removal)
    if mutation == "obsolete_metal_sidecar":
        files[
            "package/ios/Resources/RunAnywhereMLXMetalDevice.bundle/default.metallib"
        ] = b"MTLBobsolete"
    return files


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
    mlx_frameworks: tuple[str, ...] = MLX_FRAMEWORKS,
    mlx_slices: tuple[str, ...] = MLX_SLICES,
    wire_mlx_podspec: bool = True,
    mlx_mutation: str | None = None,
    package_license_payload: bytes | None = None,
    extra_entries: dict[str, bytes] | None = None,
) -> None:
    manifest: dict[str, object] = {
        "name": package_name,
        "version": "1.0.0",
    }
    if package_name != "@runanywhere/mlx":
        manifest.update(
            {
                "dependencies": {
                    "@bufbuild/protobuf": "^2.12.1",
                    PROTO_NAME: "1.0.0",
                },
                "bundledDependencies": [PROTO_NAME],
            }
        )
    manifest["license"] = (
        "MIT"
        if mlx_mutation == "license_metadata_mismatch"
        else "SEE LICENSE IN LICENSE"
    )
    manifest.update(metadata or {})
    with tarfile.open(dist / f"runanywhere-{slug}-1.0.0.tgz", "w:gz") as bundle:
        _add_bytes(bundle, "package/package.json", json.dumps(manifest).encode())
        license_payload = (
            package_license_payload
            if package_license_payload is not None
            else (REPO_ROOT / "LICENSE").read_bytes()
        )
        if mlx_mutation == "license_mismatch":
            license_payload = b"MIT\n"
        _add_bytes(bundle, "package/LICENSE", license_payload)
        for relative_path, payload in (headers or {}).items():
            _add_bytes(
                bundle,
                f"package/android/src/main/jniLibs/include/rac/{relative_path}",
                payload,
            )
        if include_proto and package_name != "@runanywhere/mlx":
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
        elif package_name == "@runanywhere/mlx":
            for name, payload in _mlx_package_files(
                mlx_frameworks,
                mlx_slices,
                wire_mlx_podspec,
                mlx_mutation,
            ).items():
                _add_bytes(bundle, name, payload)
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
                validate_public_packages(dist, headers, proto_archive, privacy_manifest)

    def test_rejects_non_mlx_license_drift(self) -> None:
        cases = (
            (
                "core license payload",
                "core",
                {"package_license_payload": b"MIT\n"},
                "@runanywhere/core package license does not match",
            ),
            (
                "llamacpp license metadata",
                "llamacpp",
                {"metadata": {"license": "MIT"}},
                "package license metadata must be",
            ),
        )
        for label, target, target_options, error_pattern in cases:
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
                        **(target_options if slug == target else {}),
                    )

                with self.assertRaisesRegex(
                    PackageValidationError, error_pattern
                ):
                    validate_public_packages(
                        dist, headers, proto_archive, privacy_manifest
                    )

    def test_rejects_incomplete_mlx_runtime_package(self) -> None:
        cases = (
            (
                "missing Swift runtime",
                {"mlx_frameworks": ("RABackendMLX", "RunAnywhereMLXMetal")},
                "RunAnywhereMLXRuntime XCFramework Info.plist",
            ),
            (
                "missing simulator slices",
                {"mlx_slices": ("ios-arm64",)},
                "missing ios-arm64-simulator",
            ),
            (
                "macOS-only runtimes",
                {"mlx_slices": ("macos-arm64",)},
                "missing ios-arm64",
            ),
            (
                "unwired podspec",
                {"wire_mlx_podspec": False},
                "podspec is missing required wiring",
            ),
            (
                "missing Metal metadata",
                {"mlx_mutation": "missing_metal_info"},
                "RunAnywhereMLXMetal XCFramework Info.plist",
            ),
            (
                "wrong runtime architecture",
                {"mlx_mutation": "runtime_wrong_arch"},
                "non-arm64 object",
            ),
            (
                "runtime missing dynamic Metal anchor",
                {"mlx_mutation": "runtime_missing_anchor"},
                "missing undefined symbols.*_ra_mlx_metal_resource_anchor",
            ),
            (
                "device runtime missing error message dependency",
                {"mlx_mutation": "device_missing_error_message"},
                "missing undefined symbols.*_rac_error_message",
            ),
            (
                "runtime owns dynamic Metal anchor",
                {"mlx_mutation": "runtime_defines_anchor"},
                "must not define the Metal resource anchor",
            ),
            (
                "runtime owns Commons symbol",
                {"mlx_mutation": "runtime_defines_commons"},
                "must not define Commons symbols",
            ),
            (
                "simulator retains unsupported shell references",
                {"mlx_mutation": "simulator_shell_references"},
                "must not retain unsupported shell references",
            ),
            (
                "runtime contains obsolete platform lookup",
                {"mlx_mutation": "runtime_obsolete_lookup"},
                "contains obsolete Metal lookup",
            ),
            *(
                (
                    f"runtime contains {label} host path",
                    {"mlx_mutation": mutation},
                    "absolute host build path",
                )
                for label, mutation in (
                    ("macOS user", "runtime_host_path_users"),
                    ("Linux home", "runtime_host_path_home"),
                    ("macOS temporary", "runtime_host_path_var"),
                    ("Windows user", "runtime_host_path_windows"),
                    ("MLX temporary", "runtime_host_path_tmp"),
                    ("private MLX temporary", "runtime_host_path_private_tmp"),
                )
            ),
            (
                "Metal framework is static",
                {"mlx_mutation": "metal_static"},
                "must be a dynamic library",
            ),
            (
                "Metal framework has wrong install name",
                {"mlx_mutation": "metal_wrong_install_name"},
                "install name must be",
            ),
            (
                "Metal framework has no UUID",
                {"mlx_mutation": "metal_missing_uuid"},
                "must contain exactly one LC_UUID command",
            ),
            (
                "missing Metal library",
                {"mlx_mutation": "missing_metallib"},
                "default.metallib",
            ),
            (
                "invalid Metal library",
                {"mlx_mutation": "invalid_metallib"},
                "default.metallib has invalid magic",
            ),
            (
                "missing generated Hub resource",
                {"mlx_mutation": "missing_hub_resource"},
                "MLX runtime resource",
            ),
            (
                "missing third-party notices",
                {"mlx_mutation": "missing_notices"},
                "third-party notices are missing",
            ),
            (
                "obsolete Metal sidecar",
                {"mlx_mutation": "obsolete_metal_sidecar"},
                "app-root resource bundles must be exactly",
            ),
            (
                "broad resource glob",
                {"mlx_mutation": "podspec_broad_resources"},
                "broad or obsolete wiring",
            ),
            (
                "broad linker retention",
                {"mlx_mutation": "podspec_all_load"},
                "broad or obsolete wiring",
            ),
            (
                "wrong Swift toolchain",
                {"mlx_mutation": "podspec_wrong_swift"},
                "podspec is missing required wiring.*swift_version",
            ),
            (
                "mismatched license file",
                {"mlx_mutation": "license_mismatch"},
                "package license does not match",
            ),
            (
                "wrong npm license metadata",
                {"mlx_mutation": "license_metadata_mismatch"},
                "license metadata must be",
            ),
            (
                "unused MLX protocol runtime dependencies",
                {
                    "metadata": {
                        "dependencies": {
                            "@bufbuild/protobuf": "^2.12.1",
                            PROTO_NAME: "1.0.0",
                        }
                    }
                },
                "must not declare unused proto runtime dependencies",
            ),
            (
                "unused MLX bundled protocol declaration",
                {"metadata": {"bundledDependencies": [PROTO_NAME]}},
                "bundledDependencies must be None",
            ),
        )
        for label, mlx_options, error_pattern in cases:
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
                    options = mlx_options if slug == "mlx" else {}
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
