"""Regression tests for the Electron-parity fixes applied after the parity review.

Each test pins a specific divergence that the broader unit suite did not cover:
grammar JSON-stringify parity (non-ASCII / integer-float / boolean maxItems), the HF
source-classifier regex (trailing newline / non-ASCII word chars), total listener
isolation in the event bus, and the client's services-ready seam / model_status root /
VAD teardown.
"""
from __future__ import annotations

import os
import sys

# Make the package importable regardless of the pytest invocation cwd.
_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import pytest  # noqa: E402

from runanywhere.download import is_remote_source  # noqa: E402
from runanywhere.events import EventBus, InitializedEvent  # noqa: E402
from runanywhere.grammar import json_schema_to_grammar  # noqa: E402


# --------------------------------------------------------------------------
# grammar.py — JSON.stringify parity in const/enum literals
# --------------------------------------------------------------------------
def test_grammar_non_ascii_const_is_raw_not_escaped():
    # JS JSON.stringify never \u-escapes; the é must stay a raw character.
    g = json_schema_to_grammar({"const": "café"})
    assert "café" in g
    assert "u00e9" not in g


def test_grammar_integer_valued_float_renders_like_js():
    # JS has no int/float split: JSON.stringify(5.0) === "5".
    g = json_schema_to_grammar({"const": 5.0})
    assert '"5"' in g
    assert "5.0" not in g


def test_grammar_boolean_max_items_is_unbounded():
    # `maxItems: true` is not a number in JS -> unbounded; bool must not read as 1.
    g = json_schema_to_grammar({"type": "array", "items": {"type": "string"}, "maxItems": True})
    assert ")*" in g  # the unbounded `( ws "," ws item )*` form, not a bounded chain


# --------------------------------------------------------------------------
# download.py — is_remote_source HF classifier parity with the JS regex
# --------------------------------------------------------------------------
@pytest.mark.parametrize(
    "value, expected",
    [
        ("owner/repo", True),           # plain HF repo id
        ("owner/repo:file.gguf", True),  # HF repo with explicit file
        ("https://x/y.gguf", True),      # direct URL
        ("owner/repo\n", False),         # trailing newline -> local path (JS parity)
        ("owner/repö", False),           # non-ASCII word char -> local path (JS parity)
        ("/abs/local/model.gguf", False),
        ("./relative/model.gguf", False),
    ],
)
def test_is_remote_source_matches_js_semantics(value, expected):
    assert is_remote_source(value) is expected


# --------------------------------------------------------------------------
# events.py — a listener raising a normal Exception is isolated, but a control-flow
# BaseException (KeyboardInterrupt / CancelledError / SystemExit) must PROPAGATE, not be
# silently swallowed. (A literal port of Electron's catch-all `catch {}` would have eaten
# Ctrl-C — the Python-correct behavior catches Exception, not BaseException.)
# --------------------------------------------------------------------------
def test_emit_isolates_exception_but_propagates_base():
    seen: list[object] = []
    b = EventBus()

    def raises_exc(_e):
        raise RuntimeError("boom")

    b.on(raises_exc)
    b.on(seen.append)
    b.emit(InitializedEvent())  # a normal Exception is isolated
    assert len(seen) == 1  # the second listener still ran

    class Boom(BaseException):
        pass

    def raises_base(_e):
        raise Boom()

    b2 = EventBus()
    b2.on(raises_base)
    b2.on(seen.append)
    with pytest.raises(Boom):
        b2.emit(InitializedEvent())  # a BaseException is NOT swallowed — it propagates


# --------------------------------------------------------------------------
# client.py — services-ready seam, model_status root, VAD teardown
# --------------------------------------------------------------------------
class _FakeCore:
    """Minimal recording stand-in for the compiled _core module."""

    def __init__(self):
        self.unloaded_vad: list[int] = []
        self.shutdown_calls = 0

    def version(self):
        return "test-0"

    def initialize(self, secure, base):
        pass

    def shutdown(self):
        self.shutdown_calls += 1

    def create_vad(self, threshold=None):
        return 7

    def unload_vad(self, handle):
        self.unloaded_vad.append(handle)

    def backends(self):
        return ["llamacpp", "onnx", "sherpa"]


@pytest.fixture()
def client_env(monkeypatch):
    """Reset the process-global client state + bus, and inject a fake core."""
    import runanywhere.client as C
    from runanywhere import events as E

    C._init_count = 0
    C._native_up = False
    C._services_ready = False
    E.bus.remove_all()
    fake = _FakeCore()
    monkeypatch.setattr(C._native, "get_core", lambda: fake)
    monkeypatch.setattr(C, "model_status", lambda root=None: {"__root__": root})
    yield C, fake
    C._init_count = 0
    C._native_up = False
    C._services_ready = False
    E.bus.remove_all()


def test_services_ready_lifecycle_and_idempotent(client_env):
    C, _ = client_env
    ra = C.RunAnywhere()
    assert ra.are_services_ready is False
    ra.initialize()
    assert ra.are_services_ready is True  # Phase-2 ran on first init
    ra.complete_services_initialization()  # idempotent, must not raise
    assert ra.are_services_ready is True
    ra.shutdown()
    assert ra.are_services_ready is False  # reset on last shutdown


def test_model_status_uses_models_root_not_base_dir(client_env):
    C, _ = client_env
    ra = C.RunAnywhere(base_dir="/some/other/base")
    status = ra.model_status()  # no init required (pure host I/O)
    assert status["__root__"] is None  # defaulted to models_root(), not base_dir


def test_vad_is_closed_on_client_shutdown(client_env):
    C, fake = client_env
    ra = C.RunAnywhere().initialize()
    vad = ra.create_vad()  # hold a strong ref (the WeakSet drops GC'd models)
    assert vad is not None
    ra.shutdown()
    assert fake.unloaded_vad == [7]  # registered -> close() -> core.unload_vad(handle)


def test_available_backends_reports_core_list(client_env):
    C, _ = client_env
    # No initialize() required — it reflects the build's compiled-in backends.
    assert C.RunAnywhere().available_backends() == ["llamacpp", "onnx", "sherpa"]
