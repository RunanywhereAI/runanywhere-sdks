#!/usr/bin/env bash
# Re-grade lane modality_results.tsv using catalog §10 patterns + §7.0 UI-proves rule.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/test_workflows/scripts/_catalog_marker_patterns.sh"

usage() {
  echo "Usage: $0 <lane_evidence_dir> [source_modality_results.tsv]" >&2
  echo "  Writes <out_dir>/modality_results.tsv + REGRADE_NOTES.md" >&2
  echo "  Env: RAC_REGRADE_SUBDIR (default iter5-regrade), RAC_REGRADE_OUT_DIR (override out path)" >&2
}

[[ $# -ge 1 ]] || { usage; exit 1; }

LANE_DIR="$(cd "$1" && pwd)"
SRC_TSV="${2:-${LANE_DIR}/modality_results.tsv}"
if [[ "${SRC_TSV}" != /* ]]; then
  SRC_TSV="${LANE_DIR}/${SRC_TSV}"
fi
OUT_SUBDIR="${RAC_REGRADE_SUBDIR:-iter5-regrade}"
OUT_DIR="${RAC_REGRADE_OUT_DIR:-${LANE_DIR}/${OUT_SUBDIR}}"
OUT_TSV="${OUT_DIR}/modality_results.tsv"
OUT_NOTES="${OUT_DIR}/REGRADE_NOTES.md"
CLUSTER_TAG="${RAC_REGRADE_CLUSTER_TAG:-CLUSTER-26 / ANALYZER-MARKER-001}"

[[ -f "${SRC_TSV}" ]] || { echo "missing ${SRC_TSV}" >&2; exit 1; }

EVIDENCE_ROOT="$(rac_catalog_evidence_root "${LANE_DIR}")"
mkdir -p "${OUT_DIR}"

LOG_FILES=()
while IFS= read -r f; do
  [[ -n "${f}" ]] && LOG_FILES+=("${f}")
done < <(rac_catalog_collect_logs "${EVIDENCE_ROOT}")

limited_before=0
pattern_converted=0
ui_proves_converted=0
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
        pattern_converted=$((pattern_converted + 1))
        conversion_lines+=("${tc}: LIMITED -> PASS §10 (${notes})")
      elif rac_catalog_ui_proves_pass "${EVIDENCE_ROOT}" "${tc}" "${screenshot:-}"; then
        new_status="PASS"
        new_notes="regrade §7.0: PASS-WHEN-UI-PROVES (action+screenshot, no fatal/counter-evidence)"
        ui_proves_converted=$((ui_proves_converted + 1))
        conversion_lines+=("${tc}: LIMITED -> PASS §7.0 UI-proves (${notes})")
      fi
    fi

    if [[ -n "${screenshot:-}" ]]; then
      echo -e "${tc}\t${new_status}\t${new_notes}\t${screenshot}"
    else
      echo -e "${tc}\t${new_status}\t${new_notes}"
    fi
  done < "${SRC_TSV}"
} > "${OUT_TSV}"

converted=$((pattern_converted + ui_proves_converted))

{
  echo "# ${OUT_SUBDIR} — ${CLUSTER_TAG}"
  echo
  echo "- Source: \`${SRC_TSV#${REPO_ROOT}/}\`"
  echo "- Evidence root: \`${EVIDENCE_ROOT#${REPO_ROOT}/}\`"
  echo "- Log files searched: ${#LOG_FILES[@]}"
  echo "- LIMITED marker rows before: ${limited_before}"
  echo "- LIMITED -> PASS conversions: ${converted} (§10=${pattern_converted}, §7.0 UI-proves=${ui_proves_converted})"
  echo
  echo "## Conversions"
  if [[ ${#conversion_lines[@]} -eq 0 ]]; then
    echo "(none — no §10 patterns or §7.0 UI evidence matched)"
  else
    for line in "${conversion_lines[@]}"; do
      echo "- ${line}"
    done
  fi
  echo
  echo "## Pattern source"
  echo "- \`test_workflows/scripts/_catalog_marker_patterns.sh\`"
  echo "- \`test_workflows/instructions/cross-platform-e2e-test-catalog.md\` §10"
  echo "- \`test_workflows/instructions/reusable-full-matrix-e2e-loop-prompt.md\` §7.0 PASS-WHEN-UI-PROVES"
} > "${OUT_NOTES}"

echo "${OUT_DIR}|limited_before=${limited_before}|converted=${converted}|pattern=${pattern_converted}|ui_proves=${ui_proves_converted}"
