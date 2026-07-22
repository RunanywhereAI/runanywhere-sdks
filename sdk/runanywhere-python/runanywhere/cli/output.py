"""Output discipline for the CLI, matching the C++ rcli.

Results go to **stdout**; logs / progress / prompts / errors go to **stderr**; ``--json`` prints
exactly one JSON document to stdout. This keeps the CLI pipeable (`runanywhere run … | jq`).
"""
from __future__ import annotations

import json
import sys
from typing import Any


def result(text: str = "") -> None:
    """A result line -> stdout."""
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


def result_raw(text: str) -> None:
    """Result text with no trailing newline (for streaming tokens)."""
    sys.stdout.write(text)
    sys.stdout.flush()


def status(text: str = "") -> None:
    """A log/status line -> stderr."""
    sys.stderr.write(text + "\n")
    sys.stderr.flush()


def status_raw(text: str) -> None:
    sys.stderr.write(text)
    sys.stderr.flush()


def error(text: str) -> None:
    """An error line -> stderr, prefixed like rcli."""
    sys.stderr.write(f"error: {text}\n")
    sys.stderr.flush()


def emit_json(obj: Any) -> None:
    """Exactly one JSON document -> stdout."""
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def table(headers: list[str], rows: list[list[str]]) -> None:
    """A simple left-aligned ASCII table -> stdout."""
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(str(cell)))
    result("  ".join(h.ljust(widths[i]) for i, h in enumerate(headers)))
    for row in rows:
        result("  ".join(str(c).ljust(widths[i]) for i, c in enumerate(row)))


def stdout_is_tty() -> bool:
    return sys.stdout.isatty()


def stderr_is_tty() -> bool:
    return sys.stderr.isatty()
