#!/usr/bin/env python3
"""Unit tests for ``validate_public_packages`` using synthetic in-memory wheels/sdists.

Each case assembles a minimal but structurally faithful wheel (a ZIP with ``runanywhere/``,
a compiled ``_core`` stub, ``*.dist-info/METADATA``, and platform sidecars) and sdist (a
``.tar.gz`` under a single ``runanywhere-<version>/`` prefix). The good bundle must pass; the
host-path-leak / missing-sidecar / binary-in-sdist bundles must each be rejected.
"""

from __future__ import annotations

import importlib.util
import io
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest


def _load_validator():
    """Load the sibling ``validate_public_packages`` module by file path (not on sys.path)."""
    here = Path(__file__).resolve().parent
    module_path = here / "validate_public_packages.py"
    name = "_ra_validate_pkgs"
    spec = importlib.util.spec_from_file_location(name, module_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # Register before exec so @dataclass(frozen=True) can resolve the module in sys.modules.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


V = _load_validator()

VERSION = "0.20.11"
WHEEL_NAME = f"runanywhere-{VERSION}-cp312-cp312-win_amd64.whl"
SDIST_NAME = f"runanywhere-{VERSION}.tar.gz"

# A minimal ELF-ish / PE-ish binary blob; content is irrelevant to the validator except for
# host-path marker scanning, so plain bytes with no marker are "clean".
CLEAN_BINARY = b"\x7fELF" + b"\x00" * 64


def _metadata(version: str = VERSION) -> bytes:
    return (
        "Metadata-Version: 2.1\n"
        "Name: runanywhere\n"
        f"Version: {version}\n"
        "Summary: RunAnywhere SDK\n"
    ).encode("utf-8")


def _win_sidecars() -> dict[str, bytes]:
    """The Windows base sidecar set delvewheel places beside _core (no GPU)."""
    return {
        "runanywhere/_native/onnxruntime.dll": CLEAN_BINARY,
        "runanywhere/_native/onnxruntime_providers_shared.dll": CLEAN_BINARY,
        "runanywhere/_native/sherpa-onnx-c-api.dll": CLEAN_BINARY,
    }


def _build_wheel(
    *,
    version: str = VERSION,
    include_core: bool = True,
    sidecars: dict[str, bytes] | None = None,
    extra_members: dict[str, bytes] | None = None,
) -> bytes:
    """Assemble an in-memory wheel ZIP with the requested members."""
    members: dict[str, bytes] = {
        "runanywhere/__init__.py": b"__version__ = '%b'\n" % version.encode(),
        "runanywhere/_native/__init__.py": b"# lazy loader\n",
        f"runanywhere-{version}.dist-info/METADATA": _metadata(version),
        f"runanywhere-{version}.dist-info/WHEEL": b"Wheel-Version: 1.0\n",
        f"runanywhere-{version}.dist-info/RECORD": b"",
    }
    if include_core:
        members["runanywhere/_native/_core.cp312-win_amd64.pyd"] = CLEAN_BINARY
    members.update(_win_sidecars() if sidecars is None else sidecars)
    if extra_members:
        members.update(extra_members)

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, payload in members.items():
            archive.writestr(name, payload)
    return buffer.getvalue()


def _build_sdist(
    *,
    version: str = VERSION,
    prefix: str | None = None,
    include_pyproject: bool = True,
    include_native: bool = True,
    include_runanywhere: bool = True,
    extra_members: dict[str, bytes] | None = None,
) -> bytes:
    """Assemble an in-memory sdist tarball under a single versioned prefix."""
    root = prefix if prefix is not None else f"runanywhere-{version}"
    members: dict[str, bytes] = {}
    if include_pyproject:
        members[f"{root}/pyproject.toml"] = b"[project]\nname='runanywhere'\n"
    if include_native:
        members[f"{root}/native/CMakeLists.txt"] = b"# native build\n"
        members[f"{root}/native/module.cpp"] = b"// source\n"
    if include_runanywhere:
        members[f"{root}/runanywhere/__init__.py"] = b"# package\n"
        members[f"{root}/runanywhere/client.py"] = b"# client\n"
    members[f"{root}/PKG-INFO"] = _metadata(version)
    if extra_members:
        members.update(extra_members)

    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as bundle:
        for name, payload in members.items():
            info = tarfile.TarInfo(name=name)
            info.size = len(payload)
            bundle.addfile(info, io.BytesIO(payload))
    return buffer.getvalue()


def _write_dist(
    tmp_path: Path, wheel: bytes | None = None, sdist: bytes | None = None
) -> Path:
    """Materialize a dist/ dir with the given wheel + sdist bytes and return its path."""
    dist = tmp_path / "dist"
    dist.mkdir(parents=True)
    (dist / WHEEL_NAME).write_bytes(wheel if wheel is not None else _build_wheel())
    (dist / SDIST_NAME).write_bytes(sdist if sdist is not None else _build_sdist())
    return dist


# --------------------------------------------------------------------------------------- good


def test_good_bundle_passes(tmp_path: Path) -> None:
    dist = _write_dist(tmp_path)
    V.validate_public_packages(dist, VERSION)


def test_good_bundle_main_returns_zero(tmp_path: Path) -> None:
    dist = _write_dist(tmp_path)
    assert V.main(["--dist", str(dist), "--expected-version", VERSION]) == 0


def test_gpu_flag_requires_cuda_sidecars(tmp_path: Path) -> None:
    # Base-only wheel must FAIL under --gpu (CUDA sidecars absent) ...
    dist = _write_dist(tmp_path)
    with pytest.raises(V.PackageValidationError):
        V.validate_public_packages(dist, VERSION, gpu=True)

    # ... but PASS once the CUDA DLLs are vendored beside _core.
    gpu_sidecars = _win_sidecars()
    gpu_sidecars.update(
        {
            "runanywhere/_native/cudart64_12.dll": CLEAN_BINARY,
            "runanywhere/_native/cublas64_12.dll": CLEAN_BINARY,
            "runanywhere/_native/cublasLt64_12.dll": CLEAN_BINARY,
        }
    )
    dist2 = _write_dist(tmp_path / "gpu", wheel=_build_wheel(sidecars=gpu_sidecars))
    V.validate_public_packages(dist2, VERSION, gpu=True)


# ---------------------------------------------------------------------------- wheel rejections


def test_host_path_in_binary_is_tolerated(tmp_path: Path) -> None:
    # A native extension (and its vendored deps) unavoidably embed build-env source paths,
    # and CI runner workspaces live under /home/ or /Users/, so compiled binaries are NOT
    # scanned for host paths — a build-path string inside _core / a sidecar must not fail.
    leaky = _win_sidecars()
    leaky["runanywhere/_native/_core.cp312-win_amd64.pyd"] = (
        CLEAN_BINARY + b"C:\\Users\\runner\\build\\_core.obj\x00"
    )
    leaky["runanywhere/_native/onnxruntime.dll"] = (
        CLEAN_BINARY + b"/home/runner/work/onnxruntime\x00"
    )
    dist = _write_dist(tmp_path, wheel=_build_wheel(include_core=False, sidecars=leaky))
    V.validate_public_packages(dist, VERSION)  # must not raise


def test_host_path_leak_in_text_member_is_rejected(tmp_path: Path) -> None:
    # A host path in a TEXT / metadata member (our own source) IS an avoidable leak.
    wheel = _build_wheel(
        extra_members={"runanywhere/_leak.py": b"CACHE = '/home/dev/secret/models'\n"}
    )
    dist = _write_dist(tmp_path, wheel=wheel)
    with pytest.raises(V.PackageValidationError, match="host"):
        V.validate_public_packages(dist, VERSION)


def test_missing_sidecar_lib_is_rejected(tmp_path: Path) -> None:
    partial = _win_sidecars()
    del partial["runanywhere/_native/sherpa-onnx-c-api.dll"]
    dist = _write_dist(tmp_path, wheel=_build_wheel(sidecars=partial))
    with pytest.raises(V.PackageValidationError, match="sidecar"):
        V.validate_public_packages(dist, VERSION)


def test_missing_core_extension_is_rejected(tmp_path: Path) -> None:
    dist = _write_dist(tmp_path, wheel=_build_wheel(include_core=False))
    with pytest.raises(V.PackageValidationError, match="_core"):
        V.validate_public_packages(dist, VERSION)


def test_version_mismatch_is_rejected(tmp_path: Path) -> None:
    dist = _write_dist(tmp_path, wheel=_build_wheel(version=VERSION))
    with pytest.raises(V.PackageValidationError, match="version"):
        V.validate_public_packages(dist, "9.9.9")


def test_missing_package_dir_is_rejected(tmp_path: Path) -> None:
    # A wheel with the dist-info + sidecars but no runanywhere/__init__.py.
    members = _win_sidecars()
    members["runanywhere/_native/_core.cp312-win_amd64.pyd"] = CLEAN_BINARY
    members[f"runanywhere-{VERSION}.dist-info/METADATA"] = _metadata()
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, payload in members.items():
            archive.writestr(name, payload)
    dist = _write_dist(tmp_path, wheel=buffer.getvalue())
    with pytest.raises(V.PackageValidationError, match="runanywhere"):
        V.validate_public_packages(dist, VERSION)


# ---------------------------------------------------------------------------- sdist rejections


def test_binary_in_sdist_is_rejected(tmp_path: Path) -> None:
    sdist = _build_sdist(
        extra_members={
            f"runanywhere-{VERSION}/runanywhere/_native/_core.cp312-win_amd64.pyd": CLEAN_BINARY
        }
    )
    dist = _write_dist(tmp_path, sdist=sdist)
    with pytest.raises(V.PackageValidationError, match="binaries"):
        V.validate_public_packages(dist, VERSION)


def test_sdist_multiple_prefixes_is_rejected(tmp_path: Path) -> None:
    # Add a stray second top-level prefix beside the versioned one.
    sdist = _build_sdist(extra_members={"stray-0.1/setup.py": b"# stray\n"})
    dist = _write_dist(tmp_path, sdist=sdist)
    with pytest.raises(V.PackageValidationError, match="prefix"):
        V.validate_public_packages(dist, VERSION)


def test_sdist_missing_pyproject_is_rejected(tmp_path: Path) -> None:
    dist = _write_dist(tmp_path, sdist=_build_sdist(include_pyproject=False))
    with pytest.raises(V.PackageValidationError, match="pyproject"):
        V.validate_public_packages(dist, VERSION)


def test_sdist_missing_native_is_rejected(tmp_path: Path) -> None:
    dist = _write_dist(tmp_path, sdist=_build_sdist(include_native=False))
    with pytest.raises(V.PackageValidationError, match="native"):
        V.validate_public_packages(dist, VERSION)


def test_sdist_wrong_version_prefix_is_rejected(tmp_path: Path) -> None:
    # Prefix names a different version than expected.
    sdist = _build_sdist(prefix="runanywhere-0.0.1")
    dist = _write_dist(tmp_path, sdist=sdist)
    with pytest.raises(V.PackageValidationError, match="prefix"):
        V.validate_public_packages(dist, VERSION)


# ----------------------------------------------------------------------------- dist-set errors


def test_missing_sdist_is_rejected(tmp_path: Path) -> None:
    dist = tmp_path / "dist"
    dist.mkdir()
    (dist / WHEEL_NAME).write_bytes(_build_wheel())
    with pytest.raises(V.PackageValidationError, match="sdist"):
        V.validate_public_packages(dist, VERSION)


def test_missing_wheel_is_rejected(tmp_path: Path) -> None:
    dist = tmp_path / "dist"
    dist.mkdir()
    (dist / SDIST_NAME).write_bytes(_build_sdist())
    with pytest.raises(V.PackageValidationError, match="wheel"):
        V.validate_public_packages(dist, VERSION)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
