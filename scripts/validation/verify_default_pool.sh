#!/usr/bin/env bash
#
# verify_default_pool.sh
#
# Reads the generated default pool back out of every language it was emitted
# into and asserts they all agree with idl/sdk_defaults.proto.
#
# This is the check that answers "is the pool actually doing its job". The
# gate (check_no_hardcoded_defaults.sh) proves nobody re-declared a default in
# SDK source; this proves the values the SDKs *do* read are the same values in
# every language. Different question, different failure mode: codegen that runs
# for four languages and silently skips the fifth passes the gate and fails
# this.
#
# It parses the emitted files rather than re-running codegen on purpose. Running
# the generators again would prove the generators are deterministic, not that
# what is committed matches the proto — and what is committed is what ships.
#
# Usage:
#   scripts/validation/verify_default_pool.sh          # table + verdict
#   scripts/validation/verify_default_pool.sh --quiet  # verdict only
#
# Exit codes:
#   0  Every language agrees with the proto.
#   1  At least one value disagrees, or a language is missing a field.
#   2  A generated file is missing (run idl/codegen/generate_defaults_pool.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

PY="${PYTHON_BIN:-python3}"
command -v "${PY}" >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 2; }

QUIET="${QUIET}" "${PY}" - <<'PYEOF'
import os
import re
import sys
from pathlib import Path

QUIET = os.environ.get("QUIET") == "1"

PROTO = Path("idl/sdk_defaults.proto")
TARGETS = {
    "proto":  PROTO,
    "c":      Path("core/include/rac/rac_defaults_generated.h"),
    "swift":  Path("bindings/swift/Sources/RunAnywhere/Generated/RADefaultsPool.swift"),
    "kotlin": Path("bindings/kotlin/src/main/kotlin/com/runanywhere/sdk/generated/RADefaultsPool.kt"),
    "dart":   Path("bindings/flutter/packages/runanywhere/lib/generated/ra_defaults_pool.dart"),
    "ts":     Path("bindings/shared/proto-ts/src/defaults/pool.ts"),
    "python": Path("bindings/python/runanywhere/_generated_defaults.py"),
    # The Flutter and RN Android plugins get their own copy because neither
    # depends on the Kotlin SDK; they must match it byte-for-byte in value.
    "kotlin/flutter-android": Path(
        "bindings/flutter/packages/runanywhere/android/src/main/kotlin/"
        "com/runanywhere/sdk/generated/RADefaultsPool.kt"
    ),
    "kotlin/rn-android": Path(
        "bindings/react-native/packages/core/android/src/main/java/"
        "com/runanywhere/sdk/generated/RADefaultsPool.kt"
    ),
}

missing = [f"{k} -> {v}" for k, v in TARGETS.items() if not v.is_file()]
if missing:
    print("error: generated pool file(s) missing:", file=sys.stderr)
    for m in missing:
        print(f"  {m}", file=sys.stderr)
    print("\nRun: idl/codegen/generate_defaults_pool.py", file=sys.stderr)
    sys.exit(2)


def to_snake(name: str) -> str:
    """camelCase / PascalCase / SCREAMING_SNAKE -> snake_case.

    Acronym runs must stay together: FFI -> ffi (not f_f_i), and
    defaultVadModelID -> default_vad_model_id (not ..._i_d). A name that is
    already SCREAMING_SNAKE is only lowercased.
    """
    if name.isupper() or re.fullmatch(r"[A-Z0-9_]+", name):
        return name.lower()
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", name)   # HTTPServer -> HTTP_Server
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)         # micSample  -> mic_Sample
    return s.lower()


def norm_key(group: str, field: str) -> str:
    """Collapse per-language spelling to one key: group + snake_case field."""
    g = re.sub(r"_?defaults$", "", to_snake(group))
    return f"{g}.{to_snake(field)}"


def norm_val(v: str) -> str:
    """Collapse literal spelling: 2.0f / 2.0 -> 2.0; 16_000 -> 16000.

    Strings are returned verbatim after unquoting. The numeric suffix strip must
    not touch them: rstrip("fFlL") on "https://dev.runanywhere.local" silently
    eats the trailing "l".
    """
    v = v.strip().rstrip(",;")
    if v in ("True", "False"):        # Python bool spelling
        return v.lower()
    if v[:1] in ('"', "'"):
        return v.strip('"').strip("'")
    core = v.rstrip("fFlL")
    try:
        f = float(core.replace("_", ""))
    except ValueError:
        return v.strip('"').strip("'")
    return str(int(f)) if f == int(f) and "." not in core else f"{f}"


def parse_proto(text):
    out = {}
    group = None
    for line in text.splitlines():
        m = re.match(r"\s*message\s+(\w+)\s*\{", line)
        if m:
            group = m.group(1)
            continue
        if group and re.match(r"\s*\}", line):
            group = None
        if not group:
            continue
        # field on one line, or a field whose annotations wrap
        fm = re.match(r"\s*\w+\s+(\w+)\s*=\s*\d+", line)
        if fm:
            pending = fm.group(1)
            dm = re.search(r'rac_default\)\s*=\s*"([^"]*)"', line)
            if dm:
                out[norm_key(group, pending)] = norm_val(dm.group(1))
            else:
                parse_proto.pending = (group, pending)
            continue
        dm = re.search(r'rac_default\)\s*=\s*"([^"]*)"', line)
        if dm and getattr(parse_proto, "pending", None):
            g, f = parse_proto.pending
            out[norm_key(g, f)] = norm_val(dm.group(1))
            parse_proto.pending = None
    return out


def parse_c(text, group_prefixes):
    """The C macro name is RAC_DEFAULT_<GROUP>_<FIELD> with both parts already
    SCREAMING_SNAKE, so the split point is only recoverable from the known group
    list. That list is derived from the proto rather than hardcoded: a hardcoded
    one silently reports every field of a newly added message as absent."""
    out = {}
    # longest first, so AUDIO_CAPTURE wins over a hypothetical AUDIO
    ordered = sorted(group_prefixes, key=len, reverse=True)
    for m in re.finditer(r"#define\s+RAC_DEFAULT_([A-Z0-9_]+)\s+(\S+)", text):
        name, val = m.group(1), m.group(2)
        for grp in ordered:
            if name.startswith(grp + "_"):
                field = name[len(grp) + 1:].lower()
                out[f"{grp.lower()}.{field}"] = norm_val(val)
                break
    return out


def parse_nested(text, group_re, field_re):
    """Swift/Kotlin: a nested group block, then fields inside it."""
    out = {}
    group = None
    for line in text.splitlines():
        gm = re.search(group_re, line)
        if gm:
            group = gm.group(1)
            continue
        if group:
            fm = re.search(field_re, line)
            if fm:
                out[norm_key(group, fm.group(1))] = norm_val(fm.group(2))
    return out


def parse_python(text):
    out = {}
    group = None
    for line in text.splitlines():
        gm = re.search(r"^class (\w+)Defaults:", line)
        if gm:
            group = gm.group(1)
            continue
        if group:
            fm = re.search(r"^\s+(\w+):\s*Final\[\w+\]\s*=\s*(.+)$", line)
            if fm:
                out[norm_key(group, fm.group(1))] = norm_val(fm.group(2))
    return out


def parse_dart(text):
    out = {}
    group = None
    for line in text.splitlines():
        gm = re.search(r"abstract final class RADefaults(\w+)", line)
        if gm:
            group = gm.group(1)
            continue
        if group:
            fm = re.search(r"static const \w+ (\w+)\s*=\s*([^;]+);", line)
            if fm:
                out[norm_key(group, fm.group(1))] = norm_val(fm.group(2))
    return out


def parse_ts(text):
    out = {}
    group = None
    for line in text.splitlines():
        gm = re.search(r"export const (\w+)Defaults\s*=", line)
        if gm:
            # ts-proto lowercases the first character of a symbol, so the FFI
            # group lands as `fFIDefaults` (same rule that yields
            # `vADConfigurationDefaults` in the convenience output). Undo it
            # before snake-casing, or the acronym splits into f_fi.
            g = gm.group(1)
            group = g[0].upper() + g[1:]
            continue
        if group:
            fm = re.search(r"^\s*(\w+):\s*(.+?)\s+as\s+\w+,", line)
            if fm:
                out[norm_key(group, fm.group(1))] = norm_val(fm.group(2))
    return out


SWIFT_GROUP = r"public enum (\w+) \{"
SWIFT_FIELD = r"public static let (\w+):\s*\w+\s*=\s*(.+)$"
KT_GROUP = r"public object (\w+) \{"
KT_FIELD = r"public const val (\w+):\s*\w+\s*=\s*(.+)$"

# Group prefixes exactly as generate_cpp_defaults.py forms them: the message
# name in SCREAMING_SNAKE with a trailing _DEFAULTS stripped.
C_GROUP_PREFIXES = set()
for _m in re.finditer(r"^\s*message\s+(\w+)\s*\{", TARGETS["proto"].read_text(), re.M):
    _g = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", _m.group(1))
    _g = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", _g).upper()
    C_GROUP_PREFIXES.add(re.sub(r"_?DEFAULTS$", "", _g))

parsed = {
    "proto":  parse_proto(TARGETS["proto"].read_text()),
    "c":      parse_c(TARGETS["c"].read_text(), C_GROUP_PREFIXES),
    "swift":  parse_nested(TARGETS["swift"].read_text(), SWIFT_GROUP, SWIFT_FIELD),
    "kotlin": parse_nested(TARGETS["kotlin"].read_text(), KT_GROUP, KT_FIELD),
    "dart":   parse_dart(TARGETS["dart"].read_text()),
    "ts":     parse_ts(TARGETS["ts"].read_text()),
    "python": parse_python(TARGETS["python"].read_text()),
    "kotlin/flutter-android": parse_nested(
        TARGETS["kotlin/flutter-android"].read_text(), KT_GROUP, KT_FIELD),
    "kotlin/rn-android": parse_nested(
        TARGETS["kotlin/rn-android"].read_text(), KT_GROUP, KT_FIELD),
}

# Swift/Kotlin/Dart/TS nest under one outer RADefaults enum/object, so the outer
# name shows up as a group with no fields. Drop empty groups.
expected = parsed["proto"]
if not expected:
    print("error: parsed no rac_default annotations out of the proto", file=sys.stderr)
    sys.exit(2)

langs = [k for k in parsed if k != "proto"]
problems = []
rows = []

for key in sorted(expected):
    want = expected[key]
    got = {L: parsed[L].get(key) for L in langs}
    bad = [L for L, v in got.items() if v != want]
    rows.append((key, want, bad))
    for L in bad:
        problems.append(
            f"{key}: proto={want} but {L}="
            f"{got[L] if got[L] is not None else '<absent>'}"
        )

if not QUIET:
    w = max(len(k) for k, _, _ in rows)
    print(f"{'field'.ljust(w)}  {'proto'.ljust(14)} languages")
    print("-" * (w + 30))
    for key, want, bad in rows:
        mark = "OK" if not bad else "MISMATCH: " + ", ".join(bad)
        print(f"{key.ljust(w)}  {want.ljust(14)} {mark}")
    print()
    print(f"{len(expected)} pooled defaults x {len(langs)} emitted languages "
          f"= {len(expected) * len(langs)} value checks")

if problems:
    print(f"\n{len(problems)} mismatch(es):", file=sys.stderr)
    for p in problems:
        print(f"  {p}", file=sys.stderr)
    sys.exit(1)

print("OK: every language agrees with idl/sdk_defaults.proto.")
PYEOF
