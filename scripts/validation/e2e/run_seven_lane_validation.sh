#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_validation_lib.sh"

lane_data() {
  cat <<'LANES'
01_android_kotlin|Kotlin|Android|Android Kotlin SDK
02_ios_swift|Swift|iOS|iOS Swift SDK
03_react_native_android|React Native|Android|React Native Android Target
04_react_native_ios|React Native|iOS|React Native iOS Target
05_flutter_android|Flutter|Android|Flutter Android Target
06_flutter_ios|Flutter|iOS|Flutter iOS Target
07_web|Web|Browser|Web Target
LANES
}

usage() {
  cat <<'USAGE'
Usage: scripts/validation/e2e/run_seven_lane_validation.sh [options]

Creates the standard seven-lane evidence folder under test_workflows/logs/.
The shell wrapper cannot drive Mobile MCP or browser MCP by itself; target
agents should add command logs, actions.jsonl, modality_table.tsv, screenshots,
videos, logs, and agent reports inside the generated lane folders.

Options:
  --with-preflight       Run global source checks and commons proto checks first.
  --dry-run              Seed no-device BLOCKED evidence rows and self-check them.
  --self-check           Validate the generated evidence schema before exiting.
  --check-only RUN_DIR   Validate an existing run folder and exit.
  --report               Generate a unified REPORT.md summary after the run.
  -h, --help             Show this help text.
USAGE
}

WITH_PREFLIGHT=0
DRY_RUN=0
SELF_CHECK=0
CHECK_ONLY=""
GENERATE_REPORT=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --with-preflight)
      WITH_PREFLIGHT=1
      ;;
    --dry-run)
      DRY_RUN=1
      SELF_CHECK=1
      ;;
    --self-check)
      SELF_CHECK=1
      ;;
    --check-only)
      if [[ "$#" -lt 2 ]]; then
        printf "error: --check-only requires RUN_DIR\n" >&2
        usage >&2
        exit 2
      fi
      CHECK_ONLY="$2"
      shift
      ;;
    --report)
      GENERATE_REPORT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf "error: unknown argument: %s\n" "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# generate_report TARGET_RUN_DIR
#
# Reads the TSV evidence files in TARGET_RUN_DIR and writes a unified
# REPORT.md.  The report is both human-readable and machine-parseable
# (consistent markdown table format).
# ---------------------------------------------------------------------------
generate_report() {
  local run_dir="$1"
  local report="${run_dir}/REPORT.md"
  local commit_sha
  local mode="real"
  local schema_version="2"
  local timestamp
  local validator_summary=""

  commit_sha="$(git -C "$(validation_repo_root)" rev-parse --short HEAD 2>/dev/null || printf "unknown")"
  timestamp="$(date -Iseconds)"

  # Detect mode from machine_summary.json if available.
  if [[ -f "${run_dir}/machine_summary.json" ]]; then
    if grep -q '"dry_run": true' "${run_dir}/machine_summary.json"; then
      mode="dry-run"
    fi
  fi

  # Run the Python validator and capture its stdout summary line.
  set +e
  validator_summary="$(python3 "${SCRIPT_DIR}/validate_seven_lane_evidence.py" "${run_dir}" 2>/dev/null | head -1)"
  set -e

  {
    # ---- Header ----
    printf "# Seven-Lane Validation Report\n\n"
    printf "| Field | Value |\n"
    printf "| --- | --- |\n"
    printf "| Timestamp | %s |\n" "${timestamp}"
    printf "| Commit | \`%s\` |\n" "${commit_sha}"
    printf "| Evidence schema version | %s |\n" "${schema_version}"
    printf "| Mode | %s |\n" "${mode}"
    printf "| Run directory | \`%s\` |\n" "${run_dir}"
    if [[ -n "${validator_summary}" ]]; then
      printf "| Schema validation | %s |\n" "${validator_summary}"
    fi
    printf "\n"

    # ---- Pre-flight Results ----
    local source_checks="${run_dir}/global/source-checks/summary.tsv"
    local proto_checks="${run_dir}/global/commons-proto-checks/summary.tsv"
    if [[ -f "${source_checks}" ]] || [[ -f "${proto_checks}" ]]; then
      printf "## Pre-flight Results\n\n"
      printf "| Check | Status | Exit | Log |\n"
      printf "| --- | --- | ---: | --- |\n"
      if [[ -f "${source_checks}" ]]; then
        awk -F '\t' 'NR > 1 && NF >= 4 { printf "| %s | %s | %s | `%s` |\n", $1, $2, $3, $4 }' "${source_checks}"
      fi
      if [[ -f "${proto_checks}" ]]; then
        awk -F '\t' 'NR > 1 && NF >= 4 { printf "| %s | %s | %s | `%s` |\n", $1, $2, $3, $4 }' "${proto_checks}"
      fi
      printf "\n"
    fi

    # ---- Per-Lane Build Summary ----
    printf "## Per-Lane Build Summary\n\n"
    printf "| Lane | SDK | Platform | Build | Install | Launch | Status |\n"
    printf "| --- | --- | --- | --- | --- | --- | --- |\n"

    while IFS='|' read -r lane sdk platform title; do
      [[ -z "${lane}" ]] && continue
      local lane_cmd="${run_dir}/${lane}/command_summary.tsv"
      local build_status="-"
      local install_status="-"
      local launch_status="-"
      local lane_status="-"

      if [[ -f "${lane_cmd}" ]]; then
        # Extract statuses from command_summary rows by matching name patterns.
        build_status="$(awk -F '\t' 'NR > 1 && $1 ~ /build/ { print $2; exit }' "${lane_cmd}")"
        install_status="$(awk -F '\t' 'NR > 1 && $1 ~ /install/ { print $2; exit }' "${lane_cmd}")"
        launch_status="$(awk -F '\t' 'NR > 1 && $1 ~ /launch/ { print $2; exit }' "${lane_cmd}")"
        build_status="${build_status:-"-"}"
        install_status="${install_status:-"-"}"
        launch_status="${launch_status:-"-"}"
      fi

      # Derive lane status from modality_table: worst status wins.
      local lane_mod="${run_dir}/${lane}/modality_table.tsv"
      if [[ -f "${lane_mod}" ]]; then
        lane_status="$(awk -F '\t' '
          BEGIN { worst = "PASS"; rank["PASS"] = 1; rank["SMOKE_PASS"] = 2; rank["LIMITED"] = 3; rank["N/A"] = 1; rank["BLOCKED"] = 4; rank["FAIL"] = 5 }
          NR > 1 && NF >= 2 {
            s = $2
            if (rank[s]+0 > rank[worst]+0) worst = s
          }
          END { print worst }
        ' "${lane_mod}")"
      fi

      # For dry-run, if no meaningful build/install/launch rows exist, mark as BLOCKED.
      if [[ "${build_status}" == "-" && "${install_status}" == "-" && "${launch_status}" == "-" ]]; then
        if awk -F '\t' 'NR > 1 && $1 ~ /dry_run/ { found = 1 } END { exit !found }' "${lane_cmd}" 2>/dev/null; then
          lane_status="BLOCKED"
        fi
      fi

      printf "| %s | %s | %s | %s | %s | %s | %s |\n" \
        "${lane}" "${sdk}" "${platform}" "${build_status}" "${install_status}" "${launch_status}" "${lane_status}"
    done < <(lane_data)
    printf "\n"

    # ---- Modality Coverage Matrix ----
    printf "## Modality Coverage Matrix\n\n"

    # Collect the union of all modalities across all lanes.
    local all_modalities=""
    while IFS='|' read -r lane sdk platform title; do
      [[ -z "${lane}" ]] && continue
      local lane_mod="${run_dir}/${lane}/modality_table.tsv"
      if [[ -f "${lane_mod}" ]]; then
        local mods
        mods="$(awk -F '\t' 'NR > 1 && NF >= 1 { print $1 }' "${lane_mod}")"
        if [[ -n "${mods}" ]]; then
          all_modalities="${all_modalities}${all_modalities:+$'\n'}${mods}"
        fi
      fi
    done < <(lane_data)

    # Deduplicate and sort modalities.
    local sorted_modalities
    sorted_modalities="$(printf "%s\n" "${all_modalities}" | sort -u)"

    if [[ -n "${sorted_modalities}" ]]; then
      # Print table header.
      printf "| Modality | Android Kotlin | iOS Swift | RN Android | RN iOS | Flutter Android | Flutter iOS | Web |\n"
      printf "| --- | --- | --- | --- | --- | --- | --- | --- |\n"

      while IFS= read -r modality; do
        [[ -z "${modality}" ]] && continue
        printf "| %s" "${modality}"

        while IFS='|' read -r lane sdk platform title; do
          [[ -z "${lane}" ]] && continue
          local lane_mod="${run_dir}/${lane}/modality_table.tsv"
          local cell_status="-"
          if [[ -f "${lane_mod}" ]]; then
            cell_status="$(awk -F '\t' -v mod="${modality}" 'NR > 1 && $1 == mod { print $2; exit }' "${lane_mod}")"
            cell_status="${cell_status:-"-"}"
          fi
          printf " | %s" "${cell_status}"
        done < <(lane_data)

        printf " |\n"
      done <<< "${sorted_modalities}"
    else
      printf "_No modality data found in any lane._\n"
    fi
    printf "\n"

    # ---- Failure Summary ----
    printf "## Failure Summary\n\n"
    local fail_file="${run_dir}/failure_summary.tsv"
    if [[ -f "${fail_file}" ]]; then
      local fail_count
      fail_count="$(awk -F '\t' 'NR > 1 && NF >= 2 { count++ } END { print count+0 }' "${fail_file}")"

      if [[ "${fail_count}" -gt 0 ]]; then
        printf "| ID | Lane | Modality | Severity | Summary | Next Action |\n"
        printf "| --- | --- | --- | --- | --- | --- |\n"
        awk -F '\t' 'NR > 1 && NF >= 8 { printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $6, $8 }' "${fail_file}"
      else
        printf "_No failures recorded._\n"
      fi
    else
      printf "_failure_summary.tsv not found._\n"
    fi
    printf "\n"

    # ---- Convergence Metrics ----
    printf "## Convergence Metrics\n\n"

    # Count all modality cells and statuses across all lanes.
    local total_cells=0
    local pass_count=0
    local fail_count=0
    local blocked_count=0
    local limited_count=0
    local na_count=0
    local smoke_pass_count=0

    while IFS='|' read -r lane sdk platform title; do
      [[ -z "${lane}" ]] && continue
      local lane_mod="${run_dir}/${lane}/modality_table.tsv"
      if [[ -f "${lane_mod}" ]]; then
        local counts
        counts="$(awk -F '\t' '
          NR > 1 && NF >= 2 {
            total++
            s = $2
            if (s == "PASS") pass++
            else if (s == "FAIL") fail++
            else if (s == "BLOCKED") blocked++
            else if (s == "LIMITED") limited++
            else if (s == "N/A") na++
            else if (s == "SMOKE_PASS") smoke++
          }
          END {
            printf "%d %d %d %d %d %d %d", total, pass, fail, blocked, limited, na, smoke
          }
        ' "${lane_mod}")"
        local t p f b l n s
        read -r t p f b l n s <<< "${counts}"
        total_cells=$((total_cells + t))
        pass_count=$((pass_count + p))
        fail_count=$((fail_count + f))
        blocked_count=$((blocked_count + b))
        limited_count=$((limited_count + l))
        na_count=$((na_count + n))
        smoke_pass_count=$((smoke_pass_count + s))
      fi
    done < <(lane_data)

    local pass_rate="0.0"
    if [[ "${total_cells}" -gt 0 ]]; then
      pass_rate="$(awk "BEGIN { printf \"%.1f\", (${pass_count} + ${na_count}) * 100.0 / ${total_cells} }")"
    fi

    printf "| Metric | Value |\n"
    printf "| --- | ---: |\n"
    printf "| total_modality_cells | %d |\n" "${total_cells}"
    printf "| pass_count | %d |\n" "${pass_count}"
    printf "| fail_count | %d |\n" "${fail_count}"
    printf "| blocked_count | %d |\n" "${blocked_count}"
    printf "| limited_count | %d |\n" "${limited_count}"
    printf "| na_count | %d |\n" "${na_count}"
    printf "| smoke_pass_count | %d |\n" "${smoke_pass_count}"
    printf "| pass_rate | %s%% |\n" "${pass_rate}"
    printf "| regression_count | 0 |\n"
    printf "\n"

    # ---- Footer ----
    if [[ "${mode}" == "dry-run" ]]; then
      printf "%s\n\n" "---"
      printf "_This report was generated from a dry-run. All lanes contain synthetic BLOCKED evidence only. "
      printf "No devices, simulators, browsers, models, or inference were used._\n"
    fi

  } > "${report}"

  printf "Report written: %s\n" "${report}"
}

if [[ -n "${CHECK_ONLY}" ]]; then
  set +e
  python3 "${SCRIPT_DIR}/validate_seven_lane_evidence.py" "${CHECK_ONLY}"
  check_exit=$?
  set -e
  if [[ "${GENERATE_REPORT}" -eq 1 ]]; then
    generate_report "${CHECK_ONLY}"
  fi
  exit "${check_exit}"
fi

VALIDATION_REPO_ROOT="$(validation_repo_root)"
VALIDATION_BUILD_ROOT="${VALIDATION_BUILD_ROOT:-${VALIDATION_REPO_ROOT}/build/validation}"
VALIDATION_STAMP="${VALIDATION_STAMP:-$(date +"%Y%m%d-%H%M%S")}"
RUN_DIR="${VALIDATION_RUN_DIR:-${VALIDATION_REPO_ROOT}/test_workflows/logs/${VALIDATION_STAMP}-seven-lane-validation}"

mkdir -p "${RUN_DIR}/global/logs" "${VALIDATION_BUILD_ROOT}"
printf "name\tstatus\texit_code\tlog\n" > "${RUN_DIR}/summary.tsv"
printf "id\tlane\tmodality\tseverity\tevidence\tsummary\towner_area\tnext_action\n" > "${RUN_DIR}/failure_summary.tsv"

write_machine_summary() {
  local dry_run_json="false"
  local with_preflight_json="false"
  local self_check_json="false"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    dry_run_json="true"
  fi
  if [[ "${WITH_PREFLIGHT}" -eq 1 ]]; then
    with_preflight_json="true"
  fi
  if [[ "${SELF_CHECK}" -eq 1 ]]; then
    self_check_json="true"
  fi

  cat > "${RUN_DIR}/machine_summary.json" <<JSON
{
  "evidence_schema_version": 2,
  "run_dir": "${RUN_DIR}",
  "build_root": "${VALIDATION_BUILD_ROOT}",
  "dry_run": ${dry_run_json},
  "with_preflight": ${with_preflight_json},
  "self_check": ${self_check_json},
  "required_action_phases": [
    "clean_install",
    "model_download",
    "model_load",
    "inference",
    "modality_result"
  ],
  "lane_files": [
    "agent_report.md",
    "actions.jsonl",
    "command_summary.tsv",
    "modality_table.tsv",
    "logs/",
    "screenshots/",
    "videos/"
  ],
  "summary_file": "summary.tsv",
  "failure_summary_file": "failure_summary.tsv"
}
JSON
}

write_lane_report_template() {
  local lane="$1"
  local sdk="$2"
  local platform="$3"
  local title="$4"

  cat > "${RUN_DIR}/${lane}/agent_report.md" <<EOF
# Target Report: ${lane}

## Environment
- SDK: ${sdk}
- Platform: ${platform}
- Device/simulator/browser: TODO
- App package or bundle: TODO
- Commit: TODO
- Build artifact: TODO

## Fresh Install
- Uninstall command: TODO
- Install command: TODO
- Launch command: TODO
- Clean launch screenshot: screenshots/000_launch.png
- Foreground app verified: TODO

## Continuous Logging
- Log start command: TODO
- Log stop command: TODO
- Main log file: TODO
- Crash log file: TODO

## Build Results
| Step | Status | Log |
| --- | --- | --- |

## Modality Results
| Modality | Status | Model | Downloaded | Loaded | Inference | Evidence | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Logs Reviewed
| Log | Finding |
| --- | --- |

## Screenshots Reviewed
| Screenshot | Finding |
| --- | --- |

## C++/Proto Ownership Findings
- Business logic duplicated outside C++: TODO
- Platform-only code confirmed: TODO
- API/type naming drift: TODO

## Final Status
- Status: TODO
- Blocking failures: TODO
- Limited areas: TODO

Evidence files for this lane:

- actions.jsonl: one v2 JSON object per user-visible action.
- command_summary.tsv: one row per command or action group run for this lane.
- modality_table.tsv: one row per modality, including log_paths and screenshots.
- logs/: command, device, simulator, browser, and inspection logs.
- screenshots/: launch and per-action screenshots.
EOF
}

dry_run_failure_id() {
  case "$1" in
    01_android_kotlin) printf "ANDROID-KOTLIN-DRY-RUN-NO-DEVICE\n" ;;
    02_ios_swift) printf "SWIFT-IOS-DRY-RUN-NO-SIMULATOR\n" ;;
    03_react_native_android) printf "RN-ANDROID-DRY-RUN-NO-DEVICE\n" ;;
    04_react_native_ios) printf "RN-IOS-DRY-RUN-NO-SIMULATOR\n" ;;
    05_flutter_android) printf "FLUTTER-ANDROID-DRY-RUN-NO-DEVICE\n" ;;
    06_flutter_ios) printf "FLUTTER-IOS-DRY-RUN-NO-SIMULATOR\n" ;;
    07_web) printf "WEB-DRY-RUN-NO-BROWSER\n" ;;
    *) printf "GLOBAL-DRY-RUN-NO-TARGET\n" ;;
  esac
}

append_dry_run_action() {
  local lane="$1"
  local sdk="$2"
  local platform="$3"
  local modality="$4"
  local phase="$5"
  local action="$6"
  local expected="$7"
  local actual="$8"
  local screenshot="$9"
  local log="${10}"
  local model_id="${11}"
  local notes="${12}"

  printf '{"ts":"%s","target":"%s","sdk":"%s","platform":"%s","modality":"%s","phase":"%s","action":"%s","expected":"%s","actual":"%s","status":"BLOCKED","screenshot":"%s","logs":["%s"],"modelId":"%s","notes":"%s"}\n' \
    "$(date -Iseconds)" \
    "${lane}" \
    "${sdk}" \
    "${platform}" \
    "${modality}" \
    "${phase}" \
    "${action}" \
    "${expected}" \
    "${actual}" \
    "${screenshot}" \
    "${log}" \
    "${model_id}" \
    "${notes}" >> "${RUN_DIR}/${lane}/actions.jsonl"
}

seed_dry_run_lane_evidence() {
  local lane="$1"
  local sdk="$2"
  local platform="$3"
  local lane_dir="${RUN_DIR}/${lane}"
  local notes="Dry-run schema fixture only; no device, simulator, browser, model download, model load, or inference ran."

  for name in clean_install model_download model_load inference modality_result; do
    printf "Dry-run evidence placeholder for %s/%s.\n%s\n" "${lane}" "${name}" "${notes}" \
      > "${lane_dir}/logs/dry_run_${name}.log"
    : > "${lane_dir}/screenshots/dry_run_${name}.png"
  done

  {
    printf "name\tstatus\texit_code\tlog\n"
    printf "dry_run_evidence_seed\tPASS\t0\tlogs/dry_run_clean_install.log\n"
  } > "${lane_dir}/command_summary.tsv"

  append_dry_run_action "${lane}" "${sdk}" "${platform}" "run" "clean_install" \
    "dry_run_clean_install_blocked" \
    "clean uninstall, build, install, launch, and launch screenshot evidence can be captured" \
    "dry run created schema-valid placeholder paths without contacting a target" \
    "screenshots/dry_run_clean_install.png" \
    "logs/dry_run_clean_install.log" \
    "n/a" \
    "${notes}"

  append_dry_run_action "${lane}" "${sdk}" "${platform}" "llm" "model_download" \
    "dry_run_model_download_blocked" \
    "model download action captures a screenshot and download logs" \
    "dry run did not download a model; placeholder evidence validates path shape" \
    "screenshots/dry_run_model_download.png" \
    "logs/dry_run_model_download.log" \
    "dry-run-model" \
    "${notes}"

  append_dry_run_action "${lane}" "${sdk}" "${platform}" "llm" "model_load" \
    "dry_run_model_load_blocked" \
    "model load action captures a loaded-state screenshot and memory/load logs" \
    "dry run did not load a model; placeholder evidence validates path shape" \
    "screenshots/dry_run_model_load.png" \
    "logs/dry_run_model_load.log" \
    "dry-run-model" \
    "${notes}"

  append_dry_run_action "${lane}" "${sdk}" "${platform}" "llm" "inference" \
    "dry_run_inference_blocked" \
    "inference action captures input, output, screenshot, and runtime logs" \
    "dry run did not run inference; placeholder evidence validates path shape" \
    "screenshots/dry_run_inference.png" \
    "logs/dry_run_inference.log" \
    "dry-run-model" \
    "${notes}"

  append_dry_run_action "${lane}" "${sdk}" "${platform}" "llm" "modality_result" \
    "dry_run_modality_result_blocked" \
    "modality result records final status, reviewed logs, screenshots, and output evidence" \
    "dry run marked the modality BLOCKED because no target runtime was used" \
    "screenshots/dry_run_modality_result.png" \
    "logs/dry_run_modality_result.log" \
    "dry-run-model" \
    "${notes}"

  {
    printf "modality\tstatus\tmodel_id\tdownloaded\tloaded\tinference_run\toutput_evidence\tlogs_reviewed\tlog_paths\tscreenshots\tnotes\n"
    printf "llm\tBLOCKED\tdry-run-model\tno\tno\tno\tlogs/dry_run_inference.log\tyes\tlogs/dry_run_model_download.log;logs/dry_run_model_load.log;logs/dry_run_inference.log;logs/dry_run_modality_result.log\tscreenshots/dry_run_model_download.png;screenshots/dry_run_model_load.png;screenshots/dry_run_inference.png;screenshots/dry_run_modality_result.png\t%s\n" "${notes}"
  } > "${lane_dir}/modality_table.tsv"

  printf "%s\t%s\tllm\tBLOCKED\t%s/actions.jsonl\tDry run did not use real target hardware/runtime.\thardware_device\tRun the lane with a real device, simulator, or browser and replace dry-run evidence rows.\n" \
    "$(dry_run_failure_id "${lane}")" \
    "${lane}" \
    "${lane}" >> "${RUN_DIR}/failure_summary.tsv"
}

run_evidence_self_check() {
  local require_evidence="$1"
  local require_files="$2"
  local log="${RUN_DIR}/global/logs/evidence_self_check.log"
  local code
  local status
  local args=("${RUN_DIR}")

  if [[ "${require_evidence}" -eq 1 ]]; then
    args+=("--require-evidence")
  fi
  if [[ "${require_files}" -eq 1 ]]; then
    args+=("--require-files")
  fi

  set +e
  python3 "${SCRIPT_DIR}/validate_seven_lane_evidence.py" "${args[@]}" > "${log}" 2>&1
  code=$?
  set -e

  status="PASS"
  if [[ "${code}" -ne 0 ]]; then
    status="FAIL"
  fi
  printf "evidence_self_check\t%s\t%s\tglobal/logs/evidence_self_check.log\n" "${status}" "${code}" >> "${RUN_DIR}/summary.tsv"

  return "${code}"
}

{
  printf "# Seven-Lane Validation Manifest\n\n"
  printf -- "- Started: %s\n" "$(date -Iseconds)"
  printf -- "- Repo root: %s\n" "${VALIDATION_REPO_ROOT}"
  printf -- "- Build root: %s\n" "${VALIDATION_BUILD_ROOT}"
  printf -- "- Evidence schema version: 2\n"
  printf -- "- Dry run: %s\n" "${DRY_RUN}"
  printf -- "- Instructions: ../../INSTRUCTIONS.md\n"
  printf -- "- Build organization: ../../README.md\n"
} > "${RUN_DIR}/RUN_MANIFEST.md"

while IFS='|' read -r lane sdk platform title; do
  [[ -z "${lane}" ]] && continue
  mkdir -p "${RUN_DIR}/${lane}/logs" "${RUN_DIR}/${lane}/screenshots" "${RUN_DIR}/${lane}/videos"
  : > "${RUN_DIR}/${lane}/actions.jsonl"
  printf "name\tstatus\texit_code\tlog\n" > "${RUN_DIR}/${lane}/command_summary.tsv"
  printf "modality\tstatus\tmodel_id\tdownloaded\tloaded\tinference_run\toutput_evidence\tlogs_reviewed\tlog_paths\tscreenshots\tnotes\n" \
    > "${RUN_DIR}/${lane}/modality_table.tsv"
  write_lane_report_template "${lane}" "${sdk}" "${platform}" "${title}"
done < <(lane_data)

write_machine_summary

# Write a placeholder REPORT.md so the schema validator passes.
# If --report is set, generate_report() will overwrite it at the end.
{
  printf "# Seven-Lane Validation Report\n\n"
  printf -- "- Run dir: %s\n" "${RUN_DIR}"
  printf -- "- Build root: %s\n" "${VALIDATION_BUILD_ROOT}"
  printf -- "- Evidence schema version: 2\n"
  printf -- "- Preflight: %s\n" "${WITH_PREFLIGHT}"
  printf -- "- Dry run: %s\n\n" "${DRY_RUN}"
  printf "## Runtime Evidence\n\n"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "This run contains synthetic BLOCKED rows only. It validates evidence shape and path references without using devices, simulators, browsers, models, or inference.\n"
  else
    printf "Fill this report after target agents complete lanes 01 through 07.\n"
  fi
} > "${RUN_DIR}/REPORT.md"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  printf "Dry-run harness seed started at %s\n" "$(date -Iseconds)" > "${RUN_DIR}/global/logs/dry_run_harness.log"
  while IFS='|' read -r lane sdk platform title; do
    [[ -z "${lane}" ]] && continue
    seed_dry_run_lane_evidence "${lane}" "${sdk}" "${platform}"
  done < <(lane_data)
  printf "Dry-run harness seed finished at %s\n" "$(date -Iseconds)" >> "${RUN_DIR}/global/logs/dry_run_harness.log"
  printf "seven_lane_dry_run_seed\tPASS\t0\tglobal/logs/dry_run_harness.log\n" >> "${RUN_DIR}/summary.tsv"
fi

if [[ "${WITH_PREFLIGHT}" -eq 1 ]]; then
  VALIDATION_RUN_DIR="${RUN_DIR}/global/source-checks" \
    VALIDATION_BUILD_ROOT="${VALIDATION_BUILD_ROOT}" \
    "${SCRIPT_DIR}/run_global_source_checks.sh"
  VALIDATION_RUN_DIR="${RUN_DIR}/global/commons-proto-checks" \
    VALIDATION_BUILD_ROOT="${VALIDATION_BUILD_ROOT}" \
    "${SCRIPT_DIR}/../commons/run_commons_proto_checks.sh"
fi

if [[ "${SELF_CHECK}" -eq 1 ]]; then
  run_evidence_self_check "${DRY_RUN}" "${DRY_RUN}"
fi

if [[ "${GENERATE_REPORT}" -eq 1 ]]; then
  generate_report "${RUN_DIR}"
fi

printf "Seven-lane scaffold: %s\n" "${RUN_DIR}"
printf "Use build root: %s\n" "${VALIDATION_BUILD_ROOT}"
