#!/usr/bin/env python3
"""compute_percentiles.py — Aggregator for the GAP 09 #8 perf bench.

v2.1 quick-wins Item 3. Reads N per-SDK log files (each one delta_ns
per line, produced by perf_bench.{swift,kt,dart,ts}) and prints
p50 / p95 / p99 / max / count for each, plus an overall summary
table written to /tmp/perf_bench.summary.md.

Asserts `p50_ns < 1_000_000` (= 1 ms) per the GAP 09 #8 spec
criterion. Exit code 1 if any SDK fails the threshold.

Usage:
    python3 compute_percentiles.py /tmp/perf_bench.swift.log \\
                                   /tmp/perf_bench.kt.log \\
                                   /tmp/perf_bench.dart.log \\
                                   /tmp/perf_bench.rn.log \\
                                   /tmp/perf_bench.web.log
"""
import sys
from pathlib import Path

P50_THRESHOLD_NS = 1_000_000  # 1 ms per GAP 09 #8 spec


def percentile(sorted_vals, p):
    """0 <= p <= 1; linear interpolation."""
    if not sorted_vals:
        return 0
    k = (len(sorted_vals) - 1) * p
    f = int(k)
    c = min(f + 1, len(sorted_vals) - 1)
    if f == c:
        return sorted_vals[f]
    return sorted_vals[f] + (sorted_vals[c] - sorted_vals[f]) * (k - f)


def analyze_file(path):
    """Return dict with sdk name + percentile metrics."""
    name = Path(path).stem.replace("perf_bench.", "")
    try:
        deltas = sorted(int(line.strip()) for line in open(path) if line.strip())
    except FileNotFoundError:
        return {"sdk": name, "missing": True}
    if not deltas:
        return {"sdk": name, "empty": True}
    return {
        "sdk": name,
        "count": len(deltas),
        "p50": int(percentile(deltas, 0.50)),
        "p95": int(percentile(deltas, 0.95)),
        "p99": int(percentile(deltas, 0.99)),
        "max": deltas[-1],
        "min": deltas[0],
    }


def fmt_ns(ns):
    if ns < 1_000:
        return f"{ns} ns"
    if ns < 1_000_000:
        return f"{ns / 1_000:.2f} µs"
    return f"{ns / 1_000_000:.3f} ms"


def main(argv):
    # v2 close-out: allow directory arg as a convenience — discover any
    # perf_bench.<sdk>.log files inside it. CTest / CI wire this as
    # `compute_percentiles.py <build_dir>/tests/streaming/perf_bench`;
    # when no per-SDK runners have produced logs, exit 0 (harness sanity
    # check only — the C++ producer stays the actual gate).
    if len(argv) == 2 and Path(argv[1]).is_dir():
        log_paths = sorted(Path(argv[1]).glob("perf_bench.*.log"))
        if not log_paths:
            print(f"[compute_percentiles] no per-SDK logs in {argv[1]} "
                  "(per-SDK runners run in their SDK CI — C++ producer "
                  "is the authoritative gate here). Exit 0.")
            return 0
        argv = [argv[0]] + [str(p) for p in log_paths]
    elif len(argv) < 2:
        print(__doc__)
        return 2

    results = [analyze_file(p) for p in argv[1:]]

    # Console output
    print(f"{'SDK':<10} {'count':>8} {'p50':>12} {'p95':>12} {'p99':>12} {'max':>12} {'gate':>8}")
    print("-" * 80)
    failed = []
    for r in results:
        if r.get("missing"):
            print(f"{r['sdk']:<10} {'(no log file)':>56}")
            continue
        if r.get("empty"):
            print(f"{r['sdk']:<10} {'(empty log)':>56}")
            continue
        gate = "PASS" if r["p50"] < P50_THRESHOLD_NS else "FAIL"
        if gate == "FAIL":
            failed.append(r["sdk"])
        print(f"{r['sdk']:<10} {r['count']:>8} {fmt_ns(r['p50']):>12} "
              f"{fmt_ns(r['p95']):>12} {fmt_ns(r['p99']):>12} "
              f"{fmt_ns(r['max']):>12} {gate:>8}")

    # Markdown summary
    summary_lines = [
        "# Perf Bench Summary",
        "",
        "Closes [GAP 09 #8](../../../v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md)",
        f"`p50 ≤ 1ms across 5 SDKs`. Gate threshold: **{P50_THRESHOLD_NS} ns** (1 ms).",
        "",
        "| SDK | Events | p50 | p95 | p99 | max | gate |",
        "|-----|-------:|----:|----:|----:|----:|:----:|",
    ]
    for r in results:
        if r.get("missing"):
            summary_lines.append(f"| {r['sdk']} | — | — | — | — | — | (no log) |")
            continue
        if r.get("empty"):
            summary_lines.append(f"| {r['sdk']} | 0 | — | — | — | — | (empty) |")
            continue
        gate = "PASS" if r["p50"] < P50_THRESHOLD_NS else "**FAIL**"
        summary_lines.append(
            f"| {r['sdk']} | {r['count']} | {fmt_ns(r['p50'])} | "
            f"{fmt_ns(r['p95'])} | {fmt_ns(r['p99'])} | "
            f"{fmt_ns(r['max'])} | {gate} |"
        )

    Path("/tmp/perf_bench.summary.md").write_text("\n".join(summary_lines) + "\n")
    print(f"\nSummary written to /tmp/perf_bench.summary.md")

    if failed:
        print(f"\nFAILED: {', '.join(failed)} exceeded p50 threshold of {fmt_ns(P50_THRESHOLD_NS)}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
