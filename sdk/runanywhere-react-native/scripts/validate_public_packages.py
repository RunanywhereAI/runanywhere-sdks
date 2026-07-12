#!/usr/bin/env python3
"""Validate the exact public React Native package set and bundled payloads."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import struct
import tarfile
from pathlib import Path, PurePosixPath


EXPECTED_PACKAGES = {
    "@runanywhere/core",
    "@runanywhere/llamacpp",
    "@runanywhere/mlx",
    "@runanywhere/onnx",
}
BUNDLED_PROTO = "@runanywhere/proto-ts"
PROTO_RUNTIME_DEPENDENCIES = {"@bufbuild/protobuf": "^2.12.1"}
CORE_PACKAGE = "@runanywhere/core"
MLX_PACKAGE = "@runanywhere/mlx"
PACKAGES_BUNDLING_PROTO = EXPECTED_PACKAGES - {MLX_PACKAGE}
EXPECTED_EXACT_RUNTIME_DEPENDENCIES = {
    name: {BUNDLED_PROTO} for name in PACKAGES_BUNDLING_PROTO
}
CORE_HEADER_PREFIX = "package/android/src/main/jniLibs/include/rac/"
BUNDLED_PROTO_PREFIX = "package/node_modules/@runanywhere/proto-ts/"
PRIVACY_MANIFEST_RELATIVE_PATH = "ios/PrivacyInfo.xcprivacy"
CORE_PODSPEC_PATH = "package/RunAnywhereCore.podspec"
MLX_PODSPEC_PATH = "package/RunAnywhereMLX.podspec"
PACKAGE_LICENSE_PATH = "package/LICENSE"
REPOSITORY_LICENSE_PATH = Path(__file__).resolve().parents[3] / "LICENSE"
MLX_XCFRAMEWORKS = {
    "RABackendMLX": "librac_backend_mlx.a",
    "RunAnywhereMLXRuntime": "RunAnywhereMLXRuntime.framework",
    "RunAnywhereMLXMetal": "RunAnywhereMLXMetal.framework",
}
MLX_SLICES = {
    "ios-arm64": {
        "SupportedArchitectures": ["arm64"],
        "SupportedPlatform": "ios",
    },
    "ios-arm64-simulator": {
        "SupportedArchitectures": ["arm64"],
        "SupportedPlatform": "ios",
        "SupportedPlatformVariant": "simulator",
    },
}
MLX_SUPPORTED_PLATFORMS = {
    "ios-arm64": ["iPhoneOS"],
    "ios-arm64-simulator": ["iPhoneSimulator"],
}
MLX_GENERATED_BUNDLE_NAMES = {
    "swift-crypto_Crypto.bundle",
    "swift-transformers_Hub.bundle",
}
MLX_RUNTIME_BUNDLE_LOOKUPS = {"swift-transformers_Hub.bundle"}
MLX_RESOURCE_FILES = (
    "package/ios/Resources/swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy",
    "package/ios/Resources/swift-transformers_Hub.bundle/gpt2_tokenizer_config.json",
    "package/ios/Resources/swift-transformers_Hub.bundle/t5_tokenizer_config.json",
)
MLX_PRIVACY_MANIFEST_RELATIVE_PATH = (
    "ios/Resources/swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy"
)
MLX_LIFECYCLE_SYMBOLS = {
    "_ra_mlx_register_runtime",
    "_ra_mlx_unregister_runtime",
    "_ra_mlx_runtime_is_registered",
    "_ra_mlx_runtime_is_available",
}
MLX_METAL_ANCHOR_SYMBOL = "_ra_mlx_metal_resource_anchor"
MLX_DEVICE_UNDEFINED_SYMBOLS = {
    "_ra_mlx_set_clear_cancel_callback",
    "_rac_backend_mlx_register",
    "_rac_backend_mlx_unregister",
    "_rac_error_message",
    "_rac_mlx_set_callbacks",
}
MLX_SIMULATOR_FORBIDDEN_UNDEFINED_SYMBOLS = {
    "_ra_mlx_set_clear_cancel_callback",
    "_rac_backend_mlx_register",
    "_rac_mlx_set_callbacks",
}
MLX_OBSOLETE_METAL_BUNDLES = (
    "RunAnywhereMLXMetalDevice",
    "RunAnywhereMLXMetalSimulator",
)
CORE_PRIVACY_RESOURCE_MARKER = (
    '"RunAnywhereCorePrivacy" => ["ios/PrivacyInfo.xcprivacy"]'
)
PRIVATE_PATH_MARKERS = ("qhexrt", "qnn", "adsprpc", "cdsprpc")
HOST_PATH_MARKERS = (b"/Users/", b"/home/", b"/var/folders/", b"\\Users\\")
MLX_HOST_PATH_MARKERS = HOST_PATH_MARKERS + (
    b"/tmp/runanywhere-mlx-runtime-",
    b"/private/tmp/runanywhere-mlx-runtime-",
)
PERSONAL_REPOSITORY_MARKERS = (
    b"github.com/siddhesh2377/",
    b"github.com/sanchitmonga22/",
)
HOST_PATH_PAYLOAD_SUFFIXES = (".so", ".a", ".dylib", ".dll", ".wasm")


class PackageValidationError(RuntimeError):
    """Raised when a public RN release package is missing or malformed."""


def _normalized_member_name(archive: Path, name: str) -> str:
    if "\\" in name:
        raise PackageValidationError(
            f"{archive.name}: unsafe archive entry uses a backslash"
        )
    normalized = name.removeprefix("./")
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise PackageValidationError(f"{archive.name}: unsafe archive entry")
    if path.parts[0] != "package":
        raise PackageValidationError(
            f"{archive.name}: archive entry is outside package/"
        )
    lowered = normalized.casefold()
    if any(marker in lowered for marker in PRIVATE_PATH_MARKERS):
        raise PackageValidationError(
            f"{archive.name}: private QHexRT/QNN entry is not publishable"
        )
    return normalized


def _validate_archive_members(archive: Path, bundle: tarfile.TarFile) -> None:
    names: set[str] = set()
    for member in bundle.getmembers():
        normalized = _normalized_member_name(archive, member.name)
        if normalized in names:
            raise PackageValidationError(
                f"{archive.name}: duplicate archive entry {normalized}"
            )
        names.add(normalized)
        if not member.isfile() and not member.isdir():
            raise PackageValidationError(
                f"{archive.name}: links and special archive entries are not publishable"
            )
        if not member.isfile():
            continue
        source = bundle.extractfile(member)
        if source is None:
            raise PackageValidationError(
                f"{archive.name}: cannot read archive member {normalized}"
            )
        payload = source.read()
        lowered_payload = payload.lower()
        if any(marker in lowered_payload for marker in PERSONAL_REPOSITORY_MARKERS):
            raise PackageValidationError(
                f"{archive.name}: personal GitHub repository reference is not publishable"
            )
        if normalized.casefold().endswith(HOST_PATH_PAYLOAD_SUFFIXES) and any(
            marker in payload for marker in HOST_PATH_MARKERS
        ):
            raise PackageValidationError(
                f"{archive.name}: binary payload exposes an absolute host build path"
            )


def _file_hashes(bundle: tarfile.TarFile, prefix: str) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for member in bundle.getmembers():
        member_name = member.name.removeprefix("./")
        if not member.isfile() or not member_name.startswith(prefix):
            continue
        source = bundle.extractfile(member)
        if source is None:
            raise PackageValidationError(f"cannot read archive member {member_name}")
        hashes[member_name.removeprefix(prefix)] = hashlib.sha256(
            source.read()
        ).hexdigest()
    return hashes


def _file_bytes(bundle: tarfile.TarFile, member_name: str) -> bytes | None:
    try:
        source = bundle.extractfile(member_name)
    except KeyError:
        return None
    if source is None:
        raise PackageValidationError(f"cannot read archive member {member_name}")
    return source.read()


def _required_file_bytes(
    archive: Path,
    bundle: tarfile.TarFile,
    member_name: str,
    label: str,
) -> bytes:
    payload = _file_bytes(bundle, member_name)
    if not payload:
        raise PackageValidationError(
            f"{archive.name}: missing or empty {label}: {member_name}"
        )
    return payload


def _load_plist(
    archive: Path,
    bundle: tarfile.TarFile,
    member_name: str,
    label: str,
) -> dict[str, object]:
    payload = _required_file_bytes(archive, bundle, member_name, label)
    try:
        value = plistlib.loads(payload)
    except (plistlib.InvalidFileException, ValueError) as error:
        raise PackageValidationError(
            f"{archive.name}: invalid {label}: {member_name}"
        ) from error
    if not isinstance(value, dict):
        raise PackageValidationError(
            f"{archive.name}: {label} must contain a dictionary: {member_name}"
        )
    return value


def _parse_macho(payload: bytes, label: str) -> dict[str, object]:
    """Parse the small Mach-O subset needed for release payload validation."""

    if len(payload) < 32 or payload[:4] != b"\xcf\xfa\xed\xfe":
        raise PackageValidationError(f"{label}: expected a thin 64-bit Mach-O")
    (
        _magic,
        cpu_type,
        _cpu_subtype,
        file_type,
        command_count,
        command_bytes,
        _flags,
        _reserved,
    ) = struct.unpack_from("<8I", payload)
    commands_end = 32 + command_bytes
    if commands_end > len(payload):
        raise PackageValidationError(f"{label}: truncated Mach-O load commands")

    symbol_command: tuple[int, int, int, int] | None = None
    install_name: str | None = None
    uuid_count = 0
    offset = 32
    for _ in range(command_count):
        if offset + 8 > commands_end:
            raise PackageValidationError(f"{label}: truncated Mach-O load command")
        command, command_size = struct.unpack_from("<2I", payload, offset)
        if command_size < 8 or offset + command_size > commands_end:
            raise PackageValidationError(f"{label}: invalid Mach-O load command size")
        if command == 0x2:  # LC_SYMTAB
            if command_size < 24:
                raise PackageValidationError(f"{label}: invalid LC_SYMTAB command")
            symbol_command = struct.unpack_from("<4I", payload, offset + 8)
        elif command == 0xD:  # LC_ID_DYLIB
            if command_size < 24:
                raise PackageValidationError(f"{label}: invalid LC_ID_DYLIB command")
            name_offset = struct.unpack_from("<I", payload, offset + 8)[0]
            name_start = offset + name_offset
            if name_start >= offset + command_size:
                raise PackageValidationError(f"{label}: invalid dylib install name")
            name_end = payload.find(b"\0", name_start, offset + command_size)
            if name_end == -1:
                name_end = offset + command_size
            install_name = payload[name_start:name_end].decode("utf-8", errors="strict")
        elif command == 0x1B:  # LC_UUID
            if command_size != 24:
                raise PackageValidationError(f"{label}: invalid LC_UUID command")
            uuid_count += 1
        offset += command_size
    if offset != commands_end:
        raise PackageValidationError(f"{label}: inconsistent Mach-O command size")

    defined: list[str] = []
    undefined: list[str] = []
    if symbol_command is not None:
        symbol_offset, symbol_count, strings_offset, strings_size = symbol_command
        symbols_end = symbol_offset + (symbol_count * 16)
        strings_end = strings_offset + strings_size
        if symbols_end > len(payload) or strings_end > len(payload):
            raise PackageValidationError(f"{label}: truncated Mach-O symbol table")
        strings = payload[strings_offset:strings_end]
        for index in range(symbol_count):
            entry_offset = symbol_offset + (index * 16)
            (
                string_index,
                symbol_type,
                _section,
                _description,
                _value,
            ) = struct.unpack_from("<IBBHQ", payload, entry_offset)
            if symbol_type & 0xE0 or not symbol_type & 0x01:  # N_STAB / !N_EXT
                continue
            if string_index >= len(strings):
                raise PackageValidationError(f"{label}: invalid Mach-O symbol name")
            name_end = strings.find(b"\0", string_index)
            if name_end == -1:
                raise PackageValidationError(
                    f"{label}: unterminated Mach-O symbol name"
                )
            name = strings[string_index:name_end].decode("utf-8", errors="strict")
            if symbol_type & 0x0E == 0:  # N_UNDF
                undefined.append(name)
            else:
                defined.append(name)

    return {
        "cpu_type": cpu_type,
        "file_type": file_type,
        "install_name": install_name,
        "uuid_count": uuid_count,
        "defined": defined,
        "undefined": undefined,
    }


def _static_archive_objects(payload: bytes, label: str) -> list[dict[str, object]]:
    if not payload.startswith(b"!<arch>\n"):
        raise PackageValidationError(f"{label}: expected a static archive")
    objects: list[dict[str, object]] = []
    offset = 8
    while offset < len(payload):
        if offset + 60 > len(payload):
            raise PackageValidationError(f"{label}: truncated archive member header")
        header = payload[offset : offset + 60]
        if header[58:60] != b"`\n":
            raise PackageValidationError(f"{label}: invalid archive member header")
        try:
            member_size = int(header[48:58].decode("ascii").strip())
        except ValueError as error:
            raise PackageValidationError(
                f"{label}: invalid archive member size"
            ) from error
        offset += 60
        member_end = offset + member_size
        if member_end > len(payload):
            raise PackageValidationError(f"{label}: truncated archive member")
        member = payload[offset:member_end]
        name = header[:16].decode("ascii", errors="replace").strip()
        if name.startswith("#1/"):
            try:
                name_size = int(name[3:])
            except ValueError as error:
                raise PackageValidationError(
                    f"{label}: invalid extended archive member name"
                ) from error
            if name_size > len(member):
                raise PackageValidationError(
                    f"{label}: truncated extended archive member name"
                )
            member = member[name_size:]
        if member.startswith(b"\xcf\xfa\xed\xfe"):
            objects.append(_parse_macho(member, label))
        offset = member_end + (member_size % 2)
    if not objects:
        raise PackageValidationError(f"{label}: archive contains no Mach-O objects")
    for macho in objects:
        if macho["cpu_type"] != 0x0100000C:
            raise PackageValidationError(
                f"{label}: archive contains a non-arm64 object"
            )
        if macho["file_type"] != 0x1:  # MH_OBJECT
            raise PackageValidationError(
                f"{label}: archive contains a non-object Mach-O"
            )
    return objects


def _validate_framework_plist(
    archive: Path,
    plist: dict[str, object],
    name: str,
    identifier: str,
    slice_identifier: str,
) -> None:
    expected = {
        "CFBundleName": name,
        "CFBundlePackageType": "FMWK",
        "CFBundleExecutable": name,
        "CFBundleIdentifier": identifier,
        "CFBundleSupportedPlatforms": MLX_SUPPORTED_PLATFORMS[slice_identifier],
        "MinimumOSVersion": "17.5",
    }
    for key, value in expected.items():
        if plist.get(key) != value:
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} Info.plist "
                f"{key} must be {value!r}, found {plist.get(key)!r}"
            )


def _validate_mlx_xcframework(
    archive: Path,
    bundle: tarfile.TarFile,
    name: str,
    library_path: str,
) -> None:
    root = f"package/ios/Binaries/{name}.xcframework"
    plist = _load_plist(
        archive,
        bundle,
        f"{root}/Info.plist",
        f"{name} XCFramework Info.plist",
    )
    available = plist.get("AvailableLibraries")
    if not isinstance(available, list):
        raise PackageValidationError(
            f"{archive.name}: {name} XCFramework Info.plist is missing AvailableLibraries"
        )
    libraries: dict[str, dict[str, object]] = {}
    for entry in available:
        if not isinstance(entry, dict):
            raise PackageValidationError(
                f"{archive.name}: {name} XCFramework has invalid library metadata"
            )
        identifier = entry.get("LibraryIdentifier")
        if not isinstance(identifier, str) or identifier in libraries:
            raise PackageValidationError(
                f"{archive.name}: {name} XCFramework has an invalid or duplicate slice"
            )
        libraries[identifier] = entry

    for slice_identifier, expected in MLX_SLICES.items():
        entry = libraries.get(slice_identifier)
        if entry is None:
            raise PackageValidationError(
                f"{archive.name}: {name} XCFramework is missing {slice_identifier}"
            )
        for key, value in expected.items():
            if entry.get(key) != value:
                raise PackageValidationError(
                    f"{archive.name}: {name} {slice_identifier} {key} "
                    f"must be {value!r}, found {entry.get(key)!r}"
                )
        if (
            "SupportedPlatformVariant" not in expected
            and entry.get("SupportedPlatformVariant") is not None
        ):
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} must not declare "
                "a platform variant"
            )
        if entry.get("LibraryPath") != library_path:
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} LibraryPath must be "
                f"{library_path!r}, found {entry.get('LibraryPath')!r}"
            )

        slice_root = f"{root}/{slice_identifier}"
        if name == "RABackendMLX":
            binary_path = f"{slice_root}/{library_path}"
            payload = _required_file_bytes(
                archive, bundle, binary_path, f"{name} {slice_identifier} binary"
            )
            if any(marker in payload for marker in MLX_HOST_PATH_MARKERS):
                raise PackageValidationError(
                    f"{archive.name}: {name} {slice_identifier} binary exposes an "
                    "absolute host build path"
                )
            _static_archive_objects(
                payload, f"{archive.name}: {name} {slice_identifier}"
            )
            continue

        framework_root = f"{slice_root}/{library_path}"
        framework_plist = _load_plist(
            archive,
            bundle,
            f"{framework_root}/Info.plist",
            f"{name} {slice_identifier} framework Info.plist",
        )
        identifier = (
            "ai.runanywhere.mlx.runtime"
            if name == "RunAnywhereMLXRuntime"
            else "ai.runanywhere.mlx.metal"
        )
        _validate_framework_plist(
            archive, framework_plist, name, identifier, slice_identifier
        )
        binary_path = f"{framework_root}/{name}"
        payload = _required_file_bytes(
            archive, bundle, binary_path, f"{name} {slice_identifier} binary"
        )
        if any(marker in payload for marker in MLX_HOST_PATH_MARKERS):
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} binary exposes an "
                "absolute host build path"
            )

        if name == "RunAnywhereMLXRuntime":
            objects = _static_archive_objects(
                payload, f"{archive.name}: {name} {slice_identifier}"
            )
            defined = [
                symbol
                for macho in objects
                for symbol in macho["defined"]  # type: ignore[union-attr]
            ]
            undefined = {
                symbol
                for macho in objects
                for symbol in macho["undefined"]  # type: ignore[union-attr]
            }
            for symbol in MLX_LIFECYCLE_SYMBOLS:
                if defined.count(symbol) != 1:
                    raise PackageValidationError(
                        f"{archive.name}: {name} {slice_identifier} must define "
                        f"{symbol} exactly once"
                    )
            if "_ra_mlx_metal_resource_anchor" in defined:
                raise PackageValidationError(
                    f"{archive.name}: {name} {slice_identifier} must not define "
                    "the Metal resource anchor"
                )
            owned_commons_symbols = {
                symbol for symbol in defined if symbol.startswith("_rac_")
            }
            if owned_commons_symbols:
                raise PackageValidationError(
                    f"{archive.name}: {name} {slice_identifier} must not define "
                    f"Commons symbols {sorted(owned_commons_symbols)}"
                )
            required_undefined = {MLX_METAL_ANCHOR_SYMBOL}
            if slice_identifier == "ios-arm64":
                required_undefined |= MLX_DEVICE_UNDEFINED_SYMBOLS
            missing_undefined = required_undefined - undefined
            if missing_undefined:
                raise PackageValidationError(
                    f"{archive.name}: {name} {slice_identifier} is missing undefined "
                    f"symbols {sorted(missing_undefined)}"
                )
            if slice_identifier == "ios-arm64-simulator":
                phantom_shell_symbols = (
                    MLX_SIMULATOR_FORBIDDEN_UNDEFINED_SYMBOLS & undefined
                )
                if phantom_shell_symbols:
                    raise PackageValidationError(
                        f"{archive.name}: {name} {slice_identifier} must not retain "
                        "unsupported shell references "
                        f"{sorted(phantom_shell_symbols)}"
                    )
            marker = b"ai.runanywhere.mlx.metal"
            if payload.count(marker) != 1:
                raise PackageValidationError(
                    f"{archive.name}: {name} {slice_identifier} must contain exactly "
                    "one Metal bundle-ID lookup"
                )
            for bundle_name in MLX_RUNTIME_BUNDLE_LOOKUPS:
                if bundle_name.encode() not in payload:
                    raise PackageValidationError(
                        f"{archive.name}: {name} {slice_identifier} is missing "
                        f"Bundle.module lookup {bundle_name}"
                    )
            for obsolete in MLX_OBSOLETE_METAL_BUNDLES:
                if obsolete.encode() in payload:
                    raise PackageValidationError(
                        f"{archive.name}: {name} {slice_identifier} contains obsolete "
                        f"Metal lookup {obsolete}"
                    )
            continue

        macho = _parse_macho(payload, f"{archive.name}: {name} {slice_identifier}")
        if macho["cpu_type"] != 0x0100000C:
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} must be arm64"
            )
        if macho["file_type"] != 0x6:  # MH_DYLIB
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} must be a dynamic library"
            )
        if macho["uuid_count"] != 1:
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} must contain exactly "
                f"one LC_UUID command, found {macho['uuid_count']}"
            )
        expected_install_name = (
            "@rpath/RunAnywhereMLXMetal.framework/RunAnywhereMLXMetal"
        )
        if macho["install_name"] != expected_install_name:
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} install name must be "
                f"{expected_install_name!r}, found {macho['install_name']!r}"
            )
        defined = macho["defined"]
        if not isinstance(defined, list):
            raise AssertionError("Mach-O defined symbols must be a list")
        if defined.count("_ra_mlx_metal_resource_anchor") != 1:
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} must export the Metal "
                "resource anchor exactly once"
            )
        forbidden = {
            symbol
            for symbol in defined
            if symbol.startswith("_rac_") or symbol in MLX_LIFECYCLE_SYMBOLS
        }
        if forbidden:
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} exports forbidden symbols "
                f"{sorted(forbidden)}"
            )
        for relative_path in (
            "Headers/RunAnywhereMLXMetal.h",
            "Modules/module.modulemap",
        ):
            _required_file_bytes(
                archive,
                bundle,
                f"{framework_root}/{relative_path}",
                f"{name} {slice_identifier} {relative_path}",
            )
        metallib = _required_file_bytes(
            archive,
            bundle,
            f"{framework_root}/default.metallib",
            f"{name} {slice_identifier} default.metallib",
        )
        if not metallib.startswith(b"MTLB"):
            raise PackageValidationError(
                f"{archive.name}: {name} {slice_identifier} default.metallib "
                "has invalid magic"
            )


def _validate_public_package_license(
    archive: Path, bundle: tarfile.TarFile, package_name: str
) -> None:
    if not REPOSITORY_LICENSE_PATH.is_file():
        raise PackageValidationError(
            f"repository license is missing: {REPOSITORY_LICENSE_PATH}"
        )
    package_license = _required_file_bytes(
        archive, bundle, PACKAGE_LICENSE_PATH, f"{package_name} package license"
    )
    if package_license != REPOSITORY_LICENSE_PATH.read_bytes():
        raise PackageValidationError(
            f"{archive.name}: {package_name} package license does not match "
            "the repository license"
        )


def _validate_mlx_package(archive: Path, bundle: tarfile.TarFile) -> None:
    for name, library_path in MLX_XCFRAMEWORKS.items():
        _validate_mlx_xcframework(archive, bundle, name, library_path)

    member_names = {
        member.name.removeprefix("./")
        for member in bundle.getmembers()
        if member.isfile()
    }
    resource_prefix = "package/ios/Resources/"
    actual_bundles = {
        name.removeprefix(resource_prefix).split("/", 1)[0]
        for name in member_names
        if name.startswith(resource_prefix)
        and ".bundle/" in name.removeprefix(resource_prefix)
    }
    if actual_bundles != MLX_GENERATED_BUNDLE_NAMES:
        raise PackageValidationError(
            f"{archive.name}: MLX app-root resource bundles must be exactly "
            f"{sorted(MLX_GENERATED_BUNDLE_NAMES)}, found {sorted(actual_bundles)}"
        )
    for resource in MLX_RESOURCE_FILES:
        _required_file_bytes(archive, bundle, resource, "MLX runtime resource")
    notice_prefix = "package/ios/ThirdPartyNotices/"
    notices = sorted(name for name in member_names if name.startswith(notice_prefix))
    if not notices:
        raise PackageValidationError(
            f"{archive.name}: MLX runtime third-party notices are missing"
        )
    for notice in notices:
        _required_file_bytes(archive, bundle, notice, "MLX third-party notice")
    if any(
        obsolete.casefold() in member.casefold()
        for obsolete in MLX_OBSOLETE_METAL_BUNDLES
        for member in member_names
    ):
        raise PackageValidationError(
            f"{archive.name}: obsolete platform Metal sidecar bundle is not publishable"
        )

    podspec = _required_file_bytes(
        archive, bundle, MLX_PODSPEC_PATH, "RunAnywhereMLX podspec"
    )
    required_markers = (
        b"RABackendMLX.xcframework",
        b"RunAnywhereMLXRuntime.xcframework",
        b"RunAnywhereMLXMetal.xcframework",
        b"ios/Resources/swift-crypto_Crypto.bundle",
        b"ios/Resources/swift-transformers_Hub.bundle",
        b's.homepage      = "https://runanywhere.ai"',
        b's.license       = { type: "RunAnywhere License", file: "LICENSE" }',
        b's.swift_version = "6.2"',
        b'"Accelerate", "AVFoundation", "CoreGraphics", "CoreImage", "CoreML"',
        b'"Foundation", "Metal", "MetalKit", "NaturalLanguage", "UIKit"',
        b's.libraries = "c++"',
        b"s.user_target_xcconfig",
        b"-Wl,-u,_ra_mlx_runtime_is_available",
    )
    missing_markers = [
        marker.decode() for marker in required_markers if marker not in podspec
    ]
    if missing_markers:
        raise PackageValidationError(
            f"{archive.name}: MLX podspec is missing required wiring {missing_markers}"
        )
    forbidden_markers = (
        b"ios/Resources/*.bundle",
        b"RunAnywhereMLXMetalDevice.bundle",
        b"RunAnywhereMLXMetalSimulator.bundle",
        b"-all_load",
        b"-force_load",
    )
    present_forbidden = [
        marker.decode() for marker in forbidden_markers if marker in podspec
    ]
    if present_forbidden:
        raise PackageValidationError(
            f"{archive.name}: MLX podspec contains broad or obsolete wiring "
            f"{present_forbidden}"
        )


def _archive_contents(
    archive: Path,
) -> tuple[
    str,
    dict[str, object],
    dict[str, str],
    dict[str, str],
    dict[str, str],
    str | None,
]:
    with tarfile.open(archive, "r:gz") as bundle:
        _validate_archive_members(archive, bundle)
        try:
            package_json = bundle.extractfile("package/package.json")
        except KeyError as error:
            raise PackageValidationError(
                f"{archive.name}: missing package/package.json"
            ) from error
        if package_json is None:
            raise PackageValidationError(
                f"{archive.name}: package/package.json is not a file"
            )
        metadata = json.load(package_json)
        if not isinstance(metadata, dict):
            raise PackageValidationError(
                f"{archive.name}: package metadata is not an object"
            )
        name = metadata.get("name")
        if not isinstance(name, str) or not name:
            raise PackageValidationError(f"{archive.name}: package name is missing")
        if name in EXPECTED_PACKAGES:
            if metadata.get("license") != "SEE LICENSE IN LICENSE":
                raise PackageValidationError(
                    f"{archive.name}: package license metadata must be "
                    "'SEE LICENSE IN LICENSE'"
                )
            _validate_public_package_license(archive, bundle, name)
        if name == MLX_PACKAGE:
            _validate_mlx_package(archive, bundle)
        header_hashes = (
            _file_hashes(bundle, CORE_HEADER_PREFIX) if name == CORE_PACKAGE else {}
        )
        bundled_proto_hashes = _file_hashes(bundle, BUNDLED_PROTO_PREFIX)
        privacy_manifest_hashes: dict[str, str] = {}
        for member in bundle.getmembers():
            member_name = member.name.removeprefix("./")
            if not member.isfile() or not member_name.endswith(
                "/PrivacyInfo.xcprivacy"
            ):
                continue
            source = bundle.extractfile(member)
            if source is None:
                raise PackageValidationError(
                    f"cannot read archive member {member_name}"
                )
            privacy_manifest_hashes[member_name.removeprefix("package/")] = (
                hashlib.sha256(source.read()).hexdigest()
            )
        podspec_bytes = _file_bytes(bundle, CORE_PODSPEC_PATH)
        core_podspec = (
            podspec_bytes.decode("utf-8") if podspec_bytes is not None else None
        )
    return (
        name,
        metadata,
        header_hashes,
        bundled_proto_hashes,
        privacy_manifest_hashes,
        core_podspec,
    )


def _proto_archive_hashes(proto_archive: Path) -> dict[str, str]:
    if not proto_archive.is_file():
        raise PackageValidationError(
            f"proto-ts package archive is missing: {proto_archive}"
        )
    with tarfile.open(proto_archive, "r:gz") as bundle:
        hashes = _file_hashes(bundle, "package/")
    if "package.json" not in hashes:
        raise PackageValidationError(
            f"{proto_archive.name}: missing package/package.json"
        )
    return hashes


def _workspace_protocol_specs(
    value: object, path: str = "package"
) -> list[tuple[str, str]]:
    matches: list[tuple[str, str]] = []
    if isinstance(value, dict):
        for key, nested in value.items():
            matches.extend(_workspace_protocol_specs(nested, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            matches.extend(_workspace_protocol_specs(nested, f"{path}[{index}]"))
    elif isinstance(value, str) and value.startswith("workspace:"):
        matches.append((path, value))
    return matches


def _validate_manifest(
    archive: Path,
    name: str,
    metadata: dict[str, object],
    expected_version: str | None,
) -> str:
    version = metadata.get("version")
    if not isinstance(version, str) or not version:
        raise PackageValidationError(f"{archive.name}: package version is missing")
    if expected_version is not None and version != expected_version:
        raise PackageValidationError(
            f"{archive.name}: package version {version!r} does not match {expected_version!r}"
        )

    workspace_specs = _workspace_protocol_specs(metadata)
    if workspace_specs:
        path, spec = workspace_specs[0]
        raise PackageValidationError(
            f"{archive.name}: workspace protocol is not publishable at {path}: {spec}"
        )

    dependencies = metadata.get("dependencies", {})
    if not isinstance(dependencies, dict):
        raise PackageValidationError(f"{archive.name}: dependencies must be an object")
    for dependency in EXPECTED_EXACT_RUNTIME_DEPENDENCIES.get(name, set()):
        actual_spec = dependencies.get(dependency)
        if actual_spec != version:
            raise PackageValidationError(
                f"{archive.name}: {dependency} must use exact release version {version!r}, "
                f"found {actual_spec!r}"
            )
    # Unknown/private entries are validated with the historical proto-bearing
    # shape and rejected by the exact package-set gate below. Only MLX is the
    # intentionally protocol-free public package.
    expects_bundled_proto = name != MLX_PACKAGE
    if expects_bundled_proto:
        for dependency, expected_spec in PROTO_RUNTIME_DEPENDENCIES.items():
            if dependencies.get(dependency) != expected_spec:
                raise PackageValidationError(
                    f"{archive.name}: bundled proto runtime dependency {dependency} "
                    f"must use {expected_spec!r}, found {dependencies.get(dependency)!r}"
                )
    elif name == MLX_PACKAGE and any(
        dependency in dependencies
        for dependency in (BUNDLED_PROTO, *PROTO_RUNTIME_DEPENDENCIES)
    ):
        raise PackageValidationError(
            f"{archive.name}: registration-only MLX package must not declare unused "
            "proto runtime dependencies"
        )

    bundled_dependencies = metadata.get("bundledDependencies")
    expected_bundled_dependencies = [BUNDLED_PROTO] if expects_bundled_proto else None
    if bundled_dependencies != expected_bundled_dependencies:
        raise PackageValidationError(
            f"{archive.name}: bundledDependencies must be "
            f"{expected_bundled_dependencies!r}, "
            f"found {bundled_dependencies!r}"
        )
    return version


def _assert_matching_inventory(
    archive: Path,
    label: str,
    actual: dict[str, str],
    expected: dict[str, str],
) -> None:
    if actual == expected:
        return
    missing = sorted(expected.keys() - actual.keys())
    unexpected = sorted(actual.keys() - expected.keys())
    mismatched = sorted(
        path
        for path in expected.keys() & actual.keys()
        if expected[path] != actual[path]
    )
    raise PackageValidationError(
        f"{archive.name}: {label} inventory mismatch: "
        f"missing={missing}, unexpected={unexpected}, mismatched={mismatched}"
    )


def validate_public_packages(
    dist_dir: Path,
    rac_headers: Path,
    proto_archive: Path,
    privacy_manifest: Path,
    expected_version: str | None = None,
) -> None:
    if not rac_headers.is_dir():
        raise PackageValidationError(
            f"public RAC header directory is missing: {rac_headers}"
        )
    expected_proto_hashes = _proto_archive_hashes(proto_archive)
    if not privacy_manifest.is_file():
        raise PackageValidationError(
            f"canonical Apple privacy manifest is missing: {privacy_manifest}"
        )
    expected_privacy_hashes = {
        PRIVACY_MANIFEST_RELATIVE_PATH: hashlib.sha256(
            privacy_manifest.read_bytes()
        ).hexdigest()
    }

    packages: dict[
        str,
        tuple[
            Path,
            dict[str, object],
            dict[str, str],
            dict[str, str],
            dict[str, str],
            str | None,
        ],
    ] = {}
    package_versions: set[str] = set()
    for archive in sorted(dist_dir.glob("*.tgz")):
        (
            name,
            metadata,
            header_hashes,
            proto_hashes,
            privacy_hashes,
            core_podspec,
        ) = _archive_contents(archive)
        if name in packages:
            raise PackageValidationError(f"duplicate public package {name}")
        package_versions.add(
            _validate_manifest(archive, name, metadata, expected_version)
        )
        expected_package_proto_hashes = (
            expected_proto_hashes if name != MLX_PACKAGE else {}
        )
        _assert_matching_inventory(
            archive, "bundled proto-ts", proto_hashes, expected_package_proto_hashes
        )
        if name == CORE_PACKAGE:
            expected_privacy = expected_privacy_hashes
        elif name == MLX_PACKAGE:
            expected_privacy = {
                MLX_PRIVACY_MANIFEST_RELATIVE_PATH: privacy_hashes[
                    MLX_PRIVACY_MANIFEST_RELATIVE_PATH
                ]
            }
        else:
            expected_privacy = {}
        _assert_matching_inventory(
            archive, "Apple privacy manifest", privacy_hashes, expected_privacy
        )
        if name == CORE_PACKAGE and (
            core_podspec is None
            or "s.resource_bundles" not in core_podspec
            or CORE_PRIVACY_RESOURCE_MARKER not in core_podspec
        ):
            raise PackageValidationError(
                f"{archive.name}: RunAnywhereCore.podspec does not wire "
                f"{PRIVACY_MANIFEST_RELATIVE_PATH} as the core privacy resource bundle"
            )
        packages[name] = (
            archive,
            metadata,
            header_hashes,
            proto_hashes,
            privacy_hashes,
            core_podspec,
        )

    actual = set(packages)
    if actual != EXPECTED_PACKAGES:
        missing = sorted(EXPECTED_PACKAGES - actual)
        unexpected = sorted(actual - EXPECTED_PACKAGES)
        raise PackageValidationError(
            f"public package set mismatch: missing={missing}, unexpected={unexpected}"
        )
    if len(package_versions) != 1:
        raise PackageValidationError(
            f"public packages do not share one release version: {sorted(package_versions)}"
        )

    expected_headers = {
        header.relative_to(rac_headers).as_posix(): hashlib.sha256(
            header.read_bytes()
        ).hexdigest()
        for header in rac_headers.rglob("*")
        if header.is_file()
    }
    core_archive, _, actual_headers, _, _, _ = packages[CORE_PACKAGE]
    _assert_matching_inventory(
        core_archive, "RAC header", actual_headers, expected_headers
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dist", required=True, type=Path)
    parser.add_argument("--rac-headers", required=True, type=Path)
    parser.add_argument("--proto-archive", required=True, type=Path)
    parser.add_argument("--privacy-manifest", required=True, type=Path)
    parser.add_argument("--expected-version")
    args = parser.parse_args()
    try:
        validate_public_packages(
            args.dist,
            args.rac_headers,
            args.proto_archive,
            args.privacy_manifest,
            args.expected_version,
        )
    except (PackageValidationError, json.JSONDecodeError, tarfile.TarError) as error:
        print(f"ERROR: {error}")
        return 1
    print(
        "Validated the exact public RN package set, bundled proto-ts payloads, "
        "dependency versions, RAC headers, and the canonical Apple privacy manifest."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
