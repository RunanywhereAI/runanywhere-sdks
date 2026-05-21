#!/usr/bin/env bash
# Shared catalog grep markers for E2E lane executors.
# Align with Swift SDKLogger / C++ rac_logger strings and iOS example os_log.
# shellcheck disable=SC2034
RAC_MARKER_SDK_INIT='Phase 1 complete'
RAC_MARKER_SDK_INIT_ALT='SDK successfully initialized'
RAC_MARKER_SDK_INIT_DEV='SDK initialized in DEVELOPMENT mode'
RAC_MARKER_SDK_SERVICES='Services initialized for catalog refresh'
RAC_MARKER_APP_READY='App is ready to use'
RAC_MARKER_AI_READY='__RUNANYWHERE_AI_READY__'
RAC_MARKER_REGISTERED_DOWNLOAD='Registered downloaded model'
RAC_MARKER_MODEL_LOAD='Model load succeeded for'
RAC_MARKER_STT_LOADED='STT model loaded successfully'
RAC_MARKER_DOWNLOAD_ACCEPTED='Download accepted for'
RAC_MARKER_DOWNLOAD_FAILED='Download failed'
RAC_MARKER_DOWNLOAD_PLAN_REJECTED='Download plan rejected for'
RAC_MARKER_DOWNLOAD_START_REJECTED='Download start rejected for'
RAC_MARKER_STT_UI_READY='Ready to transcribe'
RAC_MARKER_OPFS_HYDRATED='hydrated'
RAC_MARKER_BENCHMARK_SAVED='Benchmark history saved'
