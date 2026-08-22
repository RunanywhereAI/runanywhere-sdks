#!/usr/bin/env python3
"""Assert the staged QHexRT prebuilt is the one we think it is — and say how stale.

WHY THIS EXISTS
---------------
`engines/qhexrt/CMakeLists.txt` consumes a PREBUILT receipt tree; it never builds
QHexRT from source. For win-arm64 that tree is staged by hand on the self-hosted
Snapdragon runner, and until now the only record of which neurun commit was inside
it was a bare directory hash in a workflow env var. So the shipped NPU engine could
drift arbitrarily far behind neurun and nothing anywhere would say so — which is
exactly what happened: the tree shipped in 0.20.25 was built from a neurun commit
that predates the Hexagon v81 kernel work.

WHAT IT CHECKS
--------------
1. HARD FAIL if the staged receipt's identity does not match
   engines/qhexrt/PREBUILT_PROVENANCE.json (someone re-staged without recording it,
   or QHEXRT_ROOT points somewhere unexpected).
2. WARN — never fail — when the recorded neurun commit is behind neurun's default
   branch. Staleness is a fact to surface, not a reason to break the release: the
   refresh needs a licensed QAIRT install on a specific physical machine.

Requires `gh` on PATH for the staleness check; skips it (with a note) if absent or
unauthenticated, so this still works offline and on forks.

USAGE
    check_qhexrt_provenance.py --qhexrt-root <staged tree>   # full check
    check_qhexrt_provenance.py --record-only                 # parse + report only
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
PROVENANCE = REPO_ROOT / "engines" / "qhexrt" / "PREBUILT_PROVENANCE.json"
NEURUN = "RunanywhereAI/neurun"


def load_provenance() -> dict:
    if not PROVENANCE.is_file():
        sys.exit(f"FAIL: missing {PROVENANCE.relative_to(REPO_ROOT)}")
    try:
        return json.loads(PROVENANCE.read_text())
    except json.JSONDecodeError as exc:
        sys.exit(f"FAIL: {PROVENANCE.relative_to(REPO_ROOT)} is not valid JSON: {exc}")


def check_staged(root: Path, want: dict) -> list[str]:
    """Compare the on-disk receipt against what we recorded. Returns failure strings."""
    fails: list[str] = []
    receipt_path = root / "qhexrt-build-receipt.json"
    if not receipt_path.is_file():
        return [f"no receipt at {receipt_path}"]

    try:
        receipt = json.loads(receipt_path.read_text())
    except json.JSONDecodeError as exc:
        return [f"receipt is not valid JSON: {exc}"]

    # The directory name IS the receipt hash (engines/qhexrt/CMakeLists.txt enforces
    # this self-identity rule too); compare it to what we recorded.
    if root.name != want["build_receipt_sha256"]:
        fails.append(
            f"staged dir name {root.name!r} != recorded build_receipt_sha256 "
            f"{want['build_receipt_sha256']!r}"
        )

    src = receipt.get("source") or {}
    for key, label in (("git_sha", "neurun git_sha"), ("state_sha256", "neurun state_sha256")):
        got, exp = src.get(key), want["neurun"].get(key)
        if got != exp:
            fails.append(f"{label}: staged={got!r} recorded={exp!r}")

    if src.get("git_dirty") is not want["neurun"].get("git_dirty"):
        fails.append(
            f"neurun git_dirty: staged={src.get('git_dirty')!r} "
            f"recorded={want['neurun'].get('git_dirty')!r}"
        )

    if receipt.get("qhexrt_version") != want.get("qhexrt_version"):
        fails.append(
            f"qhexrt_version: staged={receipt.get('qhexrt_version')!r} "
            f"recorded={want.get('qhexrt_version')!r}"
        )
    return fails


def report_staleness(want: dict) -> None:
    """WARN-only: how far behind neurun's default branch the staged tree is."""
    sha = want["neurun"]["git_sha"]
    try:
        out = subprocess.run(
            ["gh", "api", f"repos/{NEURUN}/compare/{sha}...HEAD",
             "--jq", "{ahead_by, behind_by}"],
            capture_output=True, text=True, timeout=45, check=True,
        ).stdout.strip()
        cmp = json.loads(out)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
            FileNotFoundError, json.JSONDecodeError) as exc:
        print(f"  note: staleness check skipped ({type(exc).__name__}) — needs `gh` "
              f"authenticated for the private {NEURUN}")
        return

    ahead = cmp.get("ahead_by") or 0
    if ahead == 0:
        print(f"  OK: staged QHexRT is current with {NEURUN} HEAD")
        return
    print(f"  ::warning::staged QHexRT prebuilt is {ahead} commit(s) BEHIND "
          f"{NEURUN} HEAD — neurun changes since {sha[:12]} are NOT in the shipped "
          f"@runanywhere/electron-qhexrt. Refresh: "
          f"bindings/electron/docs/QHEXRT_PREBUILT_REFRESH.md")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--qhexrt-root", type=Path,
                    help="the staged versions/<receipt-sha256> tree to verify")
    ap.add_argument("--record-only", action="store_true",
                    help="parse the provenance record and report staleness; skip disk checks")
    args = ap.parse_args()

    want = load_provenance()
    n = want["neurun"]
    print(f"recorded QHexRT prebuilt: receipt={want['build_receipt_sha256'][:16]}… "
          f"abi={want['abi']} qhexrt={want['qhexrt_version']}")
    print(f"  built from {NEURUN}@{n['git_sha'][:12]} "
          f"({n.get('commit_date','?')}) dirty={n.get('git_dirty')}")

    if args.qhexrt_root:
        root = args.qhexrt_root
        if not root.is_dir():
            print(f"FAIL: --qhexrt-root is not a directory: {root}")
            return 1
        fails = check_staged(root, want)
        if fails:
            print("FAIL: staged QHexRT does not match the recorded provenance:")
            for f in fails:
                print(f"  - {f}")
            print("\nIf the re-stage was intentional, update "
                  "engines/qhexrt/PREBUILT_PROVENANCE.json in the same commit that "
                  "moves QHEXRT_ROOT.")
            return 1
        print("  OK: staged tree matches the recorded provenance")
    elif not args.record_only:
        print("  note: no --qhexrt-root given; skipping on-disk verification")

    report_staleness(want)
    for gap in want.get("known_gaps", []):
        print(f"  known gap: {gap}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
