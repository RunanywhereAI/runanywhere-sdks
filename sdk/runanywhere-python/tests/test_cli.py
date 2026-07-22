"""Hermetic tests for the ``runanywhere`` CLI (runanywhere/__main__.py).

Pure Python — no native build, no fastapi. ``serve`` needs the [server] extra, but ``models`` /
``--version`` and the friendly "install the extra" hint all work in a base install, so these run
in every CI lane (they do NOT importorskip fastapi).
"""
from __future__ import annotations

import sys

import runanywhere
from runanywhere.__main__ import main


def test_version(capsys):
    assert main(["--version"]) == 0
    assert capsys.readouterr().out.strip() == runanywhere.__version__


def test_models_lists_catalog(capsys):
    assert main(["models"]) == 0
    out = capsys.readouterr().out
    assert "MODEL" in out and "DOWNLOADED" in out
    assert "minilm" in out  # a known catalog id


def test_no_command_prints_help_and_returns_1(capsys):
    assert main([]) == 1


def test_serve_without_extra_prints_install_hint(capsys, monkeypatch):
    """When fastapi isn't installed, `runanywhere serve` must print a friendly hint, not crash.

    Setting ``sys.modules['runanywhere.server'] = None`` makes ``from .server import serve`` raise
    ImportError even when fastapi IS installed, so this test is deterministic in any environment.
    """
    from runanywhere.__main__ import _cmd_serve

    monkeypatch.setitem(sys.modules, "runanywhere.server", None)
    args = SimpleArgs()
    assert _cmd_serve(args) == 1
    assert "pip install runanywhere[server]" in capsys.readouterr().err


class SimpleArgs:
    host = "127.0.0.1"
    port = 8000
    api_key = None
    default_llm = None
    default_vlm = None
    default_embedder = None
    default_stt = None
    default_tts = None
    log_level = "info"
