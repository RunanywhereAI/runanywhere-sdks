#!/usr/bin/env bash
#
# check_no_hardcoded_defaults.sh
#
# Fails CI when SDK source re-declares a default value that idl/sdk_defaults.proto
# (or a rac_default annotation on an existing option message) already declares.
#
# Why this exists: before the central default pool, the same sampling table was
# written out in four SDKs and had drifted to three different VLM max_tokens
# values; the three copies of OkHttpHttpTransport.kt disagreed on stream chunk
# size by 8x; and three SDKs used a VAD floor multiplier of 2.2 against the C
# layer's 2.0. Several of those copies carried comments naming the file they were
# supposed to match, which is documentation of a duplicate rather than a defense
# against one. This gate is the defense.
#
# What it looks for, in first-party SDK source only:
#   - sampling parameters assigned a numeric literal
#     (temperature / top_p / top_k / max_tokens / repetition_penalty / min_p)
#   - HTTP timeout and retry literals
#   - mic and TTS sample rates, VAD thresholds and floor multipliers
#   - the catalogued default VAD model id
#   - control-plane hostnames
#
# Generated output, tests, example apps, vendored code, and developer tools are
# out of scope. Read a value from the generated pool instead of writing it:
#   Swift   RADefaults.<Group>.<field>          (Generated/RADefaultsPool.swift)
#   Kotlin  RADefaults.<Group>.<FIELD>          (generated/RADefaultsPool.kt)
#   Dart    RADefaults<Group>.<field>           (generated/ra_defaults_pool.dart)
#   TS      <group>Defaults.<field>             (@runanywhere/proto-ts/defaults/pool)
#   C/C++   RAC_DEFAULT_<GROUP>_<FIELD>         (rac/rac_defaults_generated.h)
# For LLM/VLM/STT/TTS/RAG/VAD option messages, use the generated defaults()
# factory rather than the pool.
#
# Usage:
#   scripts/validation/gates/check_no_hardcoded_defaults.sh [--list]
#
#   --list  Print every scanned file instead of only violations. Useful when
#           adding a path and checking the scope filter covers it.
#
# Exit codes:
#   0  No re-declared defaults found.
#   1  At least one violation.
#   2  Repo layout unexpected (idl/sdk_defaults.proto missing).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

POOL_PROTO="idl/sdk_defaults.proto"
if [[ ! -f "${POOL_PROTO}" ]]; then
  printf "::error::Missing %s — the default pool is the thing this gate enforces.\n" "${POOL_PROTO}" >&2
  exit 2
fi

LIST_ONLY=0
[[ "${1:-}" == "--list" ]] && LIST_ONLY=1

# ---------------------------------------------------------------------------
# Scope. First-party SDK source for the six platform SDKs plus the two Android
# plugin forks. Deliberately excluded:
#   */generated/*, */Generated/*   the pool and proto output — the declarations
#   *.pb.*, *_pb2*, *.g.dart       proto codegen
#   */_generated_*.py              Python codegen (no generated/ dir there)
#   tests, __tests__, *.spec.*     fixtures legitimately pin literals
#   node_modules, build, dist      not source
#   DevTools, Playground, examples not shipped SDK surface
# ---------------------------------------------------------------------------
# Read loop rather than `mapfile`: macOS ships bash 3.2, which has no mapfile,
# and this gate has to be runnable locally to reproduce a CI failure. Same
# reasoning as bindings/swift/scripts/sync-dist-repo.sh and
# scripts/build/build-core-android.sh.
FILES=()
while IFS= read -r _file; do
  FILES+=("$_file")
done < <(
  find \
    bindings/swift/Sources \
    bindings/kotlin/src/main \
    bindings/flutter/packages \
    bindings/react-native/packages \
    bindings/web/packages \
    bindings/python/runanywhere \
    -type f \
    \( -name '*.swift' -o -name '*.kt' -o -name '*.dart' -o -name '*.ts' -o -name '*.py' \) \
    2>/dev/null \
  | grep -vE '/(generated|Generated)/' \
  | grep -vE '\.(pb|pbenum|pbjson|g)\.dart$' \
  | grep -vE '\.pb\.swift$|\.pb\.go$|_pb2(_grpc)?\.py$' \
  | grep -vE '/_generated_[A-Za-z0-9_]+\.py$' \
  | grep -vE '/node_modules/|/build/|/dist/|/\.dart_tool/' \
  | grep -vE 'runanywhere-(react-native|web)/packages/[^/]+/lib/' \
  | grep -vE '/(tests?|__tests__|Tests)/|\.spec\.[tj]s$|_test\.(py|dart)$|Test\.kt$' \
  | grep -vE '/DevTools/|/example/|/examples/' \
  | sort
)

if (( LIST_ONLY )); then
  printf '%s\n' "${FILES[@]}"
  printf 'scanned %d files\n' "${#FILES[@]}"
  exit 0
fi

if (( ${#FILES[@]} == 0 )); then
  printf "::error::Scope filter matched no files — the SDK layout moved and this gate is now blind.\n" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Patterns. Each entry is "<label>|<extended regex>".
#
# All of them require an assignment to a *literal*, so reading a pool constant
# (`= RADefaults.Network.requestTimeoutMs`) never matches. Zero is allowed
# throughout: proto3 treats it as "unset / let the engine decide", and several
# call sites legitimately assign it as that sentinel. 1.0 is allowed for
# penalties for the same reason (it means "no penalty").
# ---------------------------------------------------------------------------
PATTERNS=(
  "sampling parameter|(temperature|top_?p|top_?k|max_?tokens|repe(at|tition)_?penalty|min_?p)[[:space:]]*[:=][[:space:]]*[0-9]+(_[0-9]+)*(\.[0-9]+)?f?[[:space:]]*[,;)]?[[:space:]]*$"
  "http timeout|(connect|read|write|call|request|resource|streaming|adapter)_?[Tt]ime[Oo]ut(_?[Mm][Ss])?[[:space:]]*[:=][[:space:]]*[0-9]+(_[0-9]+)*"
  "retry policy|(max_?retries|retry_?backoff[A-Za-z_]*)[[:space:]]*[:=][[:space:]]*[0-9]+"
  "stream chunk size|(stream_?chunk_?(size|bytes)|STREAM_CHUNK_SIZE)[[:space:]]*[:=][[:space:]]*[0-9]+"
  "audio sample rate|(sample_?rate(_?hz)?)[[:space:]]*[:=][[:space:]]*(16000|16_000|22050|22_050|44100|48000)"
  "vad threshold|(speech_?rms_?threshold|speech_?floor_?multiplier|energy_?threshold|calibration_?multiplier)[[:space:]]*[:=][[:space:]]*[0-9]*\.[0-9]+f?"
  "default vad model id|['\"]silero-vad['\"]"
  "control-plane host|['\"]https://(dev-)?api\.runanywhere\.ai['\"]|['\"]https://dev\.runanywhere\.local['\"]"
  "path buffer size|(path_?[Bb]uffer_?(size|bytes)|pathBufferSize)[[:space:]]*[:=][[:space:]]*[0-9]+"
  "hybrid confidence|(stt_?confidence_?threshold|HYBRID_STT_CONFIDENCE_THRESHOLD)[[:space:]]*[:=][[:space:]]*[0-9]*\.[0-9]+f?"
)

# Zero and the no-op penalty value are meaningful sentinels, not defaults.
ALLOWED_LITERAL='[:=][[:space:]]*(0|0\.0|0\.0f|1\.0|1\.0f|1|-1)[[:space:]]*[,;)]?[[:space:]]*$'

violations=0
for entry in "${PATTERNS[@]}"; do
  label="${entry%%|*}"
  regex="${entry#*|}"
  while IFS= read -r hit; do
    [[ -z "${hit}" ]] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest%%:*}"
    text="${rest#*:}"

    # Skip comments and doc prose.
    trimmed="$(printf '%s' "${text}" | sed -E 's/^[[:space:]]+//')"
    case "${trimmed}" in
      '//'*|'///'*|'#'*|'*'*|'/*'*|'"""'*) continue ;;
    esac
    # Skip lines already reading the pool or a generated defaults() factory.
    if printf '%s' "${text}" | grep -qE 'RADefaults|RAC_DEFAULT_|[a-zA-Z]+Defaults\.|defaults\(\)'; then
      continue
    fi
    # Skip the allowed sentinels.
    if printf '%s' "${text}" | grep -qE "${ALLOWED_LITERAL}"; then
      continue
    fi
    # Honor an explicit opt-out. The marker must carry a reason after the colon,
    # so silencing the gate stays a deliberate, reviewable act.
    if printf '%s' "${text}" | grep -qE 'not-a-default:[[:space:]]*[^[:space:]]'; then
      continue
    fi
    # Look back a few lines so the reason can be a normal multi-line comment
    # rather than something crammed onto one line.
    # 5 lines: a suppression reason worth reading is usually a short comment
    # block, and the marker sits on its first line.
    window_start=$(( line - 5 ))
    (( window_start < 1 )) && window_start=1
    if (( line > 1 )) && sed -n "${window_start},$(( line - 1 ))p" "${file}" 2>/dev/null \
        | grep -qE 'not-a-default:[[:space:]]*[^[:space:]]'; then
      continue
    fi

    printf "::error file=%s,line=%s::re-declared default (%s): %s\n" \
      "${file}" "${line}" "${label}" "${trimmed}" >&2
    violations=$(( violations + 1 ))
  # -i is required: the patterns are written snake_case, and without it
  # `maxTokens: 256` / `topK = 40` / `topP: 0.9` slip through in every
  # camelCase language. The first version of this gate missed exactly those
  # and only caught the drifted files via their adjacent `temperature` lines.
  done < <(grep -inHE "${regex}" "${FILES[@]}" 2>/dev/null || true)
done

if (( violations > 0 )); then
  cat >&2 <<'EOF'

A default value belongs in idl/sdk_defaults.proto (or as a rac_default annotation
on the option message it configures), not in SDK source. Declare it there, run
idl/codegen/generate_all.sh, and read the generated constant.

If a literal here is genuinely not a default — a spec-fixed constant, a test
fixture, an ABI sentinel — say so in a comment on the line above and give the
value a name that does not look like a default, or extend this gate's scope
filter with the reason.
EOF
  printf '%d re-declared default(s) found.\n' "${violations}" >&2
  exit 1
fi

printf 'OK: no re-declared defaults in %d scanned SDK source files.\n' "${#FILES[@]}"
