"""Lazy loader for the compiled ``_core`` extension — never imported at package top level.

The pure-Python surface of ``runanywhere`` stays importable (and hermetically testable)
without the native module built. Only :func:`get_core` — called on the first
``RunAnywhere.initialize()`` (and by the model wrappers, via the client) — loads the
compiled ``_core`` extension that lives beside this file. On first call it adds this
directory to the platform DLL search path (so ``onnxruntime.dll`` and the other bundled
runtime DLLs resolve on Windows), honours a ``RUNANYWHERE_NATIVE_PATH`` override, imports
``_core``, caches it, and raises :class:`SDKException` on failure.
"""

from __future__ import annotations

import importlib
import importlib.machinery
import importlib.util
import os
import sys
from types import ModuleType

from ..errors import ErrorCode, ErrorCategory, SDKException

# Cache the loaded extension so the DLL-search-path manipulation + import happens once.
_core: ModuleType | None = None

# The env var that lets a caller point the loader at a native build in a non-default
# directory (e.g. an out-of-tree CMake build) instead of the packaged runanywhere/_native.
_ENV_OVERRIDE = "RUNANYWHERE_NATIVE_PATH"


def _native_dir() -> str:
    """Directory that holds the compiled ``_core`` extension + its bundled runtime DLLs.

    ``RUNANYWHERE_NATIVE_PATH`` overrides the default (this package directory) so a caller
    can load an out-of-tree build without reinstalling.
    """
    override = os.environ.get(_ENV_OVERRIDE)
    if override:
        return os.path.abspath(override)
    return os.path.dirname(os.path.abspath(__file__))


def get_core() -> ModuleType:
    """Load (once) and return the compiled ``_core`` native extension.

    On first call this adds the native directory to the DLL search path (via
    :func:`os.add_dll_directory` on Windows; elsewhere the extension's rpath resolves its
    siblings), imports ``_core`` from that directory, caches it, and returns it. Subsequent
    calls return the cached module. Raises :class:`SDKException` (category IO /
    CONFIGURATION) if the extension is missing or its dependent DLLs cannot be loaded.
    """
    global _core
    if _core is not None:
        return _core

    native_dir = _native_dir()

    # On Windows the packaged runtime DLLs (onnxruntime.dll, the sherpa/llama libs, etc.)
    # sit next to _core; add their directory to the loader search path so the extension's
    # implicit dependencies resolve. Elsewhere we rely on the extension's rpath.
    if sys.platform == "win32" and os.path.isdir(native_dir):
        try:
            os.add_dll_directory(native_dir)
        except (OSError, AttributeError):
            # add_dll_directory can fail on an unusual path; the import below still tries.
            pass

    try:
        _core = _import_core(native_dir)
    except SDKException:
        raise
    except BaseException as exc:  # ImportError / OSError (missing DLL) / anything native
        raise SDKException.of(
            ErrorCode.SERVICE_NOT_AVAILABLE,
            "failed to load the native runanywhere._core extension "
            f"from {native_dir!r} ({exc}); the module may not be built, or a dependent "
            "runtime DLL (e.g. onnxruntime.dll) could not be found",
            category=ErrorCategory.IO,
        ) from exc
    return _core


def _import_core(native_dir: str) -> ModuleType:
    """Import the ``_core`` extension, preferring the one inside ``native_dir``.

    When ``RUNANYWHERE_NATIVE_PATH`` points elsewhere the file may not be importable as the
    package submodule ``runanywhere._native._core``; load it by file path in that case.
    Otherwise import it normally so it caches under ``sys.modules``.
    """
    override = os.environ.get(_ENV_OVERRIDE)
    if not override:
        # Default install layout: _core is a submodule of this package.
        return importlib.import_module("._core", __name__)

    # Explicit override: load the extension file directly from the given directory.
    for ext in _EXTENSION_SUFFIXES:
        candidate = os.path.join(native_dir, "_core" + ext)
        if os.path.isfile(candidate):
            spec = importlib.util.spec_from_file_location("runanywhere._native._core", candidate)
            if spec is None or spec.loader is None:
                break
            module = importlib.util.module_from_spec(spec)
            sys.modules[spec.name] = module
            spec.loader.exec_module(module)
            return module
    # No file matched the override directory — fall back to the normal import so the error
    # message is uniform (raised/caught by get_core()).
    return importlib.import_module("._core", __name__)


# Native extension suffixes to probe for when loading from an explicit override directory
# (e.g. ".cp311-win_amd64.pyd" / ".pyd" on Windows, ".so" on POSIX).
_EXTENSION_SUFFIXES = tuple(importlib.machinery.EXTENSION_SUFFIXES)


__all__ = ["get_core"]
