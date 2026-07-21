#!/usr/bin/env python3
"""Unit tests for ``validate_public_packages`` using synthetic in-memory wheels/sdists.

Uses stdlib ``unittest`` (no pytest) so it runs standalone via ``python3 <file>`` in the CI
``validation`` job, exactly like the sibling SDK validator self-tests. Each case assembles a
minimal but structurally faithful wheel (a ZIP with ``runanywhere/``, a compiled ``_core``
stub, ``*.dist-info/METADATA``, and the wheel-repair tool's vendored ``runanywhere.libs/``
sidecars with hash-mangled names) and sdist (a ``.tar.gz`` under a single
``runanywhere-<version>/`` prefix). The good bundle must pass; the host-path-leak /
missing-sidecar / binary-in-sdist bundles must each be rejected.
"""

from __future__ import annotations

import importlib.util
import io
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path


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
    """The Windows base sidecars delvewheel vendors into ``runanywhere.libs/``.

    Names carry a hash suffix (delvewheel's mangling) so the tests exercise the validator's
    ``<lib>`` / ``<lib>-<hash>`` prefix matching, not just exact names.
    """
    return {
        "runanywhere.libs/onnxruntime-a1b2c3d4.dll": CLEAN_BINARY,
        "runanywhere.libs/sherpa-onnx-c-api-e5f6a7b8.dll": CLEAN_BINARY,
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


class ValidatePublicPackagesTest(unittest.TestCase):
    def _tmp(self) -> Path:
        # A per-test temp dir cleaned up automatically at tearDown (3.9-compatible).
        ctx = tempfile.TemporaryDirectory()
        self.addCleanup(ctx.cleanup)
        return Path(ctx.name)

    # ------------------------------------------------------------------- good
    def test_good_bundle_passes(self) -> None:
        V.validate_public_packages(_write_dist(self._tmp()), VERSION)

    def test_good_bundle_main_returns_zero(self) -> None:
        dist = _write_dist(self._tmp())
        self.assertEqual(V.main(["--dist", str(dist), "--expected-version", VERSION]), 0)

    def test_gpu_flag_requires_cuda_sidecars(self) -> None:
        # Base-only wheel must FAIL under --gpu (CUDA sidecars absent) ...
        dist = _write_dist(self._tmp())
        with self.assertRaises(V.PackageValidationError):
            V.validate_public_packages(dist, VERSION, gpu=True)
        # ... but PASS once the CUDA DLLs are vendored (mangled) into runanywhere.libs.
        gpu_sidecars = _win_sidecars()
        gpu_sidecars.update(
            {
                "runanywhere.libs/cudart64_12-11aa.dll": CLEAN_BINARY,
                "runanywhere.libs/cublas64_12-22bb.dll": CLEAN_BINARY,
                "runanywhere.libs/cublasLt64_12-33cc.dll": CLEAN_BINARY,
            }
        )
        dist2 = _write_dist(self._tmp(), wheel=_build_wheel(sidecars=gpu_sidecars))
        V.validate_public_packages(dist2, VERSION, gpu=True)

    # --------------------------------------------------------- wheel rejections
    def test_host_path_in_binary_is_tolerated(self) -> None:
        # A native extension (and its vendored deps) unavoidably embed build-env source paths,
        # and CI runner workspaces live under /home/ or /Users/, so compiled binaries are NOT
        # scanned for host paths — a build-path string inside _core / a sidecar must not fail.
        leaky = _win_sidecars()
        leaky["runanywhere/_native/_core.cp312-win_amd64.pyd"] = (
            CLEAN_BINARY + b"C:\\Users\\runner\\build\\_core.obj\x00"
        )
        leaky["runanywhere.libs/onnxruntime-a1b2c3d4.dll"] = (
            CLEAN_BINARY + b"/home/runner/work/onnxruntime\x00"
        )
        dist = _write_dist(self._tmp(), wheel=_build_wheel(include_core=False, sidecars=leaky))
        V.validate_public_packages(dist, VERSION)  # must not raise

    def test_host_path_leak_in_text_member_is_rejected(self) -> None:
        # A host path in a TEXT / metadata member (our own source) IS an avoidable leak.
        wheel = _build_wheel(
            extra_members={"runanywhere/_leak.py": b"CACHE = '/home/dev/secret/models'\n"}
        )
        with self.assertRaisesRegex(V.PackageValidationError, "host"):
            V.validate_public_packages(_write_dist(self._tmp(), wheel=wheel), VERSION)

    def test_missing_sidecar_lib_is_rejected(self) -> None:
        partial = _win_sidecars()
        del partial["runanywhere.libs/sherpa-onnx-c-api-e5f6a7b8.dll"]
        with self.assertRaisesRegex(V.PackageValidationError, "sidecar"):
            V.validate_public_packages(
                _write_dist(self._tmp(), wheel=_build_wheel(sidecars=partial)), VERSION
            )

    def test_missing_core_extension_is_rejected(self) -> None:
        with self.assertRaisesRegex(V.PackageValidationError, "_core"):
            V.validate_public_packages(
                _write_dist(self._tmp(), wheel=_build_wheel(include_core=False)), VERSION
            )

    def test_version_mismatch_is_rejected(self) -> None:
        with self.assertRaisesRegex(V.PackageValidationError, "version"):
            V.validate_public_packages(_write_dist(self._tmp()), "9.9.9")

    def test_missing_package_dir_is_rejected(self) -> None:
        members = _win_sidecars()
        members["runanywhere/_native/_core.cp312-win_amd64.pyd"] = CLEAN_BINARY
        members[f"runanywhere-{VERSION}.dist-info/METADATA"] = _metadata()
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for name, payload in members.items():
                archive.writestr(name, payload)
        with self.assertRaisesRegex(V.PackageValidationError, "runanywhere"):
            V.validate_public_packages(
                _write_dist(self._tmp(), wheel=buffer.getvalue()), VERSION
            )

    # --------------------------------------------------------- sdist rejections
    def test_binary_in_sdist_is_rejected(self) -> None:
        sdist = _build_sdist(
            extra_members={
                f"runanywhere-{VERSION}/runanywhere/_native/_core.cp312-win_amd64.pyd": CLEAN_BINARY
            }
        )
        with self.assertRaisesRegex(V.PackageValidationError, "binaries"):
            V.validate_public_packages(_write_dist(self._tmp(), sdist=sdist), VERSION)

    def test_sdist_multiple_prefixes_is_rejected(self) -> None:
        sdist = _build_sdist(extra_members={"stray-0.1/setup.py": b"# stray\n"})
        with self.assertRaisesRegex(V.PackageValidationError, "prefix"):
            V.validate_public_packages(_write_dist(self._tmp(), sdist=sdist), VERSION)

    def test_sdist_missing_pyproject_is_rejected(self) -> None:
        with self.assertRaisesRegex(V.PackageValidationError, "pyproject"):
            V.validate_public_packages(
                _write_dist(self._tmp(), sdist=_build_sdist(include_pyproject=False)), VERSION
            )

    def test_sdist_missing_native_is_rejected(self) -> None:
        with self.assertRaisesRegex(V.PackageValidationError, "native"):
            V.validate_public_packages(
                _write_dist(self._tmp(), sdist=_build_sdist(include_native=False)), VERSION
            )

    def test_sdist_wrong_version_prefix_is_rejected(self) -> None:
        with self.assertRaisesRegex(V.PackageValidationError, "prefix"):
            V.validate_public_packages(
                _write_dist(self._tmp(), sdist=_build_sdist(prefix="runanywhere-0.0.1")), VERSION
            )

    # ---------------------------------------------------------- dist-set errors
    def test_missing_sdist_is_rejected(self) -> None:
        dist = self._tmp() / "dist"
        dist.mkdir()
        (dist / WHEEL_NAME).write_bytes(_build_wheel())
        with self.assertRaisesRegex(V.PackageValidationError, "sdist"):
            V.validate_public_packages(dist, VERSION)

    def test_missing_wheel_is_rejected(self) -> None:
        dist = self._tmp() / "dist"
        dist.mkdir()
        (dist / SDIST_NAME).write_bytes(_build_sdist())
        with self.assertRaisesRegex(V.PackageValidationError, "wheel"):
            V.validate_public_packages(dist, VERSION)


if __name__ == "__main__":
    unittest.main()
