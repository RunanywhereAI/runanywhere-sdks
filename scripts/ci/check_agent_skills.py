#!/usr/bin/env python3
"""Gate for the committed agent instruction trees (.claude/ + .agents/).

These trees are TRACKED in a PUBLIC repo, which makes them a publishing surface,
not scratch space. Two failure modes have to be machine-checked because neither
shows a symptom in review:

  1. MIRROR DRIFT. `.claude/skills/` is canonical (Claude Code reads it directly);
     `.agents/skills/` is a generated copy for non-Claude tooling that cannot
     follow a symlink. Hand-editing one and not the other publishes a stale
     runbook that some agents read and others don't. Delegated to
     scripts/setup/sync-skills.sh --check, so CI and a laptop run the same code.

  2. PRIVATE INFRASTRUCTURE LEAKING BACK IN. The skills describe real release
     machinery, so it is natural to paste in the hostname of the Windows test
     box, an SSH identity file, or a runner name while debugging. A public repo
     must not carry those. The rule is: describe the CAPABILITY ("a Windows
     ARM64 machine reachable over SSH; read the alias from the operator's
     ~/.ssh/config"), never the COORDINATES. An agent that has read the
     instructions can resolve the rest from the operator's own machine.

Run locally exactly as CI does:

    python3 scripts/ci/check_agent_skills.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

# Repo root by WALKING UP to a marker, never by counting parent hops — a
# hardcoded parents[2] breaks silently the moment this file moves a level.
def repo_root() -> Path:
    for d in [Path(__file__).resolve().parent, *Path(__file__).resolve().parents]:
        if (d / "CMakeLists.txt").is_file() and (d / "package.json").is_file():
            return d
    sys.exit("FATAL: no repo root above this script (looked for CMakeLists.txt + package.json)")


REPO = repo_root()

# The trees this gate owns. Both are tracked; see .gitignore.
TREES = [".claude/skills", ".claude/commands", ".agents/skills"]

# Each rule is (label, compiled pattern, what to write instead). Patterns are
# deliberately about SHAPES of private coordinates rather than one team's
# current hostnames, so the gate keeps working after the infrastructure moves.
RULES: list[tuple[str, re.Pattern[str], str]] = [
    (
        "mesh-VPN / Tailscale hostname",
        re.compile(r"\b[\w-]+\.(?:ts\.net|tailscale\.net|tailnet\.[\w-]+)\b", re.I),
        "say 'the host entry in the operator's ~/.ssh/config'; never the tailnet name",
    ),
    (
        "concrete ssh target (user@host)",
        re.compile(r"\bssh\s+(?:-\S+\s+|\S+=\S+\s+)*[\w.-]+@[\w.-]+", re.I),
        "use a placeholder alias, e.g. ssh \"$WIN_BOX\" ...",
    ),
    (
        "~/.ssh config coordinates",
        re.compile(r"^\s*(?:HostName|IdentityFile|ProxyJump)\s+\S", re.I | re.M),
        "describe the host entry to look for, not its contents",
    ),
    (
        "ssh private key filename",
        re.compile(r"\bid_(?:ed25519|rsa|ecdsa|dsa)(?:_[\w-]+)?\b"),
        "never name a key file; the operator's ssh config already selects it",
    ),
    (
        "private key material",
        re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
        "a key must never be in the repo at all",
    ),
    (
        "self-hosted runner name",
        # Runner *labels* stay allowed — they are how a workflow selects a
        # runner and are already visible in .github/workflows/. Only a
        # `runs-on:`-style concrete machine name is a coordinate.
        re.compile(r"\brunner\s*\(`[\w-]+`", re.I),
        "give the runner's LABELS, not the machine's registered name",
    ),
    (
        "RFC1918 / link-local address",
        re.compile(r"\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01])|169\.254)\.\d{1,3}\.\d{1,3}\b"),
        "a private IP is a coordinate; describe how to discover the host instead",
    ),
    (
        "absolute path into a personal home directory",
        re.compile(
            r"(?:/Users/(?!<)[\w.-]+/"
            r"|/home/(?!<)[\w.-]+/"
            # Windows separators are backslashes, so the trailing separator has to
            # live INSIDE each alternative: a shared trailing `/` can never match a
            # Windows path. Any drive letter, and `\\` here is one literal backslash.
            # `+` because these files are scanned as raw text: a path written inside
            # a JSON or shell snippet arrives escaped, as `C:\\Users\\alice\\`.
            r"|[A-Za-z]:\\+Users\\+(?!<)[\w.-]+\\+)"
        ),
        "use ~ or a <placeholder>; an absolute home path names a person and a machine",
    ),
]


def tracked_files() -> list[Path]:
    """Only what git will actually publish — an untracked local scratch file
    under these directories is the author's business, not this gate's."""
    out = subprocess.run(
        ["git", "-C", str(REPO), "ls-files", "-z", "--", *TREES],
        capture_output=True, text=True, check=True,
    ).stdout
    return [REPO / p for p in out.split("\0") if p]


def check_mirror() -> list[str]:
    r = subprocess.run(
        [str(REPO / "scripts/setup/sync-skills.sh"), "--check"],
        capture_output=True, text=True,
    )
    if r.returncode == 0:
        print(r.stdout.strip())
        return []
    return [(r.stdout + r.stderr).strip()]


def check_private(files: list[Path]) -> list[str]:
    findings: list[str] = []
    for f in files:
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        lines = text.splitlines()
        for label, pat, fix in RULES:
            for m in pat.finditer(text):
                lineno = text.count("\n", 0, m.start()) + 1
                snippet = lines[lineno - 1].strip()[:120] if lineno <= len(lines) else ""
                rel = f.relative_to(REPO)
                findings.append(
                    f"{rel}:{lineno}: {label}\n"
                    f"    {snippet}\n"
                    f"    -> {fix}"
                )
    return findings


def main() -> int:
    files = tracked_files()
    if not files:
        # A .gitignore edit or a directory rename can make every path above match
        # nothing, and a gate that silently checks zero files is worse than none.
        print("::error::agent-skills gate matched NO tracked files under "
              + ", ".join(TREES) + " — the trees moved or became ignored.", file=sys.stderr)
        return 1
    print(f"agent-skills gate: {len(files)} tracked files under {', '.join(TREES)}")

    problems = check_mirror() + check_private(files)
    if problems:
        print("\n::error::agent-skills gate FAILED\n", file=sys.stderr)
        for p in problems:
            print(p + "\n", file=sys.stderr)
        print(
            "These trees ship in a PUBLIC repo. Describe the capability, not the\n"
            "coordinates — an agent that has read the instructions can resolve a\n"
            "hostname from the operator's own ~/.ssh/config.\n"
            "After editing .claude/skills/, re-run: scripts/setup/sync-skills.sh",
            file=sys.stderr,
        )
        return 1

    print("agent-skills gate: OK (mirror in sync, no private coordinates)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
