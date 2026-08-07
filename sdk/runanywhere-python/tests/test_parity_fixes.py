"""Regression tests for divergences the broader unit suite does not cover.

Grammar JSON-stringify parity (non-ASCII / integer-float / boolean maxItems), the
HuggingFace source-classifier regex (trailing newline / non-ASCII word chars), and listener
isolation in the event bus.
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
from runanywhere.events import EventBus, SdkEvent, SdkEventKind  # noqa: E402
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
    b.emit(SdkEvent(kind=SdkEventKind.READY))  # a normal Exception is isolated
    assert len(seen) == 1  # the second listener still ran

    class Boom(BaseException):
        pass

    def raises_base(_e):
        raise Boom()

    b2 = EventBus()
    b2.on(raises_base)
    b2.on(seen.append)
    with pytest.raises(Boom):
        b2.emit(SdkEvent(kind=SdkEventKind.READY))  # a BaseException is NOT swallowed — it propagates
