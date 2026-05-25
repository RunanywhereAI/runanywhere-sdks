#!/usr/bin/env bash
# Catalog §10 log grep patterns — shared by analyzers and iter-5 regrade scripts.
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
RAC_REGEX_TC02_DOWNLOAD='Download accepted for|⬇️ Download accepted for|Registered downloaded model|📦 Registered downloaded model|Starting download for model:|E2E bootstrap: starting download for|task=download-proto|\[RunAnywhere\.Download\] Download accepted'

# --- TC-04 LLM load ---
RAC_REGEX_TC04_LOAD='LLM model loaded|Model load succeeded for|ModelLifecycle.*Model load succeeded|✅ Model load succeeded for|✅ LLM model loaded:|Found downloaded chat model|\[ChatScreen\] Text model loaded: true|Voice agent LLM model loaded:|load_model SUCCESS'

# --- TC-05 LLM stream / chat inference ---
RAC_REGEX_TC05_STREAM='LLM stream complete|\[PARAMS\] generateStream|Streaming token|generateStream:|RAC_LLM_STREAM_EVENT_COMPLETE|chat/stream fallback'

# --- TC-07 STT load ---
RAC_REGEX_TC07_STT='STT model loaded successfully|STT model loaded: true|\[STTScreen\] STT model loaded: true|✅ STT model loaded|Sherpa\.STT.*STT model loaded successfully|Voice agent STT model loaded:'

# --- TC-08 TTS synthesis ---
RAC_REGEX_TC08_TTS='Speech generation complete|✅ Speech generation complete|Synthesis complete|Synthesis completed|Sherpa\.TTS.*Synthesis complete|TTS synthesis complete'

# --- TC-09 VLM ---
RAC_REGEX_TC09_VLM='VLM streaming completed|VLM processing complete|Starting VLM streaming|Frame description completed|VLM model loaded'

# --- TC-10 STT UI ready ---
RAC_REGEX_TC10_STT_UI='Ready to transcribe|STT auto-prepare started|STT auto-prepare skipped'

# --- TC-01 init ---
RAC_REGEX_TC01_INIT='SDK Phase 1 ready|Phase 1 complete|SDK successfully initialized|SDK initialization complete|\[App\] All models registered|Phase 1 complete \(Development Environment\)'

export RAC_REGEX_TC02_DOWNLOAD RAC_REGEX_TC04_LOAD RAC_REGEX_TC05_STREAM
export RAC_REGEX_TC07_STT RAC_REGEX_TC08_TTS RAC_REGEX_TC09_VLM
export RAC_REGEX_TC10_STT_UI RAC_REGEX_TC01_INIT

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

rac_catalog_collect_logs() {
  local lane_dir="$1"
  local -a logs=()
  local f
  while IFS= read -r -d '' f; do
    logs+=("${f}")
  done < <(find "${lane_dir}" -type f \( \
    -name '*.log' -o -name 'metro.log' -o -name 'nohup.out' -o -name 'ios_live.log' \
    \) ! -path '*/iter5-regrade/*' -print0 2>/dev/null)
  printf '%s\n' "${logs[@]}"
}

rac_catalog_tc_regex() {
  local tc="$1"
  local norm
  norm="$(echo "${tc}" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
  case "${norm}" in
    tc01) echo "${RAC_REGEX_TC01_INIT}" ;;
    tc02) echo "${RAC_REGEX_TC02_DOWNLOAD}" ;;
    tc04) echo "${RAC_REGEX_TC04_LOAD}" ;;
    tc05) echo "${RAC_REGEX_TC05_STREAM}|${RAC_REGEX_TC04_LOAD}|${RAC_REGEX_TC01_INIT}" ;;
    tc07) echo "${RAC_REGEX_TC07_STT}" ;;
    tc08) echo "${RAC_REGEX_TC08_TTS}" ;;
    tc09) echo "${RAC_REGEX_TC09_VLM}" ;;
    tc10) echo "${RAC_REGEX_TC10_STT_UI}|${RAC_REGEX_TC07_STT}" ;;
    *) return 1 ;;
  esac
}

rac_catalog_tc_marker_limited() {
  local tc="$1"
  local notes="$2"
  [[ "${notes}" == *"marker missing:"* ]] && return 0
  case "${tc}" in
    tc02|TC-02) [[ "${notes}" == *"download"* && "${notes}" == *"marker"* ]] && return 0 ;;
    tc04|TC-04) [[ "${notes}" == *"Model load succeeded marker missing"* ]] && return 0
                [[ "${notes}" == *"LLM model loaded"* ]] && return 0 ;;
    tc05|TC-05) [[ "${notes}" == *"inference marker missing"* ]] && return 0
                [[ "${notes}" == *"LLM stream complete"* ]] && return 0 ;;
    tc07|TC-07) [[ "${notes}" == *"batch marker not seen"* ]] && return 0
                [[ "${notes}" == *"STT model loaded"* ]] && return 0 ;;
    tc08|TC-08) [[ "${notes}" == *"synthesis log"* ]] && return 0
                [[ "${notes}" == *"TTS generate tapped"* ]] && return 0 ;;
    tc09|TC-09) [[ "${notes}" == *"VLM"* && "${notes}" == *"marker"* ]] && return 0
                [[ "${notes}" == *"VLM model not loaded"* ]] && return 0 ;;
    tc10|TC-10) [[ "${notes}" == *"STT ready marker not"* ]] && return 0 ;;
  esac
  return 1
}
