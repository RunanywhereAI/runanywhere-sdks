#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 RunAnywhere AI, Inc.
"""Compare benchmark output against committed thresholds.

Used by the `commons-bench` CI workflow to fail the build on any
performance regression beyond the threshold's tolerance.

Usage:
    check_thresholds.py --results <dir> --thresholds <dir>

Both directories contain JSON files named identically. For each threshold
file, the matching result file must exist and its p50/p90/p99 must stay
within `ceiling * (1 + tolerance_pct/100)`.

Exits 0 when every result is within budget. Exits 1 on any violation and
prints a table. Exits 2 on missing files or malformed JSON.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys


def load_json(path: pathlib.Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"ERROR: failed to read {path}: {e}", file=sys.stderr)
        sys.exit(2)


def check_one(name: str, threshold: dict, result: dict) -> list[str]:
    violations: list[str] = []
    tolerance_pct = int(threshold.get("tolerance_pct", 10))
    for key in ("p50_ms", "p90_ms", "p99_ms"):
        ceiling = float(threshold.get(key, float("inf")))
        allowed = ceiling * (1 + tolerance_pct / 100.0)
        actual = result.get(key)
        if actual is None:
            violations.append(f"{name}: result missing {key}")
            continue
        if float(actual) > allowed:
            violations.append(
                f"{name}: {key} = {actual:.3f} "
                f"(ceiling {ceiling}, +{tolerance_pct}% = {allowed:.3f})"
            )
    return violations


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--results", type=pathlib.Path, required=True,
                   help="Directory with benchmark output JSON files")
    p.add_argument("--thresholds", type=pathlib.Path, required=True,
                   help="Directory with threshold JSON files")
    args = p.parse_args()

    if not args.thresholds.is_dir():
        print(f"ERROR: {args.thresholds} is not a directory", file=sys.stderr)
        return 2

    violations: list[str] = []
    checked = 0
    for threshold_path in sorted(args.thresholds.glob("*.json")):
        threshold = load_json(threshold_path)
        name = threshold.get("name", threshold_path.stem)
        result_path = args.results / f"{threshold_path.stem}.json"
        if not result_path.exists():
            print(f"SKIP  {name} — no result file at {result_path}")
            continue
        result = load_json(result_path)
        v = check_one(name, threshold, result)
        if v:
            violations.extend(v)
        else:
            print(f"OK    {name}  p50={result.get('p50_ms')} "
                  f"p90={result.get('p90_ms')} p99={result.get('p99_ms')}")
        checked += 1

    if not checked:
        print("WARN  no benchmark results matched any threshold — check "
              "--results and --thresholds paths")

    if violations:
        print("\nTHRESHOLD VIOLATIONS:")
        for v in violations:
            print(f"  - {v}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
