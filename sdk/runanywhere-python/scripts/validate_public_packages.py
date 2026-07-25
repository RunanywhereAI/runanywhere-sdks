#!/usr/bin/env python3
"""Validate the built Python wheel + sdist for the ``runanywhere`` package.

A published wheel must be self-contained and free of any host-machine build path. This
inspects a built ``*.whl`` (a ZIP) and its companion ``*.tar.gz`` sdist and asserts:

* the wheel carries the ``runanywhere/`` package, the compiled ``runanywhere/_native/_core``
  extension, and a ``*.dist-info/METADATA`` whose ``Version`` matches the expected release;
* the platform's vendored sidecar runtime libraries (onnxruntime / sherpa) are all present in
  the wheel-repair tool's output dir (``runanywhere.libs`` for delvewheel/auditwheel,
  ``runanywhere/.dylibs`` for delocate) — plus the CUDA libraries when ``--gpu`` is given;
* no TEXT / metadata wheel member (our ``.py`` sources, ``METADATA``, ``RECORD``, ``WHEEL``)
  leaks an absolute host build path (``/Users/``, ``/home/``, ``\\Users\\``). Compiled
  binaries are NOT scanned: a native extension and its vendored deps unavoidably embed
  build-env source paths, and CI runner workspaces live under ``/home/`` / ``/Users/``;
* the sdist expands under a single ``runanywhere-<version>/`` prefix, ships
  ``pyproject.toml`` + ``native/`` + ``runanywhere/``, and contains NO compiled binary
  (``.pyd`` / ``.so`` / ``.dylib`` / ``.dll``).

Mirrors ``runanywhere-web/scripts/validate_public_packages.py`` and
``runanywhere-kotlin/scripts/validate_public_artifacts.py``.
"""

from __future__ import annotations

import argparse
import posixpath
import re
import sys
import tarfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath


# Absolute host build paths must never survive into a published binary. delvewheel /
# auditwheel / delocate do not rewrite string literals, so a leaked path would ship verbatim.
HOST_PATH_MARKERS: tuple[bytes, ...] = (b"/Users/", b"/home/", b"\\Users\\")

# Compiled-binary suffixes that belong in the wheel but must NEVER appear in the sdist.
BINARY_SUFFIXES: tuple[str, ...] = (".pyd", ".so", ".dylib", ".dll")

# The compiled extension is imported as ``runanywhere._native._core``; its file is named
# ``_core`` with a platform extension suffix (``_core.cp312-win_amd64.pyd`` / ``_core.so`` /
# ``_core.*.dylib``). Match the stem so the check is interpreter/platform independent.
CORE_STEM = "_core"
CORE_DIR = "runanywhere/_native"

VERSION_FIELD = re.compile(rb"^Version:\s*(.+?)\s*$", re.MULTILINE)


@dataclass(frozen=True)
class PlatformLibs:
    """The vendored sidecar runtime libraries for one wheel platform tag.

    ``libs_dir`` is where the wheel-repair tool places relocated sidecars relative to the
    wheel root: a top-level ``runanywhere.libs`` for delvewheel (Windows) and auditwheel
    (Linux), and ``runanywhere/.dylibs`` for delocate (macOS). ``base`` are the third-party
    runtime libraries; ``gpu`` are the extra CUDA libraries added by ``--gpu``. Matching is by
    filename stem prefix because the repair tools mangle names (e.g. a hash suffix on Linux).
    """

    libs_dir: str
    base: tuple[str, ...]
    gpu: tuple[str, ...] = field(default_factory=tuple)


# The runtime sidecars mirror the Electron native bundle (bundle-native.js): onnxruntime, its
# providers stub, and the sherpa C-API. The GPU set mirrors the Electron CUDA prebuild.
PLATFORMS: dict[str, PlatformLibs] = {
    # delvewheel vendors into a top-level `runanywhere.libs/` (sibling of the package) and
    # patches __init__ to load it — same convention auditwheel uses on Linux.
    "win": PlatformLibs(
        libs_dir="runanywhere.libs",
        base=("onnxruntime", "sherpa-onnx-c-api"),
        gpu=("cudart64_12", "cublas64_12", "cublasLt64_12"),
    ),
    "linux": PlatformLibs(
        libs_dir="runanywhere.libs",
        base=("libonnxruntime", "libsherpa-onnx-c-api"),
        gpu=("libcudart", "libcublas", "libcublasLt"),
    ),
    # delocate vendors into `<package>/.dylibs/`. On macOS sherpa/onnxruntime are built as STATIC
    # archives (.a) and linked into _core, so there are no runtime sidecar dylibs to vendor — the
    # wheel is self-contained. base is therefore empty (delocate finds nothing to relocate).
    "macos": PlatformLibs(
        libs_dir="runanywhere/.dylibs",
        base=(),
        gpu=("libcudart", "libcublas", "libcublasLt"),
    ),
}


class PackageValidationError(RuntimeError):
    """Raised when a built Python wheel or sdist is missing, malformed, or unsafe."""


def _reject_unsafe_name(label: str, name: str) -> str:
    """Reject archive traversal / absolute entries and return the POSIX-normalized name."""
    normalized = name.replace("\\", "/").removeprefix("./")
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts:
        raise PackageValidationError(f"{label}: unsafe archive entry {name!r}")
    return normalized


def _platform_of(wheel_name: str) -> PlatformLibs:
    """Pick the sidecar inventory from the wheel's platform tag (``...-<py>-<abi>-<plat>``)."""
    lowered = wheel_name.casefold()
    if "win" in lowered:
        return PLATFORMS["win"]
    if "macosx" in lowered or "darwin" in lowered:
        return PLATFORMS["macos"]
    if "linux" in lowered:
        return PLATFORMS["linux"]
    raise PackageValidationError(
        f"{wheel_name}: cannot determine platform from wheel tag"
    )


def _metadata_version(label: str, payload: bytes) -> str:
    """Extract the ``Version:`` field from a ``dist-info/METADATA`` payload."""
    match = VERSION_FIELD.search(payload)
    if match is None:
        raise PackageValidationError(f"{label}: METADATA has no Version field")
    return match.group(1).decode("utf-8", "replace")


def _basename_stem(name: str) -> str:
    """Filename with directories and the first extension dot onward stripped.

    ``onnxruntime.dll`` -> ``onnxruntime``; ``libonnxruntime-abc123.so.1`` -> ``libonnxruntime``.
    """
    base = posixpath.basename(name)
    return base.split(".", 1)[0]


def validate_wheel(wheel: Path, expected_version: str, *, gpu: bool = False) -> None:
    """Validate one built wheel: layout, version, sidecar inventory, and host-path leaks."""
    label = wheel.name
    platform = _platform_of(label)
    try:
        with zipfile.ZipFile(wheel) as archive:
            names = [_reject_unsafe_name(label, m.filename) for m in archive.infolist()]
            name_set = set(names)

            if not any(n == "runanywhere/__init__.py" for n in names):
                raise PackageValidationError(f"{label}: wheel is missing runanywhere/ package")

            core_members = [
                n
                for n in names
                if posixpath.dirname(n) == CORE_DIR
                and _basename_stem(n) == CORE_STEM
                and n.casefold().endswith(BINARY_SUFFIXES)
            ]
            if not core_members:
                raise PackageValidationError(
                    f"{label}: wheel is missing the compiled {CORE_DIR}/{CORE_STEM}* extension"
                )

            metadata_members = [
                n
                for n in names
                if n.endswith(".dist-info/METADATA")
                and n.count("/") == 1
            ]
            if len(metadata_members) != 1:
                raise PackageValidationError(
                    f"{label}: expected exactly one *.dist-info/METADATA, "
                    f"found {sorted(metadata_members)}"
                )
            version = _metadata_version(label, archive.read(metadata_members[0]))
            if version != expected_version:
                raise PackageValidationError(
                    f"{label}: METADATA version {version!r} does not match "
                    f"{expected_version!r}"
                )

            expected_libs = platform.base + (platform.gpu if gpu else ())
            present_stems = {
                _basename_stem(n)
                for n in names
                if posixpath.dirname(n) == platform.libs_dir
                and n.casefold().endswith(BINARY_SUFFIXES)
            }
            # Repair tools mangle a hash into the name (onnxruntime -> onnxruntime-a1b2c3),
            # so match a stem that equals the expected lib or begins with "<lib>-".
            missing = sorted(
                lib
                for lib in expected_libs
                if not any(s == lib or s.startswith(f"{lib}-") for s in present_stems)
            )
            if missing:
                raise PackageValidationError(
                    f"{label}: vendored sidecar libraries missing from "
                    f"{platform.libs_dir}/: {missing}"
                )

            for member_name in names:
                if member_name.endswith("/"):
                    continue
                # Skip compiled binaries: our _core and the vendored onnxruntime/sherpa libs
                # unavoidably embed build-env source paths (llama/absl/ggml __FILE__ strings),
                # and CI runner workspaces themselves live under /home/ or /Users/ — so scanning
                # binaries yields only false positives. A host path in a TEXT / metadata member
                # (our .py sources, METADATA, RECORD, WHEEL) IS an avoidable leak and is rejected.
                if member_name.casefold().endswith(BINARY_SUFFIXES):
                    continue
                payload = archive.read(member_name)
                if any(marker in payload for marker in HOST_PATH_MARKERS):
                    raise PackageValidationError(
                        f"{label}: member {member_name} leaks an absolute host build path"
                    )
            _ = name_set
    except zipfile.BadZipFile as error:
        raise PackageValidationError(f"{label}: invalid wheel ZIP") from error


def validate_sdist(sdist: Path, expected_version: str) -> None:
    """Validate one sdist: single versioned prefix, required tree, and no compiled binary."""
    label = sdist.name
    expected_prefix = f"runanywhere-{expected_version}"
    try:
        with tarfile.open(sdist, "r:gz") as bundle:
            members = bundle.getmembers()
            if not members:
                raise PackageValidationError(f"{label}: sdist is empty")

            relative_paths: list[str] = []
            prefixes: set[str] = set()
            for member in members:
                normalized = _reject_unsafe_name(label, member.name)
                if not member.isfile() and not member.isdir():
                    raise PackageValidationError(
                        f"{label}: links/special entries are not publishable: {member.name}"
                    )
                parts = PurePosixPath(normalized).parts
                if not parts:
                    continue
                prefixes.add(parts[0])
                relative = "/".join(parts[1:])
                if relative:
                    relative_paths.append(relative)

            if prefixes != {expected_prefix}:
                raise PackageValidationError(
                    f"{label}: sdist must have a single {expected_prefix}/ prefix, "
                    f"found {sorted(prefixes)}"
                )

            required_roots = ("pyproject.toml", "native/", "runanywhere/")
            for required in required_roots:
                if required.endswith("/"):
                    present = any(p == required.rstrip("/") or p.startswith(required)
                                  for p in relative_paths)
                else:
                    present = any(p == required for p in relative_paths)
                if not present:
                    raise PackageValidationError(
                        f"{label}: sdist is missing required entry {required!r}"
                    )

            for relative in relative_paths:
                if relative.casefold().endswith(BINARY_SUFFIXES):
                    raise PackageValidationError(
                        f"{label}: sdist must not contain compiled binaries: {relative}"
                    )
    except tarfile.TarError as error:
        raise PackageValidationError(f"{label}: invalid sdist tarball") from error


def validate_public_packages(dist_dir: Path, expected_version: str, *, gpu: bool = False) -> None:
    """Validate the wheel(s) + sdist in ``dist_dir`` against ``expected_version``."""
    if not dist_dir.is_dir():
        raise PackageValidationError(f"distribution directory is missing: {dist_dir}")

    wheels = sorted(dist_dir.glob("*.whl"))
    sdists = sorted(dist_dir.glob("*.tar.gz"))
    if not wheels:
        raise PackageValidationError(f"no wheel (*.whl) found in {dist_dir}")
    if len(sdists) != 1:
        raise PackageValidationError(
            f"expected exactly one sdist (*.tar.gz) in {dist_dir}, found {len(sdists)}"
        )

    for wheel in wheels:
        validate_wheel(wheel, expected_version, gpu=gpu)
    validate_sdist(sdists[0], expected_version)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dist", required=True, type=Path)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument(
        "--gpu",
        action="store_true",
        help="also require the vendored CUDA sidecar libraries",
    )
    args = parser.parse_args(argv)
    try:
        validate_public_packages(args.dist, args.expected_version, gpu=args.gpu)
    except (PackageValidationError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "Validated the runanywhere wheel (package + _core + sidecar libs, no host-path "
        "leak) and sdist (single prefix, sources only)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
