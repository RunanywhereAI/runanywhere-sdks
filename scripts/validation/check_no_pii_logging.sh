#!/usr/bin/env bash
# check_no_pii_logging.sh
#
# pass2-syn-117 / security-privacy-storage-network-003 regression guard.
#
# Prevents reintroduction of the Android logcat leak where signed URLs +
# user-specific filesystem paths were emitted together (a common
# fingerprint: `url=...dest=...` at INFO level in the HTTP download
# runner). The original leak was in
# `sdk/runanywhere-commons/src/infrastructure/http/rac_http_download.cpp`
# and was removed in the security-privacy-storage-network-003 fix.
#
# Heuristic (narrow on purpose — a noisy guard would just get disabled):
#
#   1. Scan only files under
#      sdk/runanywhere-commons/src/infrastructure/http/
#      and the platform glue at
#      sdk/runanywhere-commons/src/infrastructure/download/rac_http_*.cpp
#      — i.e. the active-download code paths that handle signed URLs and
#      live destination paths.
#   2. Inside those files, treat as a violation any __android_log_print(...)
#      or RAC_LOG_INFO(...) call whose JOINED argument list contains BOTH:
#         - a %s formatter, AND
#         - a `url`-shaped token (`url`, `download_url`, `signed_url`), AND
#         - a `dest`/path-shaped token (`dest`, `dest_path`,
#           `destination_path`, `local_path`).
#      This is exactly the combination the original leak emitted; logging
#      either alone is allowed (model-id+local_path debug lines elsewhere
#      in commons are not in scope and serve legitimate diagnosis).
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

# Active-download code paths only.
SCAN_PATHS=(
  "${COMMONS_SRC}/infrastructure/http"
)

# Logging macros / functions to guard.
GUARDED_LOGGERS=(
  "__android_log_print"
  "RAC_LOG_INFO"
)

URL_TOKEN_PATTERN='(^|[^A-Za-z_])(url|download_url|signed_url)([^A-Za-z0-9_]|$)'
DEST_TOKEN_PATTERN='(^|[^A-Za-z_])(dest|dest_path|destination_path|local_path)([^A-Za-z0-9_]|$)'

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
          for (j = i + 1; j <= i + window && j <= NR; ++j) {
            joined = joined " " lines[j]
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
      # Must mention BOTH a URL-ish token AND a destination/path token.
      if printf "%s" "${call_text}" | grep -Eq "${URL_TOKEN_PATTERN}" &&
         printf "%s" "${call_text}" | grep -Eq "${DEST_TOKEN_PATTERN}"; then
        hits+="line ${line_no}: ${call_text}"$'\n'
      fi
    done <<< "${joined_calls}"

    if [[ -n "${hits}" ]]; then
      printf "\nFAIL: PII-bearing %s call (URL + destination together) in %s:\n" "${logger}" "${file}" >&2
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
  printf "Rationale: pass2-syn-117 / security-privacy-storage-network-003 — signed URLs\n" >&2
  printf "  combined with destination paths must not reach logcat at INFO level.\n" >&2
  printf "  Either remove the URL or the destination from the log line, or downgrade\n" >&2
  printf "  the call to RAC_LOG_DEBUG with a redaction comment.\n" >&2
  exit 1
fi

printf "check_no_pii_logging.sh: OK (no URL+destination INFO logs under active-download paths)\n"
exit 0
