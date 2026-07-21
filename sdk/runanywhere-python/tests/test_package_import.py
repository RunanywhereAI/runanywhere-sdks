"""Hermetic: ``import runanywhere`` works and exposes its public surface — no native build.

The whole point of the lazy ``_native.get_core()`` loader is that the pure-Python package is
importable without the compiled ``_core`` extension. This test guarantees that: it imports
the top-level package and checks the documented public names resolve, WITHOUT ``_core`` being
built. (Nothing here calls ``initialize()`` / a model wrapper, which is what would actually
trigger the native load.)
"""

from __future__ import annotations

import importlib
import os
import subprocess
import sys

import pytest

# Directory that must be on sys.path for a fresh interpreter to import ``runanywhere``: the
# parent of the package itself, located via find_spec (no import side effects). This works
# for a source checkout AND an installed wheel — and, unlike ``dirname(dirname(__file__))``,
# it stays correct when the CI hermetic step runs this file from a relocated ``tests/`` dir.
_spec = importlib.util.find_spec("runanywhere")
assert _spec is not None and _spec.origin is not None, "runanywhere must be importable"
_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(_spec.origin)))


def _fresh_interpreter(code: str) -> subprocess.CompletedProcess:
    """Run `code` in a fresh interpreter with the package importable.

    The lazy-load invariant is about a clean import, so it must be checked in a new
    process — an in-process check is polluted once any earlier test (e.g. the gated
    smoke suite) has legitimately loaded the compiled ``_core`` into ``sys.modules``.
    """
    # Prepend the package parent while preserving any inherited PYTHONPATH.
    _existing = os.environ.get("PYTHONPATH", "")
    _pythonpath = os.pathsep.join(p for p in (_PKG_PARENT, _existing) if p)
    env = {**os.environ, "PYTHONPATH": _pythonpath}
    return subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True, env=env
    )


def test_import_runanywhere_without_native() -> None:
    """The package imports cleanly and does not eagerly load the native extension."""
    r = _fresh_interpreter(
        "import runanywhere, sys; "
        "assert 'runanywhere._native._core' not in sys.modules; print('ok')"
    )
    assert r.returncode == 0, r.stderr
    assert "ok" in r.stdout


def test_version_string() -> None:
    import runanywhere

    assert runanywhere.__version__ == "0.20.11"


# The full public surface promised by __all__ / the Electron index.ts.
_EXPECTED = [
    # facade
    "RunAnywhere",
    # model wrappers
    "LLMModel",
    "VLMModel",
    "Embedder",
    "STTModel",
    "TTSVoice",
    "Vad",
    # conversation
    "Chat",
    "ChatMessage",
    "VoiceAgent",
    # options
    "InitOptions",
    "GenerateOptions",
    "LoadOptions",
    "DownloadOptions",
    "VadOptions",
    "ChatOptions",
    # results / value types
    "LLMGenerationResult",
    "LLMStreamEvent",
    "Synthesis",
    "VoiceTurn",
    "ResolvedModel",
    "DownloadProgress",
    "ModelStatus",
    # errors
    "SDKException",
    "ErrorCode",
    "ErrorCategory",
    "is_sdk_exception",
    "as_sdk_exception",
    # events
    "EventBus",
    "bus",
    "InitializedEvent",
    "ServicesReadyEvent",
    "ShutdownEvent",
    "ModelLoadedEvent",
    "ModelUnloadedEvent",
    "GenerationEvent",
    "RunAnywhereEvent",
    # grammar / structured / tools
    "json_schema_to_grammar",
    "object_grammar",
    "parse_structured",
    "tool_call_schema",
    "tool_call_prompt",
    "ToolSpec",
    "ToolCall",
    "ToolRun",
    # streaming
    "stream_with_metrics",
    # audio helpers
    "float32_to_pcm16",
    "pcm16_to_float32",
    "pcm16_bytes",
    "downsample",
    "rms",
    "encode_wav",
    "decode_wav",
    # catalog
    "CATALOG",
    "CatalogEntry",
    "CatalogFile",
    "ModelType",
    "is_catalog_id",
    # download / resolution
    "resolve_model",
    "download_file",
    "models_root",
    "model_status",
]


@pytest.mark.parametrize("name", _EXPECTED)
def test_public_symbol_exists(name: str) -> None:
    """Every promised public symbol is re-exported at the package top level."""
    import runanywhere

    assert hasattr(runanywhere, name), f"runanywhere.{name} is missing"
    assert name in runanywhere.__all__, f"{name} not listed in runanywhere.__all__"


def test_error_codes_are_usable_without_native() -> None:
    """A representative pure type is fully functional with no native module present."""
    import runanywhere

    exc = runanywhere.SDKException.not_initialized("LLM")
    assert exc.code == runanywhere.ErrorCode.NOT_INITIALIZED
    assert isinstance(exc.category, runanywhere.ErrorCategory)


def test_native_loader_importable_but_lazy() -> None:
    """The lazy loader module imports without loading _core, and exposes get_core."""
    r = _fresh_interpreter(
        "from runanywhere import _native; import sys; "
        "assert hasattr(_native, 'get_core'); "
        "assert 'runanywhere._native._core' not in sys.modules; print('ok')"
    )
    assert r.returncode == 0, r.stderr
    assert "ok" in r.stdout
