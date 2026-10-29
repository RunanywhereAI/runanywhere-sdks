#!/usr/bin/env python3
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

CASES: list[tuple[str, str, bool]] = [
    ("absolute path into a personal home directory", "/Users/alice/Documents/x/", True),
    ("absolute path into a personal home directory", "/home/alice/build/", True),
    ("absolute path into a personal home directory", r"C:\Users\alice\build", True),
    ("absolute path into a personal home directory", r"D:\Users\alice\build", True),
    ("absolute path into a personal home directory", r"C:\\Users\\alice\\build", True),
    ("absolute path into a personal home directory", r"C:\\Users\\<you>\\x", False),
    ("absolute path into a personal home directory", "/Users/<you>/x/", False),
    ("absolute path into a personal home directory", r"C:\Users\<you>\x", False),
    ("absolute path into a personal home directory", "/usr/local/bin/", False),
    ("absolute path into a personal home directory", "~/.ssh/config", False),
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
