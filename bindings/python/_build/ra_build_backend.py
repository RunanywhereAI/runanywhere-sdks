"""In-tree PEP 517 build backend: run IDL codegen, then hand off to scikit-build-core.

WHY THIS EXISTS
---------------
Three files/trees under ``runanywhere/`` are IDL codegen output and are no longer
tracked by git:

    runanywhere/_proto/                 (protobuf modules for the RAG surface)
    runanywhere/_generated_errors.py    (ErrorCode / ErrorCategory)
    runanywhere/_generated_defaults.py  (default-pool constants)

``pyproject.toml`` had no codegen hook at all, and the failure mode is uniquely
nasty here: nothing in the *build* touches these modules, so a wheel built
without them compiles, links, packages, uploads and installs perfectly. The
error appears the first time a user calls ``import runanywhere`` — an
``ImportError`` from a released artifact.

WHERE IT RUNS
-------------
There are two distinct build contexts and this backend must behave differently
in each:

1. **In the monorepo.** ``idl/*.proto`` is four directories up, so codegen can
   run. This is where the sdist is built, and it is the only chance to get the
   generated modules into the archive.

2. **From an unpacked sdist.** ``[tool.scikit-build.sdist]`` scopes the archive
   to ``runanywhere/`` + ``native/``, so ``idl/`` is *not* in it — codegen
   cannot run and must not be attempted. cibuildwheel builds every wheel from
   that sdist, so the generated modules have to already be inside it.

Hence: generate when ``idl/`` is reachable; otherwise verify the files are
present and fail loudly (at build time, where it is cheap) if they are not.

Only the three Python generators are invoked, not ``generate_all.sh`` — a
``pip install`` must not require the Swift, Kotlin, Dart and TypeScript
toolchains.

Set ``RA_FORCE_CODEGEN=1`` to regenerate even when the outputs already exist.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

# Re-export every hook scikit-build-core provides, then override the ones that
# produce artifacts. `import *` would miss hooks added by a future release, so
# delegate by module attribute instead.
from scikit_build_core import build as _skb

_HERE = Path(__file__).resolve().parent          # bindings/python/_build
_PKG_ROOT = _HERE.parent                          # bindings/python
_REPO_ROOT = _PKG_ROOT.parent.parent              # repo root (monorepo only)

_PACKAGE = _PKG_ROOT / "runanywhere"
_REQUIRED = (
    _PACKAGE / "_proto" / "__init__.py",
    _PACKAGE / "_generated_errors.py",
    _PACKAGE / "_generated_defaults.py",
)

_CODEGEN_DIR = _REPO_ROOT / "idl" / "codegen"


def _outputs_present() -> bool:
    return all(p.exists() for p in _REQUIRED)


def _run(cmd: list[str], what: str, env: dict | None = None) -> None:
    print(f"[runanywhere-build] {what}: {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, cwd=_REPO_ROOT, check=True, env=env)


def _missing_tools() -> list[str]:
    """Host tools the generators shell out to, which pip cannot provide.

    ``[build-system] requires`` deliberately does NOT list these: the wheel
    built from an sdist needs no codegen at all, so making every build pull
    grpcio-tools would be pure cost, and ``protoc`` is not a Python package in
    the first place (grpc_tools bundles it as a module, not a binary, while
    _convenience_common.build_descriptor_set invokes the real executable).
    """
    missing = []
    if not shutil.which("protoc"):
        missing.append("protoc (see core/VERSIONS::PROTOC_VERSION)")
    try:
        import google.protobuf  # noqa: F401
    except ImportError:
        missing.append("protobuf (pip install 'protobuf>=6.33,<7')")
    try:
        import grpc_tools.protoc  # noqa: F401
    except ImportError:
        missing.append("grpcio-tools (pip install 'grpcio-tools==1.71.*')")
    return missing


def _generate() -> None:
    """Run the three Python-facing IDL generators."""
    missing = _missing_tools()
    if missing:
        raise SystemExit(
            "[runanywhere-build] cannot generate the IDL bindings; missing:\n  "
            + "\n  ".join(missing)
            + "\n\nEither install those, or generate once up front and rebuild:\n"
            "  ./scripts/setup/setup-toolchain.sh\n"
            "  ./idl/codegen/generate_all.sh --only python\n"
            "(CI does the latter via .github/actions/generate-idl.)"
        )

    env = dict(os.environ)
    # generate_python.sh resolves `python3` from PATH by default; point it at
    # the interpreter running this backend so an isolated build environment
    # with grpcio-tools installed is the one that gets used.
    env.setdefault("PYTHON_BIN", sys.executable)
    _run(["bash", str(_CODEGEN_DIR / "generate_python.sh")], "protobuf modules", env)
    _run([sys.executable, str(_CODEGEN_DIR / "generate_python_errors.py")], "error enums", env)
    _run([sys.executable, str(_CODEGEN_DIR / "generate_defaults_pool.py")], "default pool", env)


def _ensure_generated() -> None:
    force = os.environ.get("RA_FORCE_CODEGEN") == "1"

    if _CODEGEN_DIR.is_dir():
        if force or not _outputs_present():
            _generate()
        else:
            print(
                "[runanywhere-build] generated modules already present; "
                "set RA_FORCE_CODEGEN=1 to regenerate",
                flush=True,
            )

    missing = [p for p in _REQUIRED if not p.exists()]
    if missing:
        rel = "\n  ".join(str(p.relative_to(_PKG_ROOT)) for p in missing)
        raise SystemExit(
            "[runanywhere-build] generated modules are missing and cannot be "
            "produced here:\n  " + rel + "\n\n"
            "These are IDL codegen output (untracked by design). Inside the "
            "monorepo run:\n"
            "  ./idl/codegen/generate_all.sh\n"
            "If you are building from an sdist, that sdist was produced without "
            "codegen and is broken — rebuild it from the monorepo."
        )


# --- PEP 517 surface --------------------------------------------------------
# Hooks that create an artifact run codegen first. Metadata-only and
# requirement-query hooks are passed straight through: they are called by pip
# during resolution, long before a build environment exists, and running codegen
# there would be both wasteful and fragile.

def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    _ensure_generated()
    return _skb.build_wheel(wheel_directory, config_settings, metadata_directory)


def build_sdist(sdist_directory, config_settings=None):
    _ensure_generated()
    return _skb.build_sdist(sdist_directory, config_settings)


def build_editable(wheel_directory, config_settings=None, metadata_directory=None):
    _ensure_generated()
    return _skb.build_editable(wheel_directory, config_settings, metadata_directory)


def get_requires_for_build_wheel(config_settings=None):
    return _skb.get_requires_for_build_wheel(config_settings)


def get_requires_for_build_sdist(config_settings=None):
    return _skb.get_requires_for_build_sdist(config_settings)


def get_requires_for_build_editable(config_settings=None):
    return _skb.get_requires_for_build_editable(config_settings)


def prepare_metadata_for_build_wheel(metadata_directory, config_settings=None):
    return _skb.prepare_metadata_for_build_wheel(metadata_directory, config_settings)


def prepare_metadata_for_build_editable(metadata_directory, config_settings=None):
    return _skb.prepare_metadata_for_build_editable(metadata_directory, config_settings)
