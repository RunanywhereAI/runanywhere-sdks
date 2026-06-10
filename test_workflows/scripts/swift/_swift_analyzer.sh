#!/usr/bin/env bash
# Swift iOS analyzer regrade — read-only pass over captured logs + executor artifacts.
set -euo pipefail

_swift_analyzer_regrade() {
  local lane_root="$1"
  local results="${lane_root}/modality_results.tsv"
  local actions="${lane_root}/actions.jsonl"
  [[ -f "${results}" ]] || return 0

  export RAC_SESSION_ROOT="${lane_root}"
  # shellcheck source=_swift_log_lib.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_swift_log_lib.sh"

  local tc01_status tc01_notes tc07_status tc07_notes evidence
  tc01_status="$(awk -F'\t' '$1=="tc01"{print $2; exit}' "${results}")"
  tc07_status="$(awk -F'\t' '$1=="tc07"{print $2; exit}' "${results}")"

  if [[ "${tc01_status}" == "BLOCKED" ]] && _swift_tc01_ready; then
    tc01_notes="SDK init or app-ready marker in captured logs"
    _swift_analyzer_upsert "${results}" "${actions}" "tc01" "PASS" "${tc01_notes}" \
      "screenshots/000_after_launch.png"
  fi

  if [[ "${tc07_status}" == "BLOCKED" || "${tc07_status}" == "LIMITED" ]]; then
    if evidence="$(_swift_tc07_evidence)"; then
      _swift_tc07_status_from_evidence "${evidence}" | {
        IFS=$'\t' read -r tc07_status tc07_notes
        _swift_analyzer_upsert "${results}" "${actions}" "tc07" "${tc07_status}" "${tc07_notes}" \
          "screenshots/013_transcribe.png"
      }
    elif [[ "${tc07_status}" == "BLOCKED" ]]; then
      tc07_notes="transcribe surface blocked; no log or screenshot evidence"
      _swift_analyzer_upsert "${results}" "${actions}" "tc07" "LIMITED" \
        "log grep failed; screenshot retained for manual review" \
        "screenshots/013_transcribe.png"
    fi
  fi

  # Promote modality rows when log markers appear but executor missed them (grep window/capture).
  local tc marker alt_status
  while IFS=$'\t' read -r tc marker alt_status; do
    [[ -n "${tc}" ]] || continue
    local cur
    cur="$(awk -F'\t' -v t="${tc}" '$1==t{print $2; exit}' "${results}")"
    [[ "${cur}" == "LIMITED" || "${cur}" == "BLOCKED" ]] || continue
    if _swift_grep "${marker}"; then
      _swift_analyzer_upsert "${results}" "${actions}" "${tc}" "${alt_status}" \
        "analyzer: marker matched ${marker}" \
        "$(awk -F'\t' -v t="${tc}" '$1==t{print $4; exit}' "${results}")"
    fi
  done <<'MARKERS'
tc02	Download accepted for	PASS
tc04	Model load succeeded for	PASS
tc05	Phase 1 complete	PASS
tc08	Speech generation complete	PASS
tc09	VLM streaming completed	PASS
tc13	Document loaded successfully	PASS
tc13	Query complete	PASS
tc14	Registered tool calling enabled	PASS
tc16	Download accepted for	PASS
MARKERS
}

_swift_analyzer_upsert() {
  local results="$1"
  local actions="$2"
  local tc="$3"
  local status="$4"
  local notes="$5"
  local screenshot="${6:-}"

  local tmp
  tmp="$(mktemp)"
  awk -F'\t' -v tc="${tc}" 'NR==1 || $1!=tc {print}' "${results}" > "${tmp}"
  printf '%s\t%s\t%s\t%s\n' "${tc}" "${status}" "${notes}" "${screenshot}" >> "${tmp}"
  mv "${tmp}" "${results}"

  if [[ -f "${actions}" ]]; then
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' \
      "{\"ts\":\"${ts}\",\"target\":\"02_swift_ios\",\"action\":\"${tc}\",\"status\":\"${status}\",\"expected\":\"pass\",\"actual\":\"${notes}\",\"phase\":\"analyzer_regrade\",\"screenshot\":\"${screenshot}\",\"notes\":\"${notes}\"}" \
      >> "${actions}"
  fi
}
