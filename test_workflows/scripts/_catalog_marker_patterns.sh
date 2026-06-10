#!/usr/bin/env bash
# Catalog §10 log grep patterns — shared by analyzers and iter-5/8/10 regrade scripts.
# Align with sdk/runanywhere-* log strings + C++ rac_logger + example-app Timber/os_log.
# shellcheck disable=SC2034

# --- Legacy primary markers (executors still grep these first) ---
: "${RAC_MARKER_SDK_INIT:=Phase 1 complete}"; export RAC_MARKER_SDK_INIT
: "${RAC_MARKER_SDK_INIT_ALT:=SDK successfully initialized}"; export RAC_MARKER_SDK_INIT_ALT
: "${RAC_MARKER_SDK_INIT_DEV:=SDK initialized in DEVELOPMENT mode}"; export RAC_MARKER_SDK_INIT_DEV
: "${RAC_MARKER_SDK_PHASE1_READY:=SDK Phase 1 ready}"; export RAC_MARKER_SDK_PHASE1_READY
: "${RAC_MARKER_APP_READY:=App is ready to use}"; export RAC_MARKER_APP_READY
: "${RAC_MARKER_AI_READY:=__RUNANYWHERE_AI_READY__}"; export RAC_MARKER_AI_READY
: "${RAC_MARKER_REGISTERED_DOWNLOAD:=Registered downloaded model}"; export RAC_MARKER_REGISTERED_DOWNLOAD
: "${RAC_MARKER_MODEL_LOAD:=Model load succeeded for}"; export RAC_MARKER_MODEL_LOAD
: "${RAC_MARKER_LLM_LOAD:=LLM model loaded}"; export RAC_MARKER_LLM_LOAD
: "${RAC_MARKER_LLM_STREAM_DONE:=LLM stream complete}"; export RAC_MARKER_LLM_STREAM_DONE
: "${RAC_MARKER_STT_LOADED:=STT model loaded successfully}"; export RAC_MARKER_STT_LOADED
: "${RAC_MARKER_DOWNLOAD_ACCEPTED:=Download accepted for}"; export RAC_MARKER_DOWNLOAD_ACCEPTED
: "${RAC_MARKER_TTS_DONE:=Speech generation complete}"; export RAC_MARKER_TTS_DONE
: "${RAC_MARKER_VLM_DONE:=VLM streaming completed}"; export RAC_MARKER_VLM_DONE
: "${RAC_MARKER_RAG_INGEST:=Document loaded successfully}"; export RAC_MARKER_RAG_INGEST
: "${RAC_MARKER_RAG_QUERY:=Query complete}"; export RAC_MARKER_RAG_QUERY

# --- TC-02 download (grep -Ei alternates) ---
RAC_REGEX_TC02_DOWNLOAD='Download accepted for|⬇️ Download accepted for|Registered downloaded model|📦 Registered downloaded model|Starting download for model:|E2E bootstrap: starting download for|task=download-proto|\[RunAnywhere\.Download\] Download accepted|\[RunAnywhere\.Download\].*Starting download'

# --- TC-03 persistence (cold-start / force-kill relaunch) ---
RAC_REGEX_TC03_PERSISTENCE='Phase 1 complete|SDK Phase 1 ready|App is ready to use|SDK initialization complete|SDK successfully initialized|SDK initialized successfully|\[App\] All models registered|SDK Phase 1 proto initialized|InitBridge.*SDK initialized|Phase 1 initialization complete|\[RunAnywhere\.Init\] Phase 1 complete'

# --- TC-04 LLM load ---
RAC_REGEX_TC04_LOAD='LLM model loaded|Model load succeeded for|ModelLifecycle.*Model load succeeded|Model loaded successfully|✅ Model load succeeded for|✅ LLM model loaded:|Found downloaded chat model|\[ChatScreen\] Text model loaded: true|Voice agent LLM model loaded:|load_model SUCCESS|✅ LLM models registered|LLM models registered'

# --- TC-05 LLM stream / chat inference ---
RAC_REGEX_TC05_STREAM='LLM stream complete|\[PARAMS\] generateStream|Streaming token|generateStream:|RAC_LLM_STREAM_EVENT_COMPLETE|chat/stream fallback|ConversationStore.*Created conversation'

# --- TC-07 STT load / batch ---
RAC_REGEX_TC07_STT='STT model loaded successfully|STT model loaded: true|\[STTScreen\] STT model loaded: true|✅ STT model loaded|Sherpa\.STT.*STT model loaded successfully|Voice agent STT model loaded:|Batch transcription complete|✅ Batch transcription complete|Ready to transcribe|Transcription complete|\[STTScreen\]'

# --- TC-08 TTS synthesis ---
RAC_REGEX_TC08_TTS='Speech generation complete|✅ Speech generation complete|Synthesis complete|Synthesis completed|Sherpa\.TTS.*Synthesis complete|TTS synthesis complete|\[TTSScreen\]'

# --- TC-09 VLM ---
RAC_REGEX_TC09_VLM='VLM streaming completed|VLM processing complete|Starting VLM streaming|Frame description completed|VLM model loaded: true|VLM model loaded successfully|\[VisionScreen\]'

# --- TC-10 STT UI ready ---
RAC_REGEX_TC10_STT_UI='Ready to transcribe|STT auto-prepare started|STT auto-prepare skipped|\[STTScreen\]|\[TranscribeScreen\]'

# --- TC-12 voice agent ---
RAC_REGEX_TC12_VOICE='Model states synced|Voice agent.*model loaded|voice surface visible|Voice tab'

# --- TC-13 RAG ingest / query ---
RAC_REGEX_TC13_RAG='Document loaded successfully|Embedding generation complete|Query complete|ragIngest|ragQuery|RAG tab|Document Q&A'

# --- TC-14 tools ---
RAC_REGEX_TC14_TOOLS='registerTool|Tool calling enabled|demo tools registered|tool trigger|Tools enabled'

# --- TC-15/16 storage ---
RAC_REGEX_TC15_STORAGE='StorageScreen|storage surface visible|SmolLM|model storage|Downloaded models'

# --- TC-19 benchmarks ---
RAC_REGEX_TC19_BENCH='benchmark.*complete|Benchmark run|BenchmarksScreen|benchmark run triggered'

# --- TC-21 LoRA ---
RAC_REGEX_TC21_LORA='LoRA.*applied|lora.*adapter|LoRA validation|LoRA catalog'

# --- TC-Download-interrupt ---
RAC_REGEX_TC_DOWNLOAD_INTERRUPT='download.*cancel|Download.*interrupt|download-proto.*cancel|task=download-proto.*CANCEL'

# --- TC-01 init ---
RAC_REGEX_TC01_INIT='SDK Phase 1 ready|Phase 1 complete|SDK successfully initialized|SDK initialization complete|\[App\] All models registered|Phase 1 complete \(Development Environment\)'

# §7.0 PASS-WHEN-UI-PROVES: counter-evidence that blocks UI-only promotion
RAC_REGEX_COUNTER_EVIDENCE_TC04='Text model loaded: false|Text model loaded:\s*false|no lifecycle LLM model loaded|Model load failed|load_model FAILED'
RAC_REGEX_COUNTER_EVIDENCE_TC07='STT model loaded: false|STT load failed|Batch transcription failed'
RAC_REGEX_APP_PACKAGE='com\.runanywhere|runanywhere_ai|RunAnywhereAI|com\.runanywhereaI'
RAC_REGEX_COUNTER_EVIDENCE_FATAL="FATAL EXCEPTION: main.*${RAC_REGEX_APP_PACKAGE}|Process: ${RAC_REGEX_APP_PACKAGE}.*has died|Fatal error:"

export RAC_REGEX_TC02_DOWNLOAD RAC_REGEX_TC03_PERSISTENCE RAC_REGEX_TC04_LOAD RAC_REGEX_TC05_STREAM
export RAC_REGEX_TC07_STT RAC_REGEX_TC08_TTS RAC_REGEX_TC09_VLM
export RAC_REGEX_TC10_STT_UI RAC_REGEX_TC12_VOICE RAC_REGEX_TC13_RAG RAC_REGEX_TC14_TOOLS
export RAC_REGEX_TC15_STORAGE RAC_REGEX_TC19_BENCH RAC_REGEX_TC21_LORA RAC_REGEX_TC_DOWNLOAD_INTERRUPT
export RAC_REGEX_TC01_INIT
export RAC_REGEX_COUNTER_EVIDENCE_TC04 RAC_REGEX_COUNTER_EVIDENCE_TC07 RAC_REGEX_COUNTER_EVIDENCE_FATAL

rac_catalog_grep_logs() {
  local regex="$1"
  shift
  local log
  for log in "$@"; do
    [[ -f "${log}" ]] || continue
    grep -Eiq "${regex}" "${log}" 2>/dev/null && return 0
  done
  return 1
}

# Resolve executor evidence root (handles iter*-regrade subdirs).
rac_catalog_evidence_root() {
  local start_dir="$1"
  local candidate
  candidate="$(cd "${start_dir}" && pwd)"
  local i
  for ((i = 0; i < 6; i++)); do
    if [[ -d "${candidate}/logs" || -f "${candidate}/actions.jsonl" || -d "${candidate}/screenshots" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    [[ "${candidate}" == "/" ]] && break
    candidate="$(dirname "${candidate}")"
  done
  printf '%s\n' "$(cd "${start_dir}" && pwd)"
}

rac_catalog_collect_logs() {
  local lane_dir="$1"
  local evidence_root
  evidence_root="$(rac_catalog_evidence_root "${lane_dir}")"
  local -a logs=()
  local f
  while IFS= read -r -d '' f; do
    logs+=("${f}")
  done < <(find "${evidence_root}" -type f \( \
    -name '*.log' -o -name 'metro.log' -o -name 'nohup.out' -o -name 'ios_live.log' \
    \) ! -path '*/iter5-regrade/*' ! -path '*/iter8-regrade/*' ! -path '*/iter10-regrade/*' \
    ! -name 'executor.log' ! -name 'tc_executor.log' \
    -print0 2>/dev/null)
  printf '%s\n' "${logs[@]}"
}

rac_catalog_tc_regex() {
  local tc="$1"
  local norm
  norm="$(echo "${tc}" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
  case "${norm}" in
    tc01) echo "${RAC_REGEX_TC01_INIT}" ;;
    tc02) echo "${RAC_REGEX_TC02_DOWNLOAD}" ;;
    tc03|tc03a) echo "${RAC_REGEX_TC03_PERSISTENCE}" ;;
    tc04) echo "${RAC_REGEX_TC04_LOAD}" ;;
    tc05) echo "${RAC_REGEX_TC05_STREAM}|${RAC_REGEX_TC04_LOAD}|${RAC_REGEX_TC01_INIT}" ;;
    tc07) echo "${RAC_REGEX_TC07_STT}" ;;
    tc08|tc11) echo "${RAC_REGEX_TC08_TTS}" ;;
    tc09) echo "${RAC_REGEX_TC09_VLM}" ;;
    tc10) echo "${RAC_REGEX_TC10_STT_UI}|${RAC_REGEX_TC07_STT}" ;;
    tc12) echo "${RAC_REGEX_TC12_VOICE}" ;;
    tc13) echo "${RAC_REGEX_TC13_RAG}" ;;
    tc14) echo "${RAC_REGEX_TC14_TOOLS}" ;;
    tc15|tc16) echo "${RAC_REGEX_TC15_STORAGE}|${RAC_REGEX_TC03_PERSISTENCE}" ;;
    tc19) echo "${RAC_REGEX_TC19_BENCH}" ;;
    tc21) echo "${RAC_REGEX_TC21_LORA}" ;;
    tcdownloadinterrupt) echo "${RAC_REGEX_TC02_DOWNLOAD}|${RAC_REGEX_TC_DOWNLOAD_INTERRUPT}" ;;
    *) return 1 ;;
  esac
}

rac_catalog_tc_marker_limited() {
  local tc="$1"
  local notes="$2"
  [[ "${notes}" == *"marker missing:"* ]] && return 0
  [[ "${notes}" == *"catalog phase"* ]] && return 0
  case "${tc}" in
    tc02|TC-02) [[ "${notes}" == *"download"* && "${notes}" == *"marker"* ]] && return 0
                [[ "${notes}" == *"download flow driven"* ]] && return 0 ;;
    tc03|TC-03|tc03a|TC-03a) [[ "${notes}" == *"persistence not confirmed"* ]] && return 0
                [[ "${notes}" == *"force-kill"* ]] && return 0 ;;
    tc04|TC-04) [[ "${notes}" == *"Model load succeeded marker missing"* ]] && return 0
                [[ "${notes}" == *"LLM model loaded"* ]] && return 0
                [[ "${notes}" == *"load attempted"* ]] && return 0 ;;
    tc05|TC-05) [[ "${notes}" == *"inference marker missing"* ]] && return 0
                [[ "${notes}" == *"LLM stream complete"* ]] && return 0
                [[ "${notes}" == *"prompt sent"* ]] && return 0 ;;
    tc07|TC-07) [[ "${notes}" == *"batch marker not seen"* ]] && return 0
                [[ "${notes}" == *"STT model loaded"* ]] && return 0
                [[ "${notes}" == *"STT batch flow driven"* ]] && return 0 ;;
    tc08|TC-08) [[ "${notes}" == *"synthesis log"* ]] && return 0
                [[ "${notes}" == *"TTS generate tapped"* ]] && return 0 ;;
    tc09|TC-09) [[ "${notes}" == *"VLM"* && "${notes}" == *"marker"* ]] && return 0
                [[ "${notes}" == *"VLM model not loaded"* ]] && return 0
                [[ "${notes}" == *"Vision tab held"* ]] && return 0 ;;
    tc10|TC-10) [[ "${notes}" == *"STT ready marker not"* ]] && return 0
                [[ "${notes}" == *"STT UX flow"* ]] && return 0
                [[ "${notes}" == *"STT tab opened"* ]] && return 0 ;;
    tc11|TC-11) [[ "${notes}" == *"TTS screen held"* ]] && return 0
                [[ "${notes}" == *"synthesis"* ]] && return 0 ;;
    tc12|TC-12) [[ "${notes}" == *"Model states synced"* ]] && return 0
                [[ "${notes}" == *"voice"* ]] && return 0 ;;
    tc13|TC-13) [[ "${notes}" == *"RAG tab opened"* ]] && return 0
                [[ "${notes}" == *"Document Q&A"* ]] && return 0
                [[ "${notes}" == *"RAG ingest incomplete"* ]] && return 0 ;;
    tc14|TC-14) [[ "${notes}" == *"tool toggle not confirmed"* ]] && return 0
                [[ "${notes}" == *"Tool Calling"* ]] && return 0 ;;
    tc15|TC-15) [[ "${notes}" == *"storage opened"* ]] && return 0
                [[ "${notes}" == *"SmolLM2 row not confirmed"* ]] && return 0 ;;
    tc16|TC-16) [[ "${notes}" == *"storage after force-kill"* ]] && return 0
                [[ "${notes}" == *"model list unclear"* ]] && return 0
                [[ "${notes}" == *"storage/settings surface reopened"* ]] && return 0 ;;
    tc19|TC-19) [[ "${notes}" == *"benchmark run triggered"* ]] && return 0 ;;
    tc21|TC-21) [[ "${notes}" == *"LoRA"* && "${notes}" == *"attempted"* ]] && return 0 ;;
    tc-Download-interrupt|TC-Download-interrupt) [[ "${notes}" == *"download started then cancel"* ]] && return 0
                [[ "${notes}" == *"cancel/back attempted"* ]] && return 0 ;;
  esac
  return 1
}

rac_catalog_tc_normalize() {
  echo "${1}" | tr '[:upper:]' '[:lower:]' | tr -d '-'
}

# Resolve lane-relative artifact paths by walking up from evidence root.
rac_catalog_resolve_artifact() {
  local start_dir="$1"
  local rel_path="$2"
  local candidate
  candidate="$(cd "${start_dir}" && pwd)"
  local i
  for ((i = 0; i < 6; i++)); do
    if [[ -f "${candidate}/${rel_path}" && -s "${candidate}/${rel_path}" ]]; then
      printf '%s\n' "${candidate}/${rel_path}"
      return 0
    fi
    [[ "${candidate}" == "/" ]] && break
    candidate="$(dirname "${candidate}")"
  done
  return 1
}

rac_catalog_find_actions_file() {
  local start_dir="$1"
  rac_catalog_resolve_artifact "${start_dir}" "actions.jsonl"
}

rac_catalog_action_driven() {
  local evidence_root="$1"
  local tc="$2"
  local actions norm
  norm="$(rac_catalog_tc_normalize "${tc}")"
  actions="$(rac_catalog_find_actions_file "${evidence_root}" || true)"
  [[ -n "${actions}" && -f "${actions}" ]] || return 1
  grep -Fq "\"action\":\"${norm}\"" "${actions}" 2>/dev/null && return 0
  grep -Fq "\"action\":\"${tc}\"" "${actions}" 2>/dev/null && return 0
  grep -Fq "\"action\": \"${norm}\"" "${actions}" 2>/dev/null && return 0
  grep -Fq "\"action\": \"${tc}\"" "${actions}" 2>/dev/null
}

rac_catalog_screenshot_path() {
  local evidence_root="$1"
  local tc="$2"
  local screenshot_rel="${3:-}"
  local norm shot actions_path actions_dir
  norm="$(rac_catalog_tc_normalize "${tc}")"

  if [[ -n "${screenshot_rel}" ]]; then
    rac_catalog_resolve_artifact "${evidence_root}" "${screenshot_rel}" && return 0
  fi

  actions_path="$(rac_catalog_find_actions_file "${evidence_root}" || true)"
  [[ -n "${actions_path}" && -f "${actions_path}" ]] || return 1
  actions_dir="$(dirname "${actions_path}")"
  shot="$(grep -F "\"action\":\"${norm}\"" "${actions_path}" 2>/dev/null \
    | grep -F '"screenshot"' \
    | tail -1 \
    | sed -n 's/.*"screenshot"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [[ -n "${shot}" ]] || return 1
  rac_catalog_resolve_artifact "${actions_dir}" "${shot}"
}

rac_catalog_primary_logs() {
  local evidence_root="$1"
  local -a logs=()
  local root candidate name f
  root="$(rac_catalog_evidence_root "${evidence_root}")"
  for candidate in "${root}" "$(dirname "${root}")"; do
    for name in logcat_runanywhere_filtered.log android_logcat.log logcat_full.log ios_live.log metro.log; do
      f="${candidate}/logs/${name}"
      [[ -f "${f}" ]] && logs+=("${f}")
    done
  done
  if [[ ${#logs[@]} -gt 0 ]]; then
    printf '%s\n' "${logs[@]}" | awk '!seen[$0]++'
    return 0
  fi
  rac_catalog_collect_logs "${evidence_root}"
}

rac_catalog_has_fatal_errors() {
  local log
  for log in "$@"; do
    [[ -f "${log}" ]] || continue
    if grep -Ei "${RAC_REGEX_COUNTER_EVIDENCE_FATAL}" "${log}" 2>/dev/null \
      | grep -Ev 'uiautomator|AccessibilityNodeInfoDumper|instrumentation|TestRunner|UiAutomator|UiAutomationService' \
      | grep -q .; then
      return 0
    fi
  done
  return 1
}

rac_catalog_tc_counter_evidence() {
  local tc="$1"
  shift
  local norm regex=""
  norm="$(rac_catalog_tc_normalize "${tc}")"
  case "${norm}" in
    tc04) regex="${RAC_REGEX_COUNTER_EVIDENCE_TC04}" ;;
    tc07) regex="${RAC_REGEX_COUNTER_EVIDENCE_TC07}" ;;
    *) return 1 ;;
  esac
  rac_catalog_grep_logs "${regex}" "$@"
}

# §7.0 PASS-WHEN-UI-PROVES: executor drove TC, screenshot exists, no fatal/counter-evidence.
rac_catalog_ui_proves_pass() {
  local evidence_root="$1"
  local tc="$2"
  local screenshot_rel="${3:-}"
  local -a logs=()
  local log

  rac_catalog_action_driven "${evidence_root}" "${tc}" || return 1
  rac_catalog_screenshot_path "${evidence_root}" "${tc}" "${screenshot_rel}" >/dev/null || return 1

  while IFS= read -r log; do
    [[ -n "${log}" ]] && logs+=("${log}")
  done < <(rac_catalog_primary_logs "${evidence_root}")

  rac_catalog_has_fatal_errors "${logs[@]}" && return 1
  rac_catalog_tc_counter_evidence "${tc}" "${logs[@]}" && return 1
  return 0
}
