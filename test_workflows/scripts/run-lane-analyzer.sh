#!/usr/bin/env bash
# Read-only lane Analyzer — grades TCs from actions.jsonl + logs, writes reports.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/_session_lib.sh
source "${SCRIPT_DIR}/lib/_session_lib.sh"
# shellcheck source=_log_markers.sh
source "${SCRIPT_DIR}/_log_markers.sh"

usage() {
  cat <<'USAGE'
Usage: run-lane-analyzer.sh <platform> [android|ios] [--run-id ID]

Writes SUMMARY.md, modality_report.md, modality_results.tsv (via lane-finalize).
USAGE
}

platform="${1:?platform required}"
shift
target=""
run_id="${RAC_RUN_ID:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) run_id="$2"; shift 2 ;;
    android|ios) target="$1"; shift ;;
    *) shift ;;
  esac
done
[[ -n "${run_id}" ]] || { echo "RAC_RUN_ID or --run-id required" >&2; exit 2; }

export RAC_RUN_ID="${run_id}"
lane_root="$(rac_session_root "${platform}" "${run_id}" "${target}")"
slug="$(rac_lane_slug "${platform}" "${target}")"
mkdir -p "${lane_root}"

"${SCRIPT_DIR}/lane-finalize.sh" "${platform}" "${target}" 2>/dev/null || true

if [[ "${platform}" == "swift" && -z "${target}" ]]; then
  # shellcheck source=swift/_swift_analyzer.sh
  source "${SCRIPT_DIR}/swift/_swift_analyzer.sh"
  _swift_analyzer_regrade "${lane_root}"
  "${SCRIPT_DIR}/lane-finalize.sh" "${platform}" "${target}" 2>/dev/null || true
fi

results="${lane_root}/modality_results.tsv"
report="${lane_root}/modality_report.md"
summary="${lane_root}/SUMMARY.md"
actions="${lane_root}/actions.jsonl"

pass=0 fail=0 blocked=0 limited=0 na=0
if [[ -f "${results}" ]]; then
  while IFS=$'\t' read -r tc status _rest; do
    [[ "${tc}" == "tc" || -z "${tc}" ]] && continue
    case "${status}" in
      PASS) pass=$((pass+1)) ;;
      FAIL) fail=$((fail+1)) ;;
      BLOCKED) blocked=$((blocked+1)) ;;
      LIMITED) limited=$((limited+1)) ;;
      N/A|DEFERRED|SMOKE_PASS) na=$((na+1)) ;;
    esac
  done < "${results}"
fi

verdict="PASS"
[[ "${fail}" -gt 0 ]] && verdict="FAIL"
[[ "${blocked}" -gt 0 && "${fail}" -eq 0 ]] && verdict="BLOCKED"
[[ "${pass}" -eq 0 && "${fail}" -eq 0 && "${blocked}" -eq 0 ]] && verdict="LIMITED"

cat > "${report}" <<EOF
# Modality Report — ${slug}

| Field | Value |
| --- | --- |
| Run ID | \`${run_id}\` |
| Lane | \`${slug}\` |
| Analyzer | automated (\`run-lane-analyzer.sh\`) |
| Verdict | **${verdict}** |

**Evidence schema:** v2. Analyzer read-only; tests not re-run.

| TC | Status | Notes |
| --- | --- | --- |
EOF

if [[ -f "${results}" ]]; then
  awk -F'\t' 'NR>1 {printf "| %s | %s | %s |\n", $1, $2, $3}' "${results}" >> "${report}"
fi

cat > "${summary}" <<EOF
# Lane Summary — \`${slug}\`

| Metric | Count |
| --- | ---: |
| PASS | ${pass} |
| FAIL | ${fail} |
| BLOCKED | ${blocked} |
| LIMITED | ${limited} |
| N/A / other | ${na} |

**Lane verdict:** ${verdict}

## Top issues

EOF

if [[ ! -f "${actions}" ]]; then
  echo "- No \`actions.jsonl\` — Executor evidence missing" >> "${summary}"
fi
if [[ "${fail}" -gt 0 ]]; then
  awk -F'\t' '$2=="FAIL"{printf "- %s: %s\n", $1, $3}' "${results}" | head -5 >> "${summary}" || true
fi

{
  echo ""
  echo "## Analysis ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo ""
  echo "**Artifacts written:** \`SUMMARY.md\`, \`modality_report.md\`, \`modality_results.tsv\`"
} >> "${lane_root}/RUN_MANIFEST.md" 2>/dev/null || true

echo "Analyzer done: ${lane_root} verdict=${verdict} pass=${pass} fail=${fail} blocked=${blocked}"
