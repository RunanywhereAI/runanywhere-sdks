#!/usr/bin/env bash
# Shared catalog grep markers for E2E lane executors.
# Align with Swift SDKLogger / C++ rac_logger strings and iOS example os_log.
# shellcheck disable=SC2034

: "${RAC_MARKER_SDK_INIT:=Phase 1 complete}"; export RAC_MARKER_SDK_INIT
: "${RAC_MARKER_SDK_INIT_ALT:=SDK successfully initialized}"; export RAC_MARKER_SDK_INIT_ALT
: "${RAC_MARKER_SDK_INIT_DEV:=SDK initialized in DEVELOPMENT mode}"; export RAC_MARKER_SDK_INIT_DEV
: "${RAC_MARKER_SDK_SERVICES:=Services initialized for catalog refresh}"; export RAC_MARKER_SDK_SERVICES
: "${RAC_MARKER_APP_READY:=App is ready to use}"; export RAC_MARKER_APP_READY
: "${RAC_MARKER_AI_READY:=__RUNANYWHERE_AI_READY__}"; export RAC_MARKER_AI_READY
: "${RAC_MARKER_REGISTERED_DOWNLOAD:=Registered downloaded model}"; export RAC_MARKER_REGISTERED_DOWNLOAD
: "${RAC_MARKER_MODEL_LOAD:=Model load succeeded for}"; export RAC_MARKER_MODEL_LOAD
: "${RAC_MARKER_LLM_LOAD:=LLM model loaded}"; export RAC_MARKER_LLM_LOAD
: "${RAC_MARKER_LLM_STREAM_DONE:=LLM stream complete}"; export RAC_MARKER_LLM_STREAM_DONE
: "${RAC_MARKER_STT_LOADED:=STT model loaded successfully}"; export RAC_MARKER_STT_LOADED
: "${RAC_MARKER_DOWNLOAD_ACCEPTED:=Download accepted for}"; export RAC_MARKER_DOWNLOAD_ACCEPTED
: "${RAC_MARKER_DOWNLOAD_FAILED:=Download failed}"; export RAC_MARKER_DOWNLOAD_FAILED
: "${RAC_MARKER_DOWNLOAD_PLAN_REJECTED:=Download plan rejected for}"; export RAC_MARKER_DOWNLOAD_PLAN_REJECTED
: "${RAC_MARKER_DOWNLOAD_START_REJECTED:=Download start rejected for}"; export RAC_MARKER_DOWNLOAD_START_REJECTED
: "${RAC_MARKER_STT_UI_READY:=Ready to transcribe}"; export RAC_MARKER_STT_UI_READY
: "${RAC_MARKER_STT_AUTO_PREPARE:=STT auto-prepare started}"; export RAC_MARKER_STT_AUTO_PREPARE
: "${RAC_MARKER_OPFS_HYDRATED:=hydrated}"; export RAC_MARKER_OPFS_HYDRATED
: "${RAC_MARKER_BENCHMARK_SAVED:=Benchmark history saved}"; export RAC_MARKER_BENCHMARK_SAVED
: "${RAC_MARKER_TTS_DONE:=Speech generation complete}"; export RAC_MARKER_TTS_DONE
: "${RAC_MARKER_VLM_DONE:=VLM streaming completed}"; export RAC_MARKER_VLM_DONE
: "${RAC_MARKER_RAG_INGEST:=Document loaded successfully}"; export RAC_MARKER_RAG_INGEST
: "${RAC_MARKER_RAG_QUERY:=Query complete}"; export RAC_MARKER_RAG_QUERY
: "${RAC_MARKER_LORA_APPLY:=Loaded LoRA adapter}"; export RAC_MARKER_LORA_APPLY
