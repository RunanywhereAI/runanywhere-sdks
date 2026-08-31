#!/usr/bin/env python3
"""Tests for the private-coordinate rules in check_agent_skills.py.

Running the gate only proves the trees are clean TODAY. These prove each rule
still matches the shape it was added for, so a rule cannot quietly stop
catching anything -- which is exactly what happened to the personal-home-path
rule: its Windows arm required a trailing forward slash, so no Windows path
could ever reach it.

Run locally exactly as CI does:

    python3 scripts/ci/test_agent_skills.py
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

GATE = Path(__file__).resolve().parent / "check_agent_skills.py"

_spec = importlib.util.spec_from_file_location("check_agent_skills", GATE)
_gate = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(_gate)

RULES = {label: pattern for label, pattern, _fix in _gate.RULES}

# (rule label, sample, should_match)
CASES: list[tuple[str, str, bool]] = [
    # A personal home path names both a person and a machine, on every OS.
    ("absolute path into a personal home directory", "/Users/alice/Documents/x/", True),
    ("absolute path into a personal home directory", "/home/alice/build/", True),
    ("absolute path into a personal home directory", r"C:\Users\alice\build", True),
    ("absolute path into a personal home directory", r"D:\Users\alice\build", True),
    # These files are scanned as raw text, so a Windows path written inside a JSON
    # or shell snippet reaches the rule with its separators already escaped.
    ("absolute path into a personal home directory", r"C:\\Users\\alice\\build", True),
    ("absolute path into a personal home directory", r"C:\\Users\\<you>\\x", False),
    # Placeholders are the documented way to write these, on every OS.
    ("absolute path into a personal home directory", "/Users/<you>/x/", False),
    ("absolute path into a personal home directory", r"C:\Users\<you>\x", False),
    # Not a home directory at all.
    ("absolute path into a personal home directory", "/usr/local/bin/", False),
    ("absolute path into a personal home directory", "~/.ssh/config", False),
    # Spot-check the neighbouring rules so a future edit cannot blank them.
    ("mesh-VPN / Tailscale hostname", "win-arm64.tail1234.ts.net", True),
    ("mesh-VPN / Tailscale hostname", "the host entry in ~/.ssh/config", False),
    ("ssh private key filename", "id_ed25519_runner", True),
    ("private key material", "-----BEGIN OPENSSH PRIVATE KEY-----", True),
    ("RFC1918 / link-local address", "192.168.1.20", True),
    ("RFC1918 / link-local address", "8.8.8.8", False),
]


def main() -> int:
    failures: list[str] = []
    for label, sample, want in CASES:
        pattern = RULES.get(label)
        if pattern is None:
            failures.append(f"rule missing entirely: {label!r}")
            continue
        got = bool(pattern.search(sample))
        if got != want:
            verb = "should have matched" if want else "should NOT have matched"
            failures.append(f"{label}: {verb} {sample!r}")

    if failures:
        print("agent-skills rule tests FAILED\n", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        return 1

    print(f"agent-skills rule tests: {len(CASES)} cases OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
