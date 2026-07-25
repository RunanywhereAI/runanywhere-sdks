#!/usr/bin/env python
"""bundle_native.py — copy the built ``_core`` extension + its sidecar libs into the package.

Python analog of ``runanywhere-electron``'s ``scripts/bundle-native.js``. Copies the
compiled ``_core.{pyd,so,dylib}`` and the platform runtime libraries it dynamically links
(onnxruntime for the ONNX engine, sherpa for STT/TTS) out of the CMake build tree into
``runanywhere/_native/`` so a source checkout / editable install works with no separate
build step. The sidecars must sit beside ``_core`` — Windows resolves an extension's
dependent DLLs from the directory added via ``os.add_dll_directory`` (see
``runanywhere/_native/__init__.py``), and the module's rpath (``$ORIGIN`` / ``@loader_path``)
resolves its POSIX siblings.

Usage::

    python scripts/bundle_native.py [BUILD_DIR] [--gpu]

``BUILD_DIR`` (or the ``RA_NATIVE_DIR`` env var) overrides the source directory; it defaults
to a sensible ``build/*/sdk/runanywhere-python/native/Release`` path. If ``_core`` is not in
the given directory the whole build tree is searched recursively (the ONNX/sherpa sidecars
in particular live under CMake ``_deps/`` rather than beside the module). ``--gpu`` extends
the Windows sidecar set with the CUDA runtime DLLs.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

# ``scripts/`` -> package root ``runanywhere-python/``.
PKG_ROOT = Path(__file__).resolve().parent.parent
# Repo root holds the shared ``build/`` tree (runanywhere-python is one SDK under ``sdk/``).
REPO_ROOT = PKG_ROOT.parent.parent
# Where the packaged extension + sidecars must land (beside _native/__init__.py's loader).
OUT_DIR = PKG_ROOT / "runanywhere" / "_native"

# The compiled extension file, matched by prefix (the real name carries an ABI suffix such
# as ``.cp311-win_amd64.pyd`` / ``.cpython-311-x86_64-linux-gnu.so``).
CORE_STEM = "_core"
CORE_EXTS = (".pyd", ".so", ".dylib")

# Per-platform sidecar runtime libraries the extension dynamically links. Windows names are
# exact; POSIX names are matched as prefixes to catch the versioned ``.so`` / ``.dylib``
# variants (e.g. ``libonnxruntime.so.1.20.0``). ``onnxruntime_providers_shared`` is a 0-byte
# stub on CPU builds but ``onnxruntime`` still imports it, so it must be present.
SIDECARS_WIN = (
    "onnxruntime.dll",
    "onnxruntime_providers_shared.dll",
    "sherpa-onnx-c-api.dll",
)
# CUDA runtime DLLs, added to the Windows set only with --gpu (an onnxruntime CUDA build
# links these directly beside onnxruntime.dll).
SIDECARS_WIN_GPU = (
    "cudart64_12.dll",
    "cublas64_12.dll",
    "cublasLt64_12.dll",
)
# Linux/macOS sidecars are matched as name *prefixes* so versioned suffixes are picked up.
SIDECAR_PREFIXES_LINUX = ("libonnxruntime.so", "libsherpa-onnx-c-api.so")
SIDECAR_PREFIXES_MAC = ("libonnxruntime", "libsherpa-onnx-c-api")


def _default_build_dir() -> Path:
    """The conventional CMake output dir for the Python native module.

    Mirrors the Electron script's ``build/windows-release/sdk/<sdk>/native/Release`` default,
    retargeted to ``runanywhere-python``. If that exact path is absent the caller-facing
    search still finds ``_core`` anywhere under the build tree.
    """
    return (
        REPO_ROOT / "build" / "windows-release" / "sdk"
        / "runanywhere-python" / "native" / "Release"
    )


def _extra_sidecar_roots() -> list[Path]:
    """Prebuilt runtime-lib dirs outside the build tree (sherpa/onnx ship there).

    The sherpa-onnx C API DLL + its version-matched onnxruntime live under
    ``sdk/runanywhere-commons/third_party/sherpa-onnx-<os>/lib`` (downloaded prebuilts),
    not under ``build/``, so the sidecar search must include them.
    """
    tp = REPO_ROOT / "sdk" / "runanywhere-commons" / "third_party"
    roots: list[Path] = []
    for name in ("sherpa-onnx-windows", "sherpa-onnx-linux", "sherpa-onnx-macos"):
        lib = tp / name / "lib"
        if lib.is_dir():
            roots.append(lib)
    return roots


def _build_root(build_dir: Path) -> Path:
    """Return the top-level ``build/`` tree to search recursively from ``build_dir``.

    We want to fall back to searching the whole build tree (the ONNX/sherpa sidecars live
    under CMake ``_deps/`` rather than beside ``_core``). Walk up to the first ancestor named
    ``build``; otherwise search from ``build_dir`` itself.
    """
    for parent in (build_dir, *build_dir.parents):
        if parent.name == "build":
            return parent
    return build_dir


def _find_core(build_dir: Path, search_root: Path) -> Path | None:
    """Locate the compiled ``_core`` extension, preferring ``build_dir`` then the tree."""
    direct = _match_in_dir(build_dir, CORE_STEM, CORE_EXTS)
    if direct is not None:
        return direct
    if search_root.is_dir():
        for candidate in sorted(search_root.rglob("_core*")):
            if candidate.is_file() and candidate.suffix.lower() in CORE_EXTS:
                return candidate
    return None


def _match_in_dir(directory: Path, stem: str, exts: tuple[str, ...]) -> Path | None:
    """Return the first file in ``directory`` whose name is ``stem`` + one of ``exts``."""
    if not directory.is_dir():
        return None
    for entry in sorted(directory.iterdir()):
        if not entry.is_file():
            continue
        name = entry.name
        if name.startswith(stem) and entry.suffix.lower() in exts:
            return entry
    return None


def _find_exact(names: tuple[str, ...], primary: Path, roots: list[Path]) -> dict[str, Path]:
    """Resolve each exact ``name`` in ``primary`` then under each of ``roots`` in order.

    ``roots`` is ordered by preference — the prebuilt sherpa/onnx lib dirs come first so
    the version-matched ``onnxruntime.dll`` wins over an unrelated build-tree copy.
    """
    found: dict[str, Path] = {}
    for name in names:
        candidate = primary / name
        if candidate.is_file():
            found[name] = candidate
            continue
        for root in roots:
            if not root.is_dir():
                continue
            hit = next((h for h in root.rglob(name) if h.is_file()), None)
            if hit is not None:
                found[name] = hit
                break
    return found


def _find_by_prefix(prefixes: tuple[str, ...], primary: Path, roots: list[Path]) -> dict[str, Path]:
    """Resolve sidecars matched by name prefix (versioned POSIX libs), keyed by basename.

    Searches ``primary`` first, then each root in order; the first match per basename wins so a
    given library is copied once even if several copies exist across the roots.
    """
    found: dict[str, Path] = {}
    for prefix in prefixes:
        _collect_prefix(primary, prefix, found, recurse=False)
        for root in roots:
            if root.is_dir():
                _collect_prefix(root, prefix, found, recurse=True)
    return found


def _collect_prefix(base: Path, prefix: str, found: dict[str, Path], *, recurse: bool) -> None:
    """Add files under ``base`` whose basename starts with ``prefix`` to ``found``."""
    if not base.is_dir():
        return
    iterator = base.rglob("*") if recurse else base.iterdir()
    for entry in iterator:
        if entry.is_file() and entry.name.startswith(prefix) and entry.name not in found:
            found[entry.name] = entry


def _sidecar_spec(gpu: bool) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """Return ``(exact_names, prefixes)`` of sidecar libs for the current platform."""
    if sys.platform == "win32":
        exact = SIDECARS_WIN + (SIDECARS_WIN_GPU if gpu else ())
        return exact, ()
    if sys.platform == "darwin":
        return (), SIDECAR_PREFIXES_MAC
    return (), SIDECAR_PREFIXES_LINUX


def _copy(src: Path, dst_dir: Path) -> int:
    """Copy ``src`` into ``dst_dir`` (preserving its name), returning the byte size."""
    dst = dst_dir / src.name
    shutil.copy2(src, dst)
    return dst.stat().st_size


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="bundle_native.py",
        description="Copy the built _core extension + sidecar runtime libs into "
        "runanywhere/_native/ for a source checkout / editable install.",
    )
    parser.add_argument(
        "build_dir",
        nargs="?",
        default=None,
        help="CMake native output dir (default: RA_NATIVE_DIR env, else "
        "build/windows-release/sdk/runanywhere-python/native/Release). If _core is not "
        "there, the whole build tree is searched.",
    )
    parser.add_argument(
        "--gpu",
        action="store_true",
        help="Also bundle the Windows CUDA runtime DLLs (cudart64_12/cublas64_12/"
        "cublasLt64_12).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Bundle the native extension + sidecars; return a process exit code."""
    args = _parse_args(argv)

    build_dir = Path(args.build_dir or os.environ.get("RA_NATIVE_DIR") or _default_build_dir())
    build_dir = build_dir.resolve()
    search_root = _build_root(build_dir)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # The compiled extension is mandatory — without it there is nothing to bundle.
    core = _find_core(build_dir, search_root)
    if core is None:
        sys.stderr.write(
            f"  MISSING: {CORE_STEM}{CORE_EXTS} not found under {build_dir} "
            f"(nor recursively under {search_root})\n"
            "build the module first: configure with -DRAC_BUILD_PYTHON_MODULE=ON and build "
            "the 'runanywhere_core' target, then re-run this script.\n"
        )
        return 1

    copied = 0
    total_bytes = 0

    size = _copy(core, OUT_DIR)
    total_bytes += size
    copied += 1
    print(f"  + {core.name} {size / 1e6:.1f} MB")

    exact_names, prefixes = _sidecar_spec(args.gpu)
    # Prefer the prebuilt sherpa/onnx lib dirs (version-matched runtime DLLs) over the
    # build tree, then fall back to the build tree for anything else.
    sidecar_roots = [*_extra_sidecar_roots(), search_root]
    exact_found = _find_exact(exact_names, core.parent, sidecar_roots)
    prefix_found = _find_by_prefix(prefixes, core.parent, sidecar_roots)

    expected = len(exact_names)  # prefix sidecars are best-effort (versioned/optional)
    for name in exact_names:
        src = exact_found.get(name)
        if src is None:
            sys.stderr.write(f"  MISSING: {name}\n")
            continue
        size = _copy(src, OUT_DIR)
        total_bytes += size
        copied += 1
        print(f"  + {name} {size / 1e6:.1f} MB")

    for name in sorted(prefix_found):
        size = _copy(prefix_found[name], OUT_DIR)
        total_bytes += size
        copied += 1
        print(f"  + {name} {size / 1e6:.1f} MB")

    # Missing sidecars are fatal like the Electron script (it exit(1)s on any missing file):
    # onnxruntime.dll et al. are required at load time, so a partial bundle is a broken one.
    # We count only the exact (Windows) set toward the failure gate; POSIX prefix matches are
    # versioned and treated as best-effort.
    missing = expected - len(exact_found)
    if missing > 0:
        sys.stderr.write(
            f"bundled {copied} file(s) but {missing} required sidecar(s) are missing under "
            f"{search_root} — build the native module (and its ONNX/sherpa deps) first.\n"
        )
        return 1

    print(f"native bundle ({total_bytes / 1e6:.1f} MB) -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
