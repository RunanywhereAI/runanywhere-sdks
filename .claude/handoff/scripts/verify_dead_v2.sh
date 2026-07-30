#!/usr/bin/env bash
# Corrected dead-type verification. v1 only asked "does an SDK read this symbol",
# which misses two ways a type stays alive:
#   (a) another .proto references it as a field type
#   (b) commons PRODUCES it (set_*/mutable_*) even if no SDK consumes it
cd /home/home/Projects/runanywhere-sdks || exit 1

CORPUS=(
  sdk/runanywhere-commons/src sdk/runanywhere-commons/include
  sdk/runanywhere-kotlin sdk/runanywhere-swift sdk/runanywhere-flutter
  sdk/runanywhere-react-native sdk/runanywhere-web sdk/runanywhere-python
  sdk/runanywhere-electron sdk/runanywhere-cli
  examples engines runtimes
)
EXCL=(
  -g '!**/generated/**' -g '!**/Generated/**' -g '!**/*.pb.*' -g '!**/*_pb2.py'
  -g '!sdk/runanywhere-python/runanywhere/_proto/**'
  -g '!sdk/runanywhere-python/runanywhere/_generated_*.py'
  -g '!sdk/shared/proto-ts/**' -g '!sdk/runanywhere-electron/src/proto/**'
  -g '!**/rac_defaults_generated.h' -g '!**/nitrogen/**'
  -g '!**/node_modules/**' -g '!**/build/**' -g '!**/dist/**' -g '!**/Pods/**'
  -g '!**/.yarn/**' -g '!**/.dart_tool/**' -g '!**/*.md' -g '!**/*.lock'
)

TYPES=(
  ChatConversationState LLMGenerationState LLMGenerationStatus PerformanceMetrics
  ToolCallingSessionCreateResult ToolCallingSessionDestroyRequest EmbeddingsServiceState
  DiffusionConfig DiffusionServiceState DiffusionCapabilities PluginInfoList HybridCapability
  STTLanguageDetectionResult NPUChip ModelDeleteRequest ModelRuntimeCompatibility
  ToolRegistrySnapshot ToolCallingStreamEvent ToolCallingStreamEventKind
  RAGIngestRequest RAGIngestResult RAGServiceState RAGQueryRequest
  Sentiment SentimentResult NERResult ClassificationResult ClassificationCandidate
  EntityExtractionResult
  HardwareProfileRequest HardwareProfileResult HardwareAcceleratorsRequest
  HardwareAcceleratorPreferenceRequest HardwareAcceleratorPreferenceResult NpuProbeRequest
  ChatGenerationResult SDKEventPublishRequest SDKEventPublishResult
  ComponentLifecycleSnapshotRequest ComponentLifecycleSnapshotResult
  ChatStreamEvent ChatStreamEventKind SDKEventFilter SDKEventSubscribeRequest
  DiffusionTokenizerSource DiffusionTokenizerSourceKind DiffusionModelVariant
  VLMChatTemplate AudioPipelineConfig
  ComponentProgressEvent SessionStoppedEvent AgentResponseCompletedEvent
  SpeechTurnDetectionEvent WakeWordDetectedEvent
  PipelineHandle PipelineStartRequest PipelineCompileResult PipelineStopResult PipelineStatus
  ConfigurationEventKind ComponentInitializationEventKind SessionEventKind
  ModelRegistryEventKind StorageEventKind StorageLifecycleEventKind AuthEventKind
  NetworkEventKind FrameworkEventKind HardwareRoutingEventKind PerformanceEventKind
  TelemetryEventKind
)

for t in "${TYPES[@]}"; do
  reasons=""

  # (a) referenced as a field type by any surviving .proto (skip its own declaration)
  proto_ref=$(grep -nE "^[[:space:]]*(optional |repeated )?${t}[[:space:]]+[a-z_]+[[:space:]]*=" idl/*.proto 2>/dev/null | head -3)
  [ -n "$proto_ref" ] && reasons="${reasons}PROTO_FIELD "

  # oneof arms and map values also count
  oneof_ref=$(grep -nE "^[[:space:]]*${t}[[:space:]]+[a-z_]+[[:space:]]*=|<[^>]*\b${t}\b>" idl/*.proto 2>/dev/null | grep -v "^idl/[a-z_]*\.proto:[0-9]*:message\|enum" | head -3)
  [ -n "$oneof_ref" ] && reasons="${reasons}PROTO_ONEOF_OR_MAP "

  # (b) commons produces or reads the C++ symbol
  cpp_ref=$(rg -l --no-messages "${EXCL[@]}" -e "\b${t}\b" \
      sdk/runanywhere-commons/src sdk/runanywhere-commons/include engines runtimes 2>/dev/null | head -3)
  [ -n "$cpp_ref" ] && reasons="${reasons}NATIVE "

  # enum MEMBER usage: SOME_EVENT_KIND -> SOME_EVENT_KIND_* constants
  screaming=$(echo "$t" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/([A-Z]+)([A-Z][a-z])/\1_\2/g' | tr '[:lower:]' '[:upper:]')
  member_ref=$(rg -l --no-messages "${EXCL[@]}" -e "\b${screaming}_[A-Z0-9_]+\b" \
      "${CORPUS[@]}" 2>/dev/null | head -3)
  [ -n "$member_ref" ] && reasons="${reasons}ENUM_MEMBERS "

  # any SDK reference
  sdk_ref=$(rg -l --no-messages "${EXCL[@]}" -e "\b(RA)?${t}\b" "${CORPUS[@]}" 2>/dev/null | head -3)
  [ -n "$sdk_ref" ] && reasons="${reasons}SDK "

  if [ -n "$reasons" ]; then
    echo "LIVE  $t  <- $reasons"
  else
    echo "DEAD  $t"
  fi
done
