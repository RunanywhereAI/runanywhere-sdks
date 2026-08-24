#!/usr/bin/env bash
# Assert the pinned QAIRT runtime is the same QAIRT the pinned QHexRT engine was
# built against.
#
# WHY THIS IS NOT OPTIONAL
# ------------------------
# The engine (QHEXRT_*) and the runtime (QAIRT_RUNTIME_*) are two independently
# bumpable pins, on purpose -- the QAIRT SDK version and the engine version move
# on different schedules. The cost of that flexibility is that they CAN drift,
# and a drifted pair passes every other check in the pipeline: both archives
# download, both checksums verify, both receipts validate, the engine links and
# reports routable. It then crashes on a real Hexagon device, which is the one
# place nothing in CI can see.
#
# This is the only check that compares the two. It costs a few lines and closes
# the single most likely failure mode of the split-pin design.
#
# Both files record the same fact from different sides:
#   engine receipt : build.qnn_sdk.{metadata_file,metadata_sha256}
#   runtime receipt: {identity_file,identity_sha256}
# They are produced by different tools in different repos, so agreement is real
# evidence rather than a value compared against a copy of itself.
#
# Exit 0 = paired (or nothing selected, which is the public/stub build path).
# Exit 1 = drifted; the build must not proceed.
#
# Usage: check_qairt_pairing.sh [--platform <arm64-v8a|win-arm64>]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PY_BIN="${PYTHON_BIN:-python3}"
command -v "$PY_BIN" >/dev/null 2>&1 || PY_BIN=python

PLATFORMS=(arm64-v8a win-arm64)
if [[ "${1:-}" == "--platform" ]]; then
    [[ -n "${2:-}" ]] || { echo "[ERROR] --platform needs a value" >&2; exit 2; }
    PLATFORMS=("$2")
fi

checked=0
for plat in "${PLATFORMS[@]}"; do
    engine="${REPO_ROOT}/engines/qhexrt/prebuilt/current/qhexrt-prebuilt.json"
    runtime="${REPO_ROOT}/engines/qhexrt/prebuilt/qairt-runtime/${plat}/current/qairt-runtime.json"

    # Nothing selected is the intentional public/stub outcome, not a failure.
    [[ -f "$engine" && -f "$runtime" ]] || continue

    # Only compare when the selected engine payload IS this platform's -- a
    # single `current` selects one engine ABI at a time, so comparing an
    # arm64-v8a runtime against a selected win-arm64 engine would be a false
    # alarm rather than real drift.
    sel_abi="$("$PY_BIN" -c "
import json,sys
print(json.load(open(sys.argv[1], encoding='utf-8')).get('android_abi',''))" "$engine")"
    [[ "$sel_abi" == "$plat" ]] || continue

    "$PY_BIN" - "$engine" "$runtime" "$plat" <<'PY'
import json, sys
engine_path, runtime_path, plat = sys.argv[1:4]
engine = json.load(open(engine_path, encoding="utf-8"))
runtime = json.load(open(runtime_path, encoding="utf-8"))

qnn = engine.get("build", {}).get("qnn_sdk", {})
e_file, e_sha = qnn.get("metadata_file"), qnn.get("metadata_sha256")
r_file, r_sha = runtime.get("identity_file"), runtime.get("identity_sha256")

if not e_sha or not r_sha:
    sys.exit(f"[FAIL] {plat}: a receipt is missing its QAIRT identity "
             f"(engine={e_sha!r} runtime={r_sha!r})")
if e_file != r_file:
    sys.exit(f"[FAIL] {plat}: identity files differ: engine={e_file!r} runtime={r_file!r}")
if e_sha != r_sha:
    sys.exit(
        f"[FAIL] {plat}: the pinned QAIRT runtime is NOT the SDK this engine was built against.\n"
        f"        engine  expects {e_file} sha256 {e_sha}\n"
        f"        runtime provides {r_file} sha256 {r_sha}\n"
        f"        QHEXRT_* and QAIRT_RUNTIME_* in core/VERSIONS have drifted. Re-pin one of them;\n"
        f"        shipping this pair links an engine against a runtime it never saw."
    )
print(f"[OK] {plat}: engine and QAIRT runtime agree "
      f"({r_file} {r_sha[:16]}..., QAIRT {runtime.get('qairt_version')})")
PY
    checked=$((checked + 1))
done

if [[ "$checked" -eq 0 ]]; then
    echo "[OK] no engine+runtime pair selected — nothing to pair (public/stub build)"
fi
