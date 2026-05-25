#!/usr/bin/env bash
# Re-grade iter-5 lane modality_results.tsv using catalog §10 expanded patterns (read-only on executor evidence).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/test_workflows/scripts/_catalog_marker_patterns.sh"

usage() {
  echo "Usage: $0 <lane_evidence_dir> [source_modality_results.tsv]" >&2
  echo "  Writes <lane_evidence_dir>/iter5-regrade/modality_results.tsv + REGRADE_NOTES.md" >&2
}

[[ $# -ge 1 ]] || { usage; exit 1; }

LANE_DIR="$(cd "$1" && pwd)"
SRC_TSV="${2:-${LANE_DIR}/modality_results.tsv}"
OUT_DIR="${LANE_DIR}/iter5-regrade"
OUT_TSV="${OUT_DIR}/modality_results.tsv"
OUT_NOTES="${OUT_DIR}/REGRADE_NOTES.md"

[[ -f "${SRC_TSV}" ]] || { echo "missing ${SRC_TSV}" >&2; exit 1; }

mkdir -p "${OUT_DIR}"

LOG_FILES=()
while IFS= read -r f; do
  LOG_FILES+=("${f}")
done < <(rac_catalog_collect_logs "${LANE_DIR}")

limited_before=0
pass_after=0
converted=0
declare -a conversion_lines=()

{
  echo -e "tc\tstatus\tnotes\tscreenshot"
  while IFS=$'\t' read -r tc status notes screenshot _rest; do
    [[ "${tc}" == "tc" || "${tc}" == "tc_id" ]] && continue
    [[ -z "${tc}" ]] && continue

    new_status="${status}"
    new_notes="${notes}"

    if [[ "${status}" == "LIMITED" ]] && rac_catalog_tc_marker_limited "${tc}" "${notes}"; then
      limited_before=$((limited_before + 1))
      regex="$(rac_catalog_tc_regex "${tc}" || true)"
      if [[ -n "${regex}" ]] && rac_catalog_grep_logs "${regex}" "${LOG_FILES[@]}"; then
        new_status="PASS"
        new_notes="regrade §10: catalog pattern matched (${regex%%|*})"
        converted=$((converted + 1))
        conversion_lines+=("${tc}: LIMITED -> PASS (${notes})")
      fi
    fi

    [[ "${new_status}" == "PASS" ]] && pass_after=$((pass_after + 1))
    if [[ -n "${screenshot:-}" ]]; then
      echo -e "${tc}\t${new_status}\t${new_notes}\t${screenshot}"
    else
      echo -e "${tc}\t${new_status}\t${new_notes}"
    fi
  done < "${SRC_TSV}"
} > "${OUT_TSV}"

{
  echo "# iter5-regrade — CLUSTER-26 / ANALYZER-MARKER-001"
  echo
  echo "- Source: \`${SRC_TSV#${REPO_ROOT}/}\`"
  echo "- Log files searched: ${#LOG_FILES[@]}"
  echo "- LIMITED marker rows before: ${limited_before}"
  echo "- LIMITED -> PASS conversions: ${converted}"
  echo
  echo "## Conversions"
  if [[ ${#conversion_lines[@]} -eq 0 ]]; then
    echo "(none — no alternate §10 patterns matched captured logs)"
  else
    for line in "${conversion_lines[@]}"; do
      echo "- ${line}"
    done
  fi
  echo
  echo "## Pattern source"
  echo "- \`test_workflows/scripts/_catalog_marker_patterns.sh\`"
  echo "- \`test_workflows/instructions/cross-platform-e2e-test-catalog.md\` §10"
} > "${OUT_NOTES}"

echo "${OUT_DIR}|limited_before=${limited_before}|converted=${converted}"
