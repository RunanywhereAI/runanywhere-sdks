#!/usr/bin/env bash
# check_no_pii_logging.sh
#
# pass2-syn-117 / security-privacy-storage-network-003 regression guard.
# Widened in pass3-syn-098 to scan all of commons features/ and
# infrastructure/, and to flag URL-shaped values in INFO/WARN logs even
# without a destination-path token in the same line.
#
# Prevents reintroduction of the Android logcat leak where signed URLs
# were emitted at INFO level — originally in
# `sdk/runanywhere-commons/src/infrastructure/http/rac_http_download.cpp`,
# but the same hazard exists across any code path that touches signed URLs
# or per-user filesystem paths (features/diffusion, features/rag,
# infrastructure/model_management, infrastructure/network, etc.).
#
# Heuristic:
#
#   1. Scan files under
#      sdk/runanywhere-commons/src/features/
#      sdk/runanywhere-commons/src/infrastructure/
#      — anywhere signed URLs or per-user paths can show up.
#   2. Inside those files, treat as a violation any __android_log_print(...)
#      or RAC_LOG_INFO(...) call whose JOINED argument list contains a %s
#      formatter AND mentions a URL-shaped token (`url`, `download_url`,
#      `signed_url`, `endpoint`, `hf_url`) — independent of any
#      destination-path token. The pre-pass3 AND-only heuristic only
#      caught the exact pass-2 fingerprint and missed renamed-variable
#      leaks (e.g. `endpoint=%s into %s`).
#
# Exits 0 when no offending call sites are found, 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMMONS_SRC="${REPO_ROOT}/sdk/runanywhere-commons/src"

if [[ ! -d "${COMMONS_SRC}" ]]; then
  printf "ERROR: expected commons source root not found: %s\n" "${COMMONS_SRC}" >&2
  exit 2
fi

# pass3-syn-098: widened scope. Any URL-shaped token at INFO is now a
# potential leak regardless of whether a destination is co-logged.
SCAN_PATHS=(
  "${COMMONS_SRC}/features"
  "${COMMONS_SRC}/infrastructure"
)

# Logging macros / functions to guard.
GUARDED_LOGGERS=(
  "__android_log_print"
  "RAC_LOG_INFO"
)

URL_TOKEN_PATTERN='(^|[^A-Za-z_])(url|download_url|signed_url|endpoint|hf_url)([^A-Za-z0-9_]|$)'

violations=0

scan_one_file() {
  local file="$1"
  local logger
  for logger in "${GUARDED_LOGGERS[@]}"; do
    # Flatten each multi-line logger call into one logical line for
    # heuristic matching. We join the logger line with the next ~8 lines.
    local joined_calls
    joined_calls=$(awk -v logger="${logger}" '
      BEGIN { window = 8 }
      { lines[NR] = $0 }
      END {
        for (i = 1; i <= NR; ++i) {
          if (index(lines[i], logger) == 0) continue
          joined = lines[i]
          # Stop accumulating once the logger call'\''s own statement ends
          # (a line containing the call terminator ");"). This keeps
          # legitimate multi-line-call detection while preventing the
          # window from bleeding past the statement into unrelated tokens.
          if (index(lines[i], ");") == 0) {
            for (j = i + 1; j <= i + window && j <= NR; ++j) {
              joined = joined " " lines[j]
              if (index(lines[j], ");") > 0) break
            }
          }
          printf "%d\t%s\n", i, joined
        }
      }
    ' "${file}")

    if [[ -z "${joined_calls}" ]]; then
      continue
    fi

    local hits=""
    while IFS=$'\t' read -r line_no call_text; do
      [[ -z "${call_text}" ]] && continue
      # Must contain %s.
      if ! printf "%s" "${call_text}" | grep -Fq "%s"; then
        continue
      fi
      # pass3-syn-098: flag any URL-shaped token (no longer requires a
      # destination-path token in the same line).
      if printf "%s" "${call_text}" | grep -Eq "${URL_TOKEN_PATTERN}"; then
        hits+="line ${line_no}: ${call_text}"$'\n'
      fi
    done <<< "${joined_calls}"

    if [[ -n "${hits}" ]]; then
      printf "\nFAIL: PII-bearing %s call (URL-shaped token at INFO) in %s:\n" "${logger}" "${file}" >&2
      printf "%s" "${hits}" >&2
      violations=$((violations + 1))
    fi
  done
}

for scan_root in "${SCAN_PATHS[@]}"; do
  if [[ ! -d "${scan_root}" ]]; then
    continue
  fi
  while IFS= read -r -d '' file; do
    scan_one_file "${file}"
  done < <(find "${scan_root}" -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) -print0)
done

if (( violations > 0 )); then
  printf "\ncheck_no_pii_logging.sh: %d violation(s) found.\n" "${violations}" >&2
  printf "Rationale: pass2-syn-117 / pass3-syn-098 — signed URLs must not reach\n" >&2
  printf "  logcat at INFO level (URL query params can carry tokens; HuggingFace\n" >&2
  printf "  endpoints can carry redirect-chain metadata).\n" >&2
  printf "  Downgrade the call to RAC_LOG_DEBUG with a redaction comment, or\n" >&2
  printf "  emit only the filename/identifier without the URL.\n" >&2
  exit 1
fi

printf "check_no_pii_logging.sh: OK (no URL-shaped INFO logs under features/ or infrastructure/)\n"
exit 0
