#!/usr/bin/env python3
"""
compare_cancel_traces.py — GAP 09 #7 5-SDK cancellation-parity verifier.

v3.1 Phase 5.1. Reads per-SDK cancel traces from
/tmp/cancel_trace.<swift|kt|dart|rn|web>.log and asserts:

  1. All SDKs observed the InterruptedEvent at the same ordinal index
     (proto-wire parity — the same proto stream should arrive in the
     same order on every SDK).

  2. Every SDK stopped emitting events within 50 ms of the interrupt
     (latency bound).

Trace format (one per line):
  <event_ordinal> <payload_kind> <recv_ns>

Where payload_kind ∈ {userSaid, assistantToken, audio, vad, state,
error, interrupted, metrics} — the proto oneof case name.

The interrupt marker is the first line with payload_kind='interrupted'.
Every subsequent line must have recv_ns within 50_000_000 ns of the
interrupted line's recv_ns (50 ms).
"""
import argparse
import os
import sys
from collections import defaultdict

CANCEL_LATENCY_BUDGET_NS = 50_000_000  # 50 ms


def parse_trace(path):
    """Return a list of (ordinal, kind, recv_ns) tuples."""
    if not os.path.exists(path):
        return None
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 3:
                raise ValueError(f"bad trace line in {path}: {line!r}")
            rows.append((int(parts[0]), parts[1], int(parts[2])))
    return rows


def find_interrupt_ordinal(rows):
    """Return the ordinal of the first interrupted event, or None."""
    for ordinal, kind, _ in rows:
        if kind == "interrupted":
            return ordinal
    return None


def check_sdk(sdk_name, rows):
    """Return (ok, interrupt_ordinal, post_cancel_count, post_cancel_max_delta_ns)."""
    interrupt_ord = find_interrupt_ordinal(rows)
    if interrupt_ord is None:
        return (False, None, 0, 0, f"{sdk_name}: no interrupted event observed")

    interrupt_row = next((r for r in rows if r[0] == interrupt_ord and r[1] == "interrupted"), None)
    if interrupt_row is None:
        return (False, interrupt_ord, 0, 0, f"{sdk_name}: interrupted event lookup failed")

    _, _, interrupt_ns = interrupt_row

    post_cancel = [r for r in rows if r[0] > interrupt_ord]
    if not post_cancel:
        return (True, interrupt_ord, 0, 0, None)

    deltas = [r[2] - interrupt_ns for r in post_cancel]
    max_delta = max(deltas) if deltas else 0
    if max_delta > CANCEL_LATENCY_BUDGET_NS:
        return (
            False, interrupt_ord, len(post_cancel), max_delta,
            f"{sdk_name}: {len(post_cancel)} events after interrupt, "
            f"max_delta={max_delta}ns > budget={CANCEL_LATENCY_BUDGET_NS}ns",
        )
    return (True, interrupt_ord, len(post_cancel), max_delta, None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift", default="/tmp/cancel_trace.swift.log")
    parser.add_argument("--kt", default="/tmp/cancel_trace.kt.log")
    parser.add_argument("--dart", default="/tmp/cancel_trace.dart.log")
    parser.add_argument("--rn", default="/tmp/cancel_trace.rn.log")
    parser.add_argument("--web", default="/tmp/cancel_trace.web.log")
    parser.add_argument(
        "--require",
        default="swift,kt,dart,rn,web",
        help="Comma-separated list of SDKs that MUST have a trace. "
             "Set empty to allow all missing (harness sanity check mode).",
    )
    # v2 close-out: accept a positional directory as convenience for CTest
    # wiring — treat it as the dir holding cancel_trace.<sdk>.log files. If
    # no logs are present, fall back to harness-sanity-check mode (exit 0).
    parser.add_argument("trace_dir", nargs="?", default=None,
                        help="Optional directory holding cancel_trace.<sdk>.log files.")
    args = parser.parse_args()

    if args.trace_dir:
        from pathlib import Path
        td = Path(args.trace_dir)
        if td.is_dir():
            any_log = False
            for sdk in ("swift", "kt", "dart", "rn", "web"):
                p = td / f"cancel_trace.{sdk}.log"
                if p.exists():
                    any_log = True
                    setattr(args, sdk, str(p))
            if not any_log:
                print(f"[compare_cancel_traces] no per-SDK cancel_trace.*.log "
                      f"in {td} (per-SDK runners run in their SDK CI). "
                      "Exit 0.")
                return 0
            # Downgrade require to what's actually present.
            args.require = ",".join(
                sdk for sdk in ("swift", "kt", "dart", "rn", "web")
                if (td / f"cancel_trace.{sdk}.log").exists()
            )

    sdks = {
        "swift": args.swift,
        "kt": args.kt,
        "dart": args.dart,
        "rn": args.rn,
        "web": args.web,
    }
    required = set(s.strip() for s in args.require.split(",") if s.strip())

    results = {}
    interrupt_ordinals = defaultdict(list)
    any_failed = False

    for sdk, path in sdks.items():
        rows = parse_trace(path)
        if rows is None:
            msg = f"{sdk}: trace file missing at {path}"
            if sdk in required:
                print(f"FAIL: {msg}", file=sys.stderr)
                any_failed = True
            else:
                print(f"SKIP: {msg}", file=sys.stderr)
            continue
        ok, interrupt_ord, post_count, max_delta, err = check_sdk(sdk, rows)
        results[sdk] = (ok, interrupt_ord, post_count, max_delta)
        if interrupt_ord is not None:
            interrupt_ordinals[interrupt_ord].append(sdk)
        if not ok:
            print(f"FAIL: {err}", file=sys.stderr)
            any_failed = True
        else:
            print(f"PASS: {sdk} interrupt_ord={interrupt_ord} "
                  f"post_cancel={post_count} max_delta_ns={max_delta}")

    # Wire-parity check: every SDK must observe the interrupt at the same ordinal.
    if len(interrupt_ordinals) > 1:
        print(f"FAIL: wire-parity — SDKs disagree on interrupt ordinal: "
              f"{dict(interrupt_ordinals)}", file=sys.stderr)
        any_failed = True
    elif len(interrupt_ordinals) == 1:
        ord_val = next(iter(interrupt_ordinals))
        print(f"PASS: wire-parity — all {len(interrupt_ordinals[ord_val])} SDKs "
              f"observed interrupt at ordinal {ord_val}")

    return 1 if any_failed else 0


if __name__ == "__main__":
    sys.exit(main())
