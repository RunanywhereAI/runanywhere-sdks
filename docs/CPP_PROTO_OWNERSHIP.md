# C++ and Proto Ownership

This document is the source of truth for where shared behavior belongs across
the five public SDKs: Swift, Kotlin, Flutter, React Native, and Web.

## Ownership Rules

`idl/*.proto` is the canonical data-contract source. Generated protobuf types
are committed for every platform and should be exported directly from public
SDK APIs whenever the platform can use them ergonomically.

`sdk/runanywhere-commons` owns business logic. Download orchestration, model
registry state, load and unload behavior, lifecycle transitions, hardware
routing, backend selection, proto-byte stream/event encoding, tool parsing,
and shared validation must live in C++.

The five SDKs own platform adapters only. Acceptable SDK-side logic includes
HTTP transport registration, filesystem path access, permissions, platform UI
bridges, native async wrappers such as `AsyncStream`, `Flow`, Dart `Stream`,
JS `AsyncIterable`, and memory-safe conversion around C ABI calls.

No SDK should independently reimplement model lifecycle, download policy,
hardware routing, backend selection, or enum value systems that already exist
in proto or C++.

## Public API Rules

Public method names should match across Swift, Kotlin, Flutter, React Native,
and Web unless the platform has a strong naming convention that requires a
small spelling change.

Public data types should be generated proto types by default. A hand-written
public type is allowed only when the platform needs a native ergonomic wrapper,
and then it must have an explicit bridge to and from the generated proto type.

Serialized proto-byte C ABI functions are the SDK-facing default. A C function
is in that default path when its request or response uses serialized generated
proto bytes, `rac_proto_buffer_t`, `proto_bytes`/`proto_size`, or a
`*_proto` callback. The C buffer is only the transport; the public SDK type is
the generated proto message.

Enum values must never be re-numbered locally. If a C ABI enum starts at a
different zero value than the proto enum, the SDK adapter must use an explicit
mapping function at the C boundary.

Backward compatibility is not a design constraint for this cleanup. Prefer the
canonical proto/C++ shape over aliases or duplicated legacy wrappers. Do not
keep duplicate APIs only because SDK bindings or examples still call them; mark
those call sites as migration backlog and delete the duplicate after migration.

Legacy C struct, vtable, callback, and JSON APIs must carry one of these
classifications:

- `internal`: kept for commons, engines, runtimes, plugin loading, or platform
  adapter registration. SDK public APIs must not expose it.
- `compat`: short-lived bridge only when no canonical proto/C++ path exists yet
  or when a documented SDK/example migration blocker still needs implementation.
  New SDK public APIs must not be added on top of it, and every compat surface
  needs a removal trigger.
- `delete after SDK migration`: default classification for duplicate legacy
  public structs, callbacks, non-proto functions, and JSON APIs when a canonical
  proto-byte API or generated solution/service contract exists.

`SDK-facing default` is reserved for serialized proto-byte APIs and is the only
class allowed for new cross-SDK public data surfaces.

## Current Contract Flow

```
idl/*.proto
  -> idl/codegen/generate_all.sh
  -> generated Swift / Kotlin / Dart / TypeScript / Python / C++ proto files
  -> C++ commons business logic and C ABI
  -> platform SDK adapter
  -> public SDK API
```

For TypeScript, `sdk/runanywhere-proto-ts` is the shared generated package for
React Native and Web. Neither SDK should import from `dist/` directly; use the
package export paths such as `@runanywhere/proto-ts/voice_events`.

## Verification Checklist

For any cross-SDK API/type change:

1. Update the proto under `idl/` first when the data contract changes.
2. Run `idl/codegen/generate_all.sh`.
3. Use generated proto types in all five SDK public surfaces unless a native
   wrapper is unavoidable.
4. Keep business behavior in `sdk/runanywhere-commons`; SDKs should call C ABI
   or register platform adapters.
5. Build or typecheck each touched SDK.
6. Build and run commons tests.
7. Run `idl/codegen/ci-drift-check.sh` on a clean tree before merge.

## Platform Adapter Boundaries

HTTP is a platform adapter. SDKs may keep their existing native HTTP stacks,
but those stacks should be registered into the C++ HTTP transport layer so
downloads and network policy remain centralized.

Streaming is a platform adapter. SDKs may expose idiomatic stream primitives,
but the event shape and wire encoding should come from proto-byte callbacks
owned by C++.

Events are centralized on `SDKEvent` proto bytes. The canonical SDK event
surface is `rac/infrastructure/events/rac_sdk_event_stream.h`
(`rac_sdk_event_subscribe`, `rac_sdk_event_publish_proto`,
`rac_sdk_event_publish_failure`) carrying serialized
`runanywhere.v1.SDKEvent` bytes; canonical voice events go through
`rac_voice_agent_set_proto_callback` carrying serialized
`runanywhere.v1.VoiceEvent` bytes; structured errors are
`runanywhere.v1.SDKError` (always wrapped inside an `SDKEvent` envelope when
emitted as an event, or returned as a structured payload from `*_proto`
calls). The legacy struct-based event headers
(`core/rac_analytics_events.h`, `infrastructure/events/rac_events.h`,
`features/*/rac_*_events.h`) are classified `internal` and emit a `#warning`
unless the including translation unit defines `RAC_BUILDING_COMMONS`,
`RAC_INTERNAL_TRANSLATION_UNIT`, or `RAC_ALLOW_INTERNAL_EVENTS`. Public SDK
code MUST NOT include them.

Hardware probing should flow through C++ where a native binding exists. If a
platform temporarily synthesizes a fallback profile, it must return the
generated `HardwareProfileResult` shape and should be replaced by the C++ ABI
binding as soon as that platform binding is available.

The V2 boundary is portable orchestration, not native OS ownership. C++ owns
logical request/response contracts, planning, validation, routing, lifecycle,
registry state, artifact layout, checksum/quota/cache policy, graph/solution
execution, and canonical event encoding. Platform adapters own native HTTP
execution, permissions, secure storage, background transfers, SAF/content URI
and bookmark handles, browser File System Access handles, OS file operations,
battery/thermal/device facts, and media/audio/session APIs.

## VoiceAgent and RAG Implementation Strategy

The V2 architecture exposes L5 solution graphs as a generic compositional
runtime (`PipelineSpec` + `SolutionConfig` in `idl/solutions.proto`,
`solution_runner.cpp` in commons). VoiceAgent and RAG could plausibly be
expressed as L5 graphs — `VAD -> STT -> LLM -> TTS` and
`Embed -> Retrieve -> ContextAssembly -> LLM` respectively — and the
solution converter (`src/solutions/solution_converter.cpp`) already emits
those signatures for the YAML/proto entry points.

**Decision: VoiceAgent and RAG remain bespoke implementations that emit
canonical generated event contracts (Option B).**

### Why bespoke

- **Real-time audio path**: the voice agent owns a lock-free `in_flight`
  atomic, an energy VAD hot-path that elides `sqrt` (compares
  `mean_sq > threshold_sq`) with 4-way loop unrolling, and a strict
  audio-pipeline state machine that prevents microphone/TTS feedback.
  These optimizations live in `src/features/voice_agent/voice_agent.cpp`
  and `src/features/voice_agent/voice_agent_pipeline.cpp` and would not
  survive being decomposed into independent operator nodes that
  communicate through `OperatorEdge` queues.
- **Tight RAG inner loop**: the RAG pipeline integrates USearch HNSW
  vector search, BM25 fusion, and chunk hydration in
  `src/features/rag/rag_backend.cpp` and `vector_store_usearch.cpp`. The
  query path runs hundreds of vector comparisons inside a single
  hot loop and would lose performance if every retrieval step were
  serialized through the graph scheduler.
- **Latency budget**: an L5 solution adds per-edge queueing overhead that
  is acceptable for offline DAGs (e.g. anomaly detection over a sliding
  window) but unacceptable for first-token-to-audio targets in voice and
  for sub-100 ms retrieval-then-generate latency in RAG.
- **Convergence is at the contract layer, not the implementation
  layer**: the cross-SDK guarantee callers depend on is the *byte
  shape* of the streaming events, not the topology of the graph that
  produced them. A bespoke voice agent that emits `runanywhere.v1.VoiceEvent`
  on its proto callback is observationally indistinguishable from an
  L5 solution that composes `VAD/STT/LLM/TTS` operators emitting the
  same proto bytes.

### Canonical event contracts

Both features emit serialized generated proto bytes through the existing
proto-byte ABI surface, identical to what an L5 solution composing the
same primitives would produce:

| Feature | Streaming surface | Wire type | Defined in |
| --- | --- | --- | --- |
| VoiceAgent | `rac_voice_agent_set_proto_callback` (`features/voice_agent/rac_voice_event_abi.h`) | `runanywhere.v1.VoiceEvent` | `idl/voice_events.proto` |
| VoiceAgent (SDK envelope) | `rac_sdk_event_subscribe` carrying `SDKEvent.voice_pipeline` | `runanywhere.v1.SDKEvent` | `idl/sdk_events.proto` |
| RAG (capability events) | `rac_sdk_event_subscribe` carrying `SDKEvent.capability` for `RAG_INGESTION_*`, `RAG_QUERY_*`, `RAG_FAILED` | `runanywhere.v1.CapabilityOperationEvent` | `idl/sdk_events.proto` |
| RAG (request/response) | `rac_rag_query_proto`, `rac_rag_ingest_proto`, `rac_rag_stats_proto`, `rac_rag_clear_proto` | `runanywhere.v1.RAGResult` / `RAGStatistics` | `idl/rag.proto` |
| RAG (server-streaming, optional) | Future: `rac_rag_set_stream_proto_callback` | `runanywhere.v1.RAGStreamEvent` | `idl/rag.proto` (`service RAG.Stream`) |

The voice agent already routes every internal struct event through
`rac::voice_agent::dispatch_proto_event` (translating struct → proto
oneof) and emits richer proto events directly through
`emit_generated_voice_event`, which fans out to both the per-handle
proto callback and the global `SDKEvent` stream.

The RAG proto ABI in `src/features/rag/rac_rag_proto_abi.cpp` publishes
`SDKEvent.capability` events at the canonical lifecycle points
(`RAG_INGESTION_STARTED/COMPLETED`, `RAG_QUERY_STARTED/COMPLETED`,
`RAG_FAILED`). RAG's primary surface is request/response (`Query`
returns a single `RAGResult` proto), so these capability events are
the streaming progress contract today. The proto schema reserves
`runanywhere.v1.RAGStreamEvent` and `service RAG.Stream` for a future
incremental retrieval/generation streaming path; that path is not
required for the bespoke decision and is tracked as a future
enhancement.

### Future migration path

If the L5 solution overhead can be reduced (e.g. operator inlining,
zero-copy edges) to where the voice agent's first-token-to-audio
budget and RAG's retrieval latency targets are met without
modification, the bespoke implementations can be replaced by L5
solution graphs without changing the SDK-visible event contract:

1. Register operator factories for `vad/stt/llm/tts` and
   `embed/retrieve/context/llm` that emit the same `VoiceEvent` /
   `SDKEvent.capability` byte shapes the bespoke implementations
   produce today.
2. Switch `rac_voice_agent_*` and `rac_rag_*` to thin wrappers that
   construct a `SolutionConfig`, run it through `SolutionRunner`, and
   surface the same proto-byte callbacks.
3. SDK adapters (Swift `AsyncStream`, Kotlin `Flow`, Dart `Stream`,
   TS `AsyncIterable`) require no changes because they already
   consume `VoiceEvent` and `SDKEvent` bytes, not the implementation
   internals.

The decision is therefore a current-state implementation choice with
no contract debt — both paths produce identical wire-format events.

## ABI Ownership Inventory

### SDK-Facing Default

| Surface | Current C ABI | Canonical proto contract |
| --- | --- | --- |
| Proto buffer ownership | `foundation/rac_proto_buffer.h` | Transport wrapper for generated proto bytes. Keep as the common return-buffer ABI. |
| Model lifecycle | `core/rac_model_lifecycle.h` | `service Lifecycle` (`idl/lifecycle_service.proto`) over `ModelLoadRequest/Result`, `ModelUnloadRequest/Result`, `CurrentModelRequest/Result`, and `ComponentLifecycleSnapshotRequest/Result`. |
| Model registry | `rac_model_registry_*_proto` in `infrastructure/model_management/rac_model_registry.h` | `service ModelRegistry` (`idl/model_types.proto`) over `ModelInfo`, `ModelInfoList`, `ModelQuery`. |
| Hardware profile | `router/rac_hardware_abi.h` | `service Hardware` (`idl/hardware_profile.proto`) over `HardwareProfileResult`, `AcceleratorInfo`, plus `HardwareAcceleratorPreferenceRequest/Result`; native device facts still come from platform probes. |
| Download workflow | `rac_download_*_proto` and `rac_download_set_progress_proto_callback` in `rac_download_orchestrator.h` | `DownloadPlan/Start/Cancel/Resume/Subscribe` messages and `DownloadProgress`. HTTP bytes are executed by native transports. |
| Storage workflow | `rac_storage_analyzer_*_proto` in `rac_storage_analyzer.h` | `StorageInfo`, `StorageAvailability`, `StorageDeletePlan`, `StorageDeleteResult`; OS file operations stay in adapters. |
| SDK events | `rac_sdk_event_stream.h`, `rac_llm_set_stream_proto_callback`, `rac_voice_agent_set_proto_callback` | `SDKEvent`, `VoiceEvent`, and generated stream events. |
| LLM | `rac_llm_generate_proto`, `rac_llm_generate_stream_proto`, `rac_llm_cancel_proto` | `LLMGenerateRequest`, `LLMGenerationResult`, `LLMStreamEvent`, `SDKEvent`. |
| STT/TTS/VAD components | `rac_stt_component_*_proto`, `rac_tts_component_*_proto`, `rac_vad_component_*_proto` | `STTOptions/STTOutput/STTPartialResult`, `TTSOptions/TTSOutput/TTSVoiceInfo`, `VADConfiguration/VADOptions/VADResult/VADStatistics/SpeechActivityEvent`. |
| STT/TTS/VAD/Diffusion stream callbacks (CPP-03) | `rac_stt_set_stream_proto_callback` + `rac_stt_stream_{start,feed_audio,stop,cancel}_proto`; same shape for `rac_tts_*`, `rac_vad_*`, `rac_diffusion_*` (`features/<modality>/rac_<modality>_stream.h`) | `STTStreamEvent`, `TTSStreamEvent`, `VADStreamEvent`, `DiffusionStreamEvent`. Lifecycle-owned session ids; mirrors the LLM `rac_llm_set_stream_proto_callback` pattern. |
| Embeddings, VLM, diffusion | `rac_embeddings_embed_batch_proto`, `rac_vlm_*_proto`, `rac_diffusion_*_proto` | `EmbeddingsRequest/Result`, `VLMImage/VLMGenerationOptions/VLMResult`, `DiffusionGenerationOptions/Progress/Result`. |
| LoRA | `rac_lora_*_proto` | `LoraAdapterCatalogEntry`, `LoRAAdapterConfig`, `LoRAAdapterInfo`, `LoraCompatibilityResult`. |
| RAG | `rac_rag_session_create_proto`, `rac_rag_ingest_proto`, `rac_rag_query_proto`, `rac_rag_clear_proto`, `rac_rag_stats_proto` | `RAGConfiguration`, `RAGDocument`, `RAGQueryOptions`, `RAGResult`, `RAGStatistics`. |
| Voice agent | `rac_voice_agent_*_proto` | `VoiceAgentComposeConfig`, `VoiceAgentComponentStates`, `VoiceAgentResult`; stream callbacks use generated voice events. |
| Solutions | `rac_solution_create_from_proto` | `SolutionConfig` and `PipelineSpec`; YAML and string feed APIs are not the SDK-facing data contract. |
| Structured output | `rac_structured_output_parse_proto`, `rac_structured_output_generate_proto`, `rac_structured_output_generate_stream_proto`, `rac_structured_output_prepare_prompt_proto`, `rac_structured_output_validate_proto` | `service StructuredOutput` (`idl/structured_output.proto`) with `PreparePrompt`, `Validate`, `Parse`, `Generate`, `GenerateStream` rpcs over `StructuredOutputRequest`, `StructuredOutputParseRequest`, `StructuredOutputValidationRequest`, `StructuredOutputResult`, `StructuredOutputValidation`, `StructuredOutputStreamEvent`. |
| Tool calling | `rac_tool_call_parse_proto`, `rac_tool_call_validate_proto`, `rac_tool_call_format_prompt_proto` | `service ToolCalling` (`idl/tool_calling.proto`) over generated `ToolParseRequest/Result`, `ToolCallValidationRequest/Result`, `ToolPromptFormatRequest/Result`. |

### Deliberately Absent Services

These capabilities have C ABI stubs that intentionally return
`RAC_ERROR_FEATURE_NOT_AVAILABLE` and **MUST NOT** have public IDL `service`
definitions until they have shipping backends and proven cross-SDK
contracts. Adding a `service` block here would imply a public surface that
does not exist and would force every SDK to render dead client stubs.

| Capability | Why no service | Re-introduce when |
| --- | --- | --- |
| Rerank | Stub returns `RAC_ERROR_FEATURE_NOT_AVAILABLE`; no backend ships a rerank op today. The `rerank_ops` slot exists in `rac_engine_vtable_t` for future use only. | A backend implements `rerank_ops` and at least one SDK consumes it end-to-end. Then add `service Rerank` over generated request/result messages. |
| Tokenize | No portable C ABI yet. Tokenization runs inside each backend (llamacpp, sherpa-onnx) and is exposed only through generation paths. | A portable `rac_tokenize_proto` ABI lands and at least one backend supports it. |
| Wake-word | Public SDK facades were deleted during V2 migration; backend C stubs remain `internal`. The voice-agent compose config carries wake-word fields, but there is no standalone wake-word service contract. | A wake-word backend ships, public C ABI exists, and SDKs need to surface streaming wake-word events independently of the voice agent pipeline. |
| Speaker diarization | Stub returns `RAC_ERROR_FEATURE_NOT_AVAILABLE`. No backend implementation, no SDK callers. | A diarization backend ships and at least one SDK consumes it. |

### Legacy Struct And Callback APIs

| Surface | Classification | Replacement / action |
| --- | --- | --- |
| SDK-facing use of `rac/features/*/rac_*_types.h` modality structs and callbacks for LLM, STT, TTS, VAD, VLM, diffusion, embeddings, and voice-agent | `delete after SDK migration` | Generated proto messages are canonical. Migrate SDKs and examples through `*_proto` functions and `rac_proto_adapters`, then delete the public duplicate structs. Backend-private copies may remain only as `internal`. |
| Non-proto `rac_*_component_*` and `rac_*_service_*` functions for LLM, STT, TTS, VAD, VLM, diffusion, and embeddings | `delete after SDK migration` | SDKs should use lifecycle plus `*_proto` calls. Keep only backend smoke-test entry points as `internal`, or remove them once tests move to proto-byte calls. |
| Per-primitive service instance structs such as `rac_llm_service_t`, `rac_stt_service_t`, `rac_tts_service_t`, `rac_vad_service_t`, `rac_vlm_service_t`, `rac_diffusion_service_t`, `rac_embeddings_service_t` | `internal` | Backend dispatch implementation detail. Do not expose from SDK public APIs. |
| `rac_model_types.h`, non-proto registry calls, discovery structs, model filters, and LoRA registry structs | `delete after SDK migration` for SDK-facing use; `internal` for planner helpers | Generated `ModelInfo`, `ModelQuery`, registry proto APIs, and LoRA proto APIs are canonical. Delete public duplicate DTOs after SDK/example migration. |
| `rac_download.h` manager/task structs and non-proto `rac_download_orchestrate*` | `delete after SDK migration` | Use `download_service.proto` workflow. Native transport callbacks stay `internal` adapter contracts for byte fetching/background behavior. |
| `rac_storage_analyzer.h` non-proto structs and `rac_file_manager.h` file callback structs | `delete after SDK migration` for storage result structs; `internal` for adapter callbacks | Storage planning/results should cross SDKs as generated protos. Actual OS file operations remain adapter-owned. |
| Core lifecycle `core/capabilities/rac_lifecycle.h` and component metrics structs | `delete after SDK migration` | Replace SDK-facing state with `sdk_events.proto` lifecycle snapshots and model lifecycle proto results. |
| Legacy event and analytics emitters in `core/rac_analytics_events.h`, `infrastructure/events/rac_events.h`, and `features/*/rac_*_events.h` | `internal` (CPP-08 task — internal-only `#warning` guards added) | Canonical SDK stream is `rac_sdk_event_stream.h` with `SDKEvent` proto bytes. The analytics callback API stays for the in-process telemetry/Sentry pipeline. SDK-side telemetry shims that still register `rac_analytics_events_set_callback` are tracked migration backlog (SWF-04, KOT-11, FLT-04, RN-04, WEB-04); they need to opt in to `RAC_ALLOW_INTERNAL_EVENTS` until they migrate to the proto stream. The deleted `core/rac_events.h` (the older Swift-mirrored `SDKEvent` C struct) is not re-introduced — `infrastructure/events/rac_events.h` is the surviving lower-level publisher. |
| Telemetry, benchmark, logger, structured error, and metrics structs | `internal`; delete any SDK-facing duplicates after migration | C++ may use them for diagnostics. SDK-facing errors/events should use generated `SDKError`/`SDKEvent` shapes. |
| `rac_tool_calling.h` and `rac_llm_structured_output.h` C structs/helpers | `delete after SDK migration` for public helpers; `internal` for parsers | Public SDK contracts should use `tool_calling.proto` and `structured_output.proto`. |
| `server/rac_openai_types.h` and `server/rac_server.h` | `internal` | Local OpenAI-compatible server translation surface, not a five-SDK public data contract. |
| `rac_model_paths.h`, extraction helpers, tokenizer helpers, and image utilities | `internal` | Portable planning/helper code. SDKs should receive generated model/storage/download results rather than these structs. |
| Core init/config/module registry/SDK state APIs in `rac_core.h`, `rac_sdk_state.h`, and environment validation helpers | `compat` only for minimum bootstrap lacking generated contracts | Add generated init/config/state contracts or internalize the APIs; do not expand them as public SDK DTOs. |
| Wake-word and speaker diarization public C stubs | `internal` — SDK facades deleted during V2 migration | C stubs remain for future use. Do not re-add SDK facades until they have generated service/stream proto contracts. |
| LLM thinking-tag helpers in `features/llm/rac_llm_thinking.h` (`rac_llm_extract_thinking`, `rac_llm_strip_thinking`, `rac_llm_split_thinking_tokens`) | `internal` | Portable parser used by C++ when deriving thinking/response splits. SDK-facing splits already arrive inside `LLMGenerationResult`/`LLMStreamEvent` proto bytes; do not expose these helpers as a new public surface. |
| LLM streaming primitives `rac_llm_stream_callback_fn`, `rac_llm_token_event_t`, `rac_llm_token_event_callback_fn`, `rac_llm_stream_handle_t`, `rac_llm_stream_params_t`, `rac_llm_stream_metrics_t`, `rac_llm_stream_result_t`, and `rac_thinking_tag_pattern_t` in `features/llm/rac_llm_types.h` | `delete after SDK migration` | Replaced by `rac_llm_set_stream_proto_callback` (`features/llm/rac_llm_stream.h`) emitting `runanywhere.v1.LLMStreamEvent` bytes. Keep struct callback path only as a backend smoke-test entry until consumers migrate. |
| LLM analytics handles, metrics, and streaming-metrics collector in `features/llm/rac_llm_analytics.h` and `features/llm/rac_llm_metrics.h` (`rac_llm_analytics_handle_t`, `rac_generation_metrics_t`, `rac_streaming_metrics_handle_t`, `rac_streaming_result_t`, `rac_generation_analytics_handle_t`) | `internal` | Diagnostic plumbing used inside commons. SDKs receive aggregated metrics through `SDKEvent`/`LLMStreamEvent`; do not expose these handles. |
| STT/TTS/VAD analytics handles and metrics structs in `features/stt/rac_stt_analytics.h`, `features/tts/rac_tts_analytics.h`, `features/vad/rac_vad_analytics.h` (`rac_stt_analytics_handle_t`, `rac_stt_metrics_t`, `rac_tts_analytics_handle_t`, `rac_tts_metrics_t`, `rac_vad_analytics_handle_t`, `rac_vad_metrics_t`) | `internal` | Internal telemetry sinks. SDK-facing metrics flow via generated `SDKEvent`/component lifecycle protos. |
| Per-primitive component callback typedefs (`rac_llm_component_token_callback_fn`, `rac_llm_component_complete_callback_fn`, `rac_llm_component_error_callback_fn`, `rac_vlm_component_*_callback_fn`, `rac_diffusion_component_*` callback typedefs in `features/llm/rac_llm_component.h`, `features/vlm/rac_vlm_types.h`, `features/diffusion/rac_diffusion_types.h`) | `delete after SDK migration` | SDK streaming bridges should use the proto-byte stream callbacks. Keep struct callbacks only for backend tests until they migrate. |
| STT/TTS/VAD struct streaming callbacks (`rac_stt_stream_callback_t`, `rac_tts_stream_callback_t`, `rac_vad_activity_callback_fn`, `rac_vad_audio_callback_fn`) and the proto callback typedefs alongside them (`rac_stt_proto_stream_event_callback_fn`, `rac_tts_proto_voice_callback_fn`, `rac_tts_proto_chunk_callback_fn`, `rac_vad_proto_stream_event_callback_fn`) | `delete after SDK migration` for struct callbacks; `SDK-facing default` for proto-byte callbacks | Proto-byte callbacks emit `runanywhere.v1.STTStreamEvent`/`TTSOutput`/`TTSVoiceInfo`/`VADStreamEvent` bytes and are the canonical SDK surface. The struct callbacks remain only for non-proto backend smoke tests. |
| Voice agent struct event types: `rac_voice_agent_event_type_t`, `rac_voice_agent_event_t`, `rac_voice_agent_event_callback_fn`, `rac_voice_agent_result_t`, `rac_voice_agent_*_config_t`, `rac_voice_agent_config_t`, and the legacy non-proto `rac_voice_agent_create*`/`process*`/`transcribe`/`generate_response`/`synthesize_speech`/`detect_speech` APIs in `features/voice_agent/rac_voice_agent.h` | `delete after SDK migration` | Use `rac_voice_agent_initialize_proto`, `rac_voice_agent_component_states_proto`, `rac_voice_agent_process_voice_turn_proto`, and the proto-byte event callback in `rac_voice_event_abi.h` (`runanywhere.v1.VoiceEvent` bytes). |
| Audio pipeline state-manager surfaces in `features/voice_agent/rac_voice_agent.h` (`rac_audio_pipeline_state_t`, `rac_audio_pipeline_config_t`, `rac_audio_pipeline_state_name`, `rac_audio_pipeline_can_activate_microphone`, `rac_audio_pipeline_can_play_tts`, `rac_audio_pipeline_is_valid_transition`) | `internal` | Voice-agent feedback prevention helpers used inside commons; SDKs see pipeline state through generated `VoiceAgentComponentStates`/`VoiceEvent`. |
| Energy VAD service in `features/vad/rac_vad_energy.h` (`rac_energy_vad_handle_t`, `rac_energy_vad_config_t`, `rac_energy_vad_stats_t`, `rac_speech_activity_event_t`, `rac_speech_activity_callback_fn`, `rac_audio_buffer_callback_fn`, lifecycle/process/calibration/TTS-feedback APIs) | `internal` | Built-in CPU VAD used by the voice agent and tests. SDK-facing speech detection results cross via VAD proto APIs. |
| Wake-word public types in `features/wakeword/rac_wakeword_types.h` (`rac_wakeword_event_t`, `rac_wakeword_config_t`, `rac_wakeword_model_info_t`, `rac_wakeword_info_t`, `rac_wakeword_callback_fn`, `rac_wakeword_vad_callback_fn`, `rac_wakeword_frame_result_t`, `RAC_ERROR_WAKEWORD_*`) | `internal` | Backend-private feature with no generated proto contract. Do not re-introduce a public SDK facade until a wake-word proto service exists. |
| VLM helper APIs `rac_vlm_get_builtin_template`, `rac_vlm_resolve_model_files`, `rac_vlm_component_load_model_by_id`, and chat-template/model-family enums (`rac_vlm_chat_template_t`, `rac_vlm_model_family_t`, `rac_vlm_image_format_t`) in `features/vlm/rac_vlm_types.h` and `features/vlm/rac_vlm_component.h` | `internal` for helpers/enums; `delete after SDK migration` for SDK-facing struct entry points | Helpers stay portable in commons. Public SDK callers use `rac_vlm_process_proto`/`rac_vlm_stream_proto` with generated `VLMImage`/`VLMGenerationOptions`/`VLMResult`. |
| Diffusion model registry in `features/diffusion/rac_diffusion_model_registry.h` (`rac_diffusion_backend_t`, `rac_diffusion_platform_flags_t`, `rac_diffusion_hardware_t`, `rac_diffusion_model_def_t`, `rac_diffusion_model_strategy_t`, registry init/register/list APIs) | `internal` | Built-in catalog used by the diffusion backend. Public diffusion catalog crosses SDKs through `ModelInfoList`/registry proto APIs, not these structs. |
| Diffusion tokenizer helpers in `features/diffusion/rac_diffusion_tokenizer.h` (`RAC_DIFFUSION_TOKENIZER_VOCAB_FILE`, `RAC_DIFFUSION_TOKENIZER_MERGES_FILE`, `rac_diffusion_tokenizer_get_*`, `rac_diffusion_tokenizer_check_files`, `rac_diffusion_tokenizer_ensure_files`, `rac_diffusion_tokenizer_download_file`, `rac_diffusion_tokenizer_default_for_variant`) | `internal` | Apple CoreML support code. SDKs receive download/storage state through generated download/storage protos. |
| Diffusion JSON convenience helpers `rac_diffusion_component_configure_json`, `rac_diffusion_component_generate_json`, `rac_diffusion_component_get_info_json` in `features/diffusion/rac_diffusion_component.h` | `delete after SDK migration` | Use `DiffusionConfiguration`/`DiffusionGenerationOptions`/`DiffusionResult` proto bytes (also covered in JSON APIs below). |
| Audio utility helpers in `core/rac_audio_utils.h` (`rac_audio_float32_to_wav`, `rac_audio_int16_to_wav`, `rac_audio_wav_header_size`) and `rac_audio_format_enum_t` (defined in STT types) | `internal` | Shared PCM/WAV plumbing for backends and tests. Audio bytes leaving the SDK are wrapped by generated proto results. |
| Component identification enums in `core/rac_component_types.h` (`rac_sdk_component_t`, `rac_capability_resource_type_t`, `rac_component_config_base_t`, `rac_component_output_base_t`, plus mapping helpers) | `delete after SDK migration` | Use `runanywhere.v1.SDKComponent`/`ComponentLifecycleSnapshot` and the per-primitive proto types. |
| Lifecycle/resource enums in `core/capabilities/rac_lifecycle.h` (`rac_lifecycle_state_t`, `rac_resource_type_t`, `rac_lifecycle_metrics_t`, `rac_lifecycle_config_t`, lifecycle service callbacks, `rac_lifecycle_*` C API) | `internal` | Owned by commons; SDKs read lifecycle through `ComponentLifecycleSnapshot` and `ModelLoadResult`/`ModelUnloadResult` proto bytes. |
| Logger surfaces in `core/rac_logger.h` (`rac_log_metadata_t`, `rac_logger_*` APIs, `RAC_LOG_*` macros, `RAC_LOG_META_*`, `rac::Logger` C++ class) | `internal` | Internal diagnostics. Logs reach platform SDKs via the platform adapter `log` callback only. |
| Structured error types in `core/rac_structured_error.h` (`rac_error_category_t`, `rac_stack_frame_t`, `rac_error_t`, `rac_error_create*`/`rac_error_set_*`/`rac_error_to_*`, last-error TLS, `rac_error_log_and_track`, `rac::Error` C++ class) and the simpler model in `core/rac_error_model.h` (`rac_error_model_t`, `rac_make_error_model`, `rac_error_category`) | `internal` | Diagnostic/telemetry implementation. SDK error contracts cross as `runanywhere.v1.SDKError` / `SDKEvent` bytes. |
| Benchmark surfaces in `core/rac_benchmark.h` (`rac_benchmark_timing_t`, `RAC_BENCHMARK_STATUS_*`, `rac_monotonic_now_ms`, `rac_benchmark_timing_init`), `core/rac_benchmark_log.h` (timing→JSON/CSV/log helpers), `core/rac_benchmark_metrics.h` (`rac_benchmark_extended_metrics_t`, `rac_benchmark_metrics_provider_fn`), and `core/rac_benchmark_stats.h` (`rac_benchmark_stats_handle_t`, `rac_benchmark_summary_t`) | `internal` | Diagnostics-only plumbing. Benchmark stats are surfaced to SDKs via generated benchmark/timing protos when needed; no direct C struct exposure. |
| Analytics event surfaces in `core/rac_analytics_events.h` (`rac_event_type_t`, `rac_analytics_*_t` payload structs, `rac_analytics_event_data_t`, `rac_analytics_callback_fn`, `rac_public_event_callback_fn`, `rac_analytics_events_set_*_callback`, `rac_analytics_event_emit`, all `rac_analytics_emit_*` helpers) | `internal` (CPP-08 — `#warning` guard added) | Header now emits `#warning` unless `RAC_BUILDING_COMMONS`, `RAC_INTERNAL_TRANSLATION_UNIT`, or `RAC_ALLOW_INTERNAL_EVENTS` is defined by the including TU. Public SDK code MUST subscribe to `runanywhere.v1.SDKEvent` bytes via `rac_sdk_event_subscribe` / `rac_sdk_event_publish_proto`. The struct callback path remains live as the in-process telemetry sink (Sentry/HTTP exporter); SDK-side bridges that still call `rac_analytics_events_set_callback` are tracked migration backlog. |
| Lower-level publisher in `infrastructure/events/rac_events.h` (`rac_event_t`, `rac_event_subscribe`, `rac_event_publish`, `rac_event_track`, `rac_event_category_t`, `rac_event_destination_t`) | `internal` (CPP-08 — `#warning` guard added) | Same internal-only `#warning` strategy as `rac_analytics_events.h`. Used by lifecycle manager, storage analyzer, device manager, and engine plugins for fine-grained backend telemetry breadcrumbs. Components that emit through this channel ALSO publish a canonical `SDKEvent` through `rac_sdk_event_publish_proto`; the legacy struct stream stays alive only for engine-internal breadcrumbs that have not yet migrated to typed proto fields under `SDKEvent.telemetry`. |
| Per-modality event-type enums and publisher helpers in `features/llm/rac_llm_events.h`, `features/stt/rac_stt_events.h`, `features/tts/rac_tts_events.h`, `features/vad/rac_vad_events.h` | `internal` (CPP-08 — `#warning` guards added; currently no callers — pure dead code surface) | Each header emits `#warning` unless `RAC_BUILDING_COMMONS` / `RAC_INTERNAL_TRANSLATION_UNIT` / `RAC_ALLOW_INTERNAL_EVENTS` is defined. No commons or engine TU currently uses these per-modality publisher functions; SDK-facing emission already consolidates through `SDKEvent` bytes. Safe to delete entirely once a follow-up audit confirms no caller has appeared. |
| Voice-agent component-state enum (`rac_voice_agent_component_state_t`) and `rac_analytics_voice_agent_state_t` payload | `delete after SDK migration` | Use `runanywhere.v1.VoiceAgentComponentStates` / `VoiceEvent` bytes. |
| Foundation proto adapter functions in `foundation/rac_proto_adapters.h` (all `rac_*_to_proto`/`rac_*_from_proto` overloads in `rac::foundation` for STT/TTS/VAD/VLM/Diffusion/LoRA/RAG/Embeddings/Storage/Errors plus `rac_result_to_proto_error_code`/`rac_proto_error_code_to_result`/`rac_category_to_proto`/`rac_proto_to_category`) | `internal` | C ABI ↔ generated proto bridges. SDKs do not call these directly; the `*_proto` functions own the conversion at the C boundary. |
| Voice-agent timing constants (`RAC_VOICE_AGENT_DEFAULT_*_SEC`, `RAC_VOICE_AGENT_LLM_RESPONSE_TIMEOUT_SEC`, `RAC_VOICE_AGENT_TTS_RESPONSE_TIMEOUT_SEC`) and audio-pipeline defaults | `internal` | Backend-private defaults consumed when assembling the pipeline; not part of the SDK public surface. |

### Vtables And Adapter Contracts

| Surface | Classification | Notes |
| --- | --- | --- |
| `rac_engine_vtable_t`, engine manifests, plugin entry/loader/registry, and backend `rac_plugin_entry_*` symbols | `internal` | Stable plugin ABI for engines and router, not SDK public API. |
| `rac_runtime_vtable_t`, runtime registry, and runtime entry symbols | `internal` | Stable L1 runtime ABI. SDKs should not call runtime sessions directly. |
| Per-domain ops vtables `rac_llm_service_ops_t`, `rac_stt_service_ops_t`, `rac_tts_service_ops_t`, `rac_vad_service_ops_t`, `rac_embeddings_service_ops_t`, `rac_vlm_service_ops_t`, `rac_diffusion_service_ops_t` | `internal` | Engine implementation slots inside `rac_engine_vtable_t`. Keep until a future engine ABI replaces them. |
| Backend-specific headers under `include/rac/backends/**` | `internal` | Engine/private registration and direct backend tests only. SDKs route through lifecycle/proto APIs. |
| `rac_http_transport_ops_t`, `rac_platform_adapter_t`, platform LLM/TTS/diffusion callbacks, device callbacks, storage callbacks, file callbacks | `internal` adapter contracts | C++ calls these to delegate native work. They are not C++ ownership of HTTP execution, secure storage, OS files, device facts, or media/session APIs. |
| Raw HTTP client/download APIs in `infrastructure/http/**` | `internal` | Portable fallback/transport plumbing. Native/Web adapters own production HTTP execution and background transfer behavior. |
| CPU runtime provider hook in `plugin/rac_cpu_runtime_provider.h` (`rac_cpu_runtime_provider_t`, `rac_cpu_runtime_register_provider`, `rac_cpu_runtime_unregister_provider`, `rac_cpu_runtime_get_provider_session`) | `internal` | Engine/runtime extension point for the built-in CPU runtime. Not exposed to SDK callers. |
| Platform availability callback in `features/platform/rac_platform_services.h` (`rac_platform_service_t`, `rac_platform_service_availability_callback_t`, `rac_platform_services_register_availability_callback`, `rac_platform_services_is_available`) | `internal` adapter contract | Used by Apple platform plugins to advertise built-in services. Public availability surfaces should rely on plugin/router state and generated capability descriptors. |
| Apple platform LLM callback ABI in `features/platform/rac_llm_platform.h` (`rac_llm_platform_handle_t`, `rac_llm_platform_config_t`, `rac_llm_platform_options_t`, `rac_platform_llm_*_fn`, `rac_platform_llm_callbacks_t`, `rac_platform_llm_set_callbacks`/`get_callbacks`/`is_available`, service `rac_llm_platform_create`/`destroy`/`generate`, `rac_backend_platform_register`/`unregister`) | `internal` adapter contract | Swift Foundation Models bridge. SDKs reach this backend through standard LLM proto APIs after the plugin is registered. |
| Apple platform TTS callback ABI in `features/platform/rac_tts_platform.h` (`rac_tts_platform_handle_t`, `rac_tts_platform_config_t`, `rac_tts_platform_options_t`, `rac_platform_tts_*_fn`, `rac_platform_tts_callbacks_t`, `rac_platform_tts_set_callbacks`/`get_callbacks`/`is_available`, service `rac_tts_platform_create`/`destroy`/`synthesize`/`stop`) | `internal` adapter contract | AVSpeechSynthesizer bridge. SDKs reach it through standard TTS proto APIs. |
| Apple platform diffusion callback ABI in `features/platform/rac_diffusion_platform.h` (`rac_diffusion_platform_handle_t`, `rac_diffusion_platform_config_t`, `rac_diffusion_platform_options_t`, `rac_diffusion_platform_result_t`, `rac_platform_diffusion_*_fn`, `rac_platform_diffusion_callbacks_t`, `rac_platform_diffusion_set_callbacks`/`get_callbacks`/`is_available`, service `rac_diffusion_platform_create`/`destroy`/`generate`/`generate_with_progress`/`cancel`/`result_free`) | `internal` adapter contract | ml-stable-diffusion bridge for Apple platforms. Diffusion proto APIs remain the public surface. |
| Foundation buffer transport in `foundation/rac_proto_buffer.h` (`rac_proto_bytes_t`, `rac_proto_bytes_callback_fn`, `rac_proto_buffer_t`, `rac_proto_bytes_validate`, `rac_proto_bytes_data_or_empty`, `rac_proto_buffer_*` helpers) | `SDK-facing default` | Already canonical for proto-byte ABI; documented here so callers know `rac_proto_bytes_callback_fn` is shared across all proto-byte stream callbacks. |
| RAG legacy session create/query helpers in `features/rag/rac_rag_pipeline.h` (`rac_rag_pipeline_t` typedef, `rac_document_chunk_t`, `rac_search_result_t`, `rac_rag_pipeline_config_t`, `rac_rag_config_t`, `rac_rag_query_t`, `rac_rag_result_t`, `rac_rag_pipeline_create`/`create_standalone`/`add_document(s)`/`query`/`pipeline_query`/`clear_documents`/`get_document_count`/`get_statistics`/`result_free`/`pipeline_destroy`, plus `rac_rag_token_callback_fn`) | `delete after SDK migration` for SDK-facing entry points; `internal` for backend-only helpers | Use `rac_rag_session_create_proto`/`rac_rag_ingest_proto`/`rac_rag_query_proto`/`rac_rag_clear_proto`/`rac_rag_stats_proto` over generated `RAGConfiguration`/`RAGDocument`/`RAGQueryOptions`/`RAGResult`/`RAGStatistics` bytes. |
| RAG backend registration helpers `rac_backend_rag_register`/`rac_backend_rag_unregister` in `features/rag/rac_rag.h` | `internal` | Plugin registration entry point invoked by SDK bootstrap; not a public data contract. |

### JSON String Surfaces (Cross-SDK)

The following Nitro (React Native) surfaces deliberately use JSON strings on
the wire. They are **init-time / transport-time / introspection** entry points
where the JSON subset is identical across Swift, Kotlin, Flutter, React
Native, and Web SDKs (each platform marshals the same keys). Classification:
**`compat`** — canonical exception, migration to proto deferred to a future
iteration. The wire format is clearly labeled; TS callers round-trip through
`JSON.parse`, so there is no ambiguity about encoding.

| Nitro surface (`RunAnywhereCore`) | Shape | Cross-SDK parity |
| --- | --- | --- |
| `initialize(configJson: string): Promise<boolean>` | `{apiKey, baseURL, environment}` | Swift/Kotlin/Flutter pass proto, Web passes JSON; RN passes JSON |
| `registerDevice(environmentJson: string): Promise<boolean>` | Device/environment JSON consumed by C++ `rac_device_register` | Same JSON subset across all 5 SDKs |
| `httpRequest(method, url, headersJson, bodyJson, timeoutMs): Promise<string>` | HTTP request envelope; returns JSON body | Transport adapter; SDK-equivalent code paths elsewhere |
| `authAuthenticate(apiKey, baseURL, deviceId, platform, sdkVersion): Promise<string>` | Returns `{access_token, refresh_token, expires_in, device_id, organization_id, user_id, token_type}` | Same JSON envelope as Swift/Kotlin/Flutter/Web auth paths |
| `authRefreshToken(baseURL: string): Promise<string>` | Returns same auth response JSON | Same JSON envelope as above |
| `getBackendInfo(): Promise<string>` | JSON snapshot of registered backend plugin vtables | Introspection; consumed by TS `JSON.parse` |
| `getDeviceCapabilities(): Promise<string>` | JSON device-capabilities snapshot | Introspection; consumed by TS `JSON.parse` |

**Migration trigger**: Add the following proto messages under `idl/` and
migrate each surface end-to-end in one iteration:
- `SDKInitConfig` (replaces `initialize(configJson)`)
- `DeviceRegisterRequest` (replaces `registerDevice(environmentJson)`)
- `HTTPRequestEnvelope` / `HTTPResponseEnvelope` (replaces `httpRequest`)
- `AuthRequest` / `AuthResponse` (replaces `authAuthenticate` / `authRefreshToken`)
- `BackendInfo` (replaces `getBackendInfo`)
- `DeviceCapabilities` (replaces `getDeviceCapabilities`)

Tracked as `RN-JSON-PROTO-MIGRATE` in
`gaps/gaps/inconsistencies/react-native.md`. The JSON wire form is the
canonical contract until that row ships.

### JSON APIs

| JSON surface | Classification | Replacement / action |
| --- | --- | --- |
| `config_json` in service `create` slots and embeddings/VLM/diffusion backend setup | `internal` | Backend-private escape hatch. Do not surface in SDK public API; replace with typed proto fields when a setting becomes public. |
| Diffusion component JSON helpers: `configure_json`, `generate_json`, `get_info_json` | `delete after SDK migration` | Use `DiffusionConfiguration`, `DiffusionGenerationOptions`, and `DiffusionResult` proto bytes. |
| STT/TTS language JSON arrays and backend `get_languages(..., char** out_json)` | `delete after SDK migration` | Add/consume generated language/voice/result protos. |
| LLM LoRA info JSON and backend model-info JSON | `delete after SDK migration` | Use `LoRAAdapterInfo`, model registry protos, and engine metadata. |
| RAG `metadata_json`, `embedding_config_json`, `llm_config_json`, and `out_stats_json` | `delete after SDK migration` for SDK-facing use | Keep only as internal metadata payloads if the proto explicitly models opaque JSON. Prefer typed `RAGDocument`, `RAGConfiguration`, and `RAGStatistics`. |
| Tool calling and structured-output JSON helpers | `delete after SDK migration` for SDK-facing helpers; `internal` for parsers | SDK public contracts should use generated tool and structured-output protos. |
| Auth, telemetry, benchmark, error, OpenAI server, and network JSON serializers | `internal` | Implementation detail for transport/server/diagnostics. Generated SDK events/errors remain public contract. |
| LLM component LoRA compatibility helper `rac_llm_component_check_lora_compat` (`out_error`) in `features/llm/rac_llm_component.h` | `internal` (RAC_API stripped; `rac_llm_component_get_lora_info` JSON exporter DELETED) | LoRA proto APIs (`rac_lora_*_proto`) own the public surface. The compat check is retained as commons-internal safety net for `rac_lora_apply_proto`. |
| Tool-calling JSON helpers in `features/llm/rac_tool_calling.h` (`rac_tool_call_normalize_json`, `rac_tool_call_definitions_to_json`, `rac_tool_call_result_to_json`, JSON-flavored validate/format APIs ending in `_json`) | `internal` (RAC_API stripped; retained as commons-internal for Flutter B-4 migration + RAG pipeline) | Use `rac_tool_call_parse_proto`/`rac_tool_call_validate_proto`/`rac_tool_call_format_prompt_proto` over generated `ToolParseRequest`/`ToolParseResult`/`ToolCallValidationRequest`/`ToolCallValidationResult`/`ToolPromptFormatRequest`/`ToolPromptFormatResult` bytes. Flutter `dart_bridge_tool_calling.dart` still reaches them via FFI (FLT-07); delete after that migration. |
| Structured-output JSON helpers in `features/llm/rac_llm_structured_output.h` (`rac_structured_output_extract_json`, `rac_structured_output_parse`, `rac_structured_output_find_*`, `rac_structured_output_prepare_prompt`, `rac_structured_output_get_system_prompt`, `rac_structured_output_validate`) and the `rac_structured_output_parse_result_t` struct | `internal` (RAC_API stripped from `_extract_json`/`_find_complete_json`/`_get_system_prompt`; remaining helpers retained for RN HybridRunAnywhereCore+Voice.cpp consumption) | Use `rac_structured_output_parse_proto`/`generate_proto`/`prepare_prompt_proto`/`validate_proto`/`generate_stream_proto` over generated `StructuredOutputRequest`/`StructuredOutputResult`/`StructuredOutputValidation`/`StructuredOutputStreamEvent` bytes. |
| Benchmark JSON/CSV serializers in `core/rac_benchmark_log.h` and `core/rac_benchmark_stats.h` (`rac_benchmark_timing_to_json`, `rac_benchmark_timing_to_csv`, `rac_benchmark_timing_log`, `rac_benchmark_stats_summary_to_json`) | `internal` | Diagnostic exporters used by tools/tests. Cross-SDK benchmark surfaces should use typed proto bytes. |

### Follow-Up Migration Backlog

If any SDK binding or example app still calls a legacy struct, callback,
non-proto component/service function, or JSON helper listed as
`delete after SDK migration`, do not reclassify that API as preserved
compatibility. Add an implementation task to migrate the caller to the
canonical proto-byte API, generated proto type, or generated solution/service
contract, then remove the duplicate C ABI surface.

## Bridge Layer Audit (CPP-09)

Every SDK interposes a thin C/C++ bridge between its host language and the
`rac_*` C ABI. The V2 goal is for those bridges to be *proto-byte
pass-throughs* only: receive proto bytes from the SDK, call the matching
`*_proto` C ABI, return proto bytes back. No struct construction, JSON
parsing, option building, fallback policy, or business decisions should live
in the bridge layer; commons owns those.

This section records the per-bridge audit and the residual non-proto code
that still needs migration. The bridge files themselves are listed as
`internal` adapter glue — they are not SDK public surfaces. The migration
target is always to delete the non-proto entrypoint after the SDK Kotlin /
Swift / Dart / TypeScript caller has moved to the proto-byte equivalent
(tracked in the per-SDK gap docs under `gaps/gaps/inconsistencies/`).

### Bridge Files Inventory

| SDK | Bridge file(s) | Approx LOC | Pattern |
| --- | --- | --- | --- |
| Android / JVM | `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` | 7800 | JNI `Java_*` exports calling `rac_*` C ABI |
| Android / JVM (HTTP) | `sdk/runanywhere-commons/src/jni/okhttp_transport_adapter.cpp` | 740 | Platform HTTP transport vtable (internal adapter) |
| Web | `sdk/runanywhere-web/wasm/src/wasm_exports.cpp` | 670 | Emscripten `EMSCRIPTEN_KEEPALIVE` `sizeof`/`offsetof` helpers + version + dev-config |
| React Native | `sdk/runanywhere-react-native/packages/core/cpp/HybridRunAnywhereCore*.cpp` | 5200 | Nitro `HybridObject` methods, async `Promise<ArrayBuffer>` over `*_proto` |
| React Native | `sdk/runanywhere-react-native/packages/core/cpp/HybridLLM.cpp` | 87 | Pure proto callback fan-out for `rac_llm_set_stream_proto_callback` |
| React Native | `sdk/runanywhere-react-native/packages/core/cpp/HybridVoiceAgent.cpp` | 130 | Pure proto callback fan-out for `rac_voice_agent_set_proto_callback` |
| React Native | `sdk/runanywhere-react-native/packages/core/cpp/bridges/*.cpp` | 4000 | Per-domain platform-adapter helpers (Init, Auth, Device, Download, FileManager, HTTP, RAG, Storage, Telemetry, ModelRegistry) |
| Flutter | `sdk/runanywhere-flutter/packages/runanywhere/src/flutter_rag_bridge.cpp` | 480 | RAG-only thin C entrypoints for Dart FFI; uses non-proto `rac_rag_*` struct API |
| Flutter | `sdk/runanywhere-flutter/packages/runanywhere/ios/Classes/URLSessionHttpTransport.mm` | 460 | iOS HTTP transport vtable (internal adapter) |
| Swift | `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/CppBridge*.swift` | n/a | Swift-side bridge; the C side it consumes is the canonical `rac_*` C ABI directly. No additional C++ shim ships in the Swift SDK. |

### Functions Classified as Thin Pass-Through (Good)

These calls already meet the V2 invariant: bytes in, bytes out, no logic.
Leave them as-is.

| SDK / Bridge | Functions | Notes |
| --- | --- | --- |
| JNI | `racLlmGenerateProto`, `racLlmGenerateStreamProto`, `racLlmCancelProto` | `callProtoBufferFn` over `rac_llm_*_proto` |
| JNI | `racSttComponentTranscribeProto`, `racSttComponentTranscribeStreamProto`, `racTtsComponentSynthesizeProto`, `racTtsComponentSynthesizeStreamProto`, `racTtsComponentListVoicesProto`, `racVadComponentConfigureProto`, `racVadComponentProcessProto`, `racVadComponentGetStatisticsProto`, `racVadComponentSetActivityProtoCallback` | All over `rac_<modality>_*_proto` |
| JNI | `racVlmProcessProto`, `racVlmProcessStreamProto`, `racVlmCancelProto` | Over `rac_vlm_*_proto` |
| JNI | `racDiffusionGenerateProto`, `racDiffusionGenerateWithProgressProto`, `racDiffusionCancelProto` | Over `rac_diffusion_*_proto` |
| JNI | `racEmbeddingsEmbedBatchProto` | Over `rac_embeddings_embed_batch_proto` |
| JNI | `racRagSessionCreateProto`, `racRagSessionDestroyProto`, `racRagIngestProto`, `racRagQueryProto`, `racRagClearProto`, `racRagStatsProto` | Over `rac_rag_*_proto` |
| JNI | `racLoraApplyProto`, `racLoraRemoveProto`, `racLoraListProto`, `racLoraStateProto`, `racLoraCompatibilityProto`, `racLoraRegisterProto` | Over `rac_lora_*_proto` |
| JNI | `racVoiceAgentInitializeProto`, `racVoiceAgentComponentStatesProto`, `racVoiceAgentProcessVoiceTurnProto` | Over `rac_voice_agent_*_proto` |
| JNI | `racToolCallParseProto`, `racToolCallFormatPromptProto`, `racToolCallValidateProto` | Over `rac_tool_call_*_proto` |
| JNI | `racStructuredOutputParseProto`, `racStructuredOutputPreparePromptProto`, `racStructuredOutputValidateProto` | Over `rac_structured_output_*_proto` |
| JNI | `racHardwareProfileGet`, `racHardwareGetAccelerators`, `racHardwareSetAcceleratorPreference` | Proto-byte hardware ABI |
| JNI | `racStorageInfoProto`, `racStorageAvailabilityProto`, `racStorageDeletePlanProto`, `racStorageDeleteProto` | Over `rac_storage_analyzer_*_proto` |
| JNI | `racSdkEventSubscribe`, `racSdkEventUnsubscribe`, `racSdkEventPublishProto`, `racSdkEventPoll`, `racSdkEventPublishFailure` | Over `rac_sdk_event_*` proto callbacks |
| JNI | `racDownloadSetProgressProtoCallback`, `racDownloadPlanProto`, `racDownloadStartProto`, `racDownloadCancelProto`, `racDownloadResumeProto`, `racDownloadProgressPollProto` | Over `rac_download_*_proto` |
| JNI | `racModelLifecycleLoadProto`, `racModelLifecycleUnloadProto`, `racModelLifecycleCurrentModelProto`, `racComponentLifecycleSnapshotProto` | Over `rac_model_lifecycle_*_proto` |
| JNI | `racModelRegistryRegisterProto`, `racModelRegistryUpdateProto`, `racModelRegistryGetProto`, `racModelRegistryListProto`, `racModelRegistryQueryProto`, `racModelRegistryListDownloadedProto`, `racModelRegistryRemoveProto`, `racModelRegistryRefreshProto` | Over `rac_model_registry_*_proto` |
| JNI | `racSolutionCreateFromProto` | Over `rac_solution_create_from_proto` |
| WASM | All `rac_wasm_sizeof_*` / `rac_wasm_offsetof_*` helpers | Pure compiler `sizeof()`/`offsetof()` exports |
| WASM | `rac_wasm_dev_config_*` | Pure forwarders to `rac_dev_config_*` |
| WASM | (linked symbols) `rac_*_proto` and `rac_*_set_*_proto_callback` are exported from the WASM via the linker — TS adapters call them through Emscripten `ccall`/`_rac_*`. The WASM bridge layer holds no business logic. |
| Nitro | All `HybridRunAnywhereCore::<feature>Proto` methods in `+Lifecycle`, `+Registry` (proto variants), `+Download`, `+Storage`, `+Hardware`, `+Tools`, `+Voice` (proto variants), `+Solutions` | Run async on a worker, copy `ArrayBuffer` in, copy `ArrayBuffer` out around `*_proto` |
| Nitro | `HybridLLM::subscribeProtoEvents`, `HybridVoiceAgent::subscribeProtoEvents` | Proto-byte trampoline → JS fan-out |
| Nitro | `HybridRunAnywhereCore+Telemetry`, `+SecureStorage`, `+Http`, `+Events` | Platform-adapter pass-throughs (internal adapter contracts) |
| Flutter | `flutter_rag_create_pipeline_proto` style entrypoints (when added) | Currently the Flutter bridge has none — see migration target below |

### Functions That Need Migration (Bad, but Tracked)

These bridges still build C structs, parse JSON, apply defaults, or call
non-proto C ABI. The migration target exists in commons; the SDK-side
caller change is the gating work. None of these can be silently rewritten
in this audit — each has a per-SDK gap entry.

| Bridge file (LOC range) | Function | Today | Target | Gap doc |
| --- | --- | --- | --- | --- |
| `runanywhere_commons_jni.cpp` (929–1022) | `racLlmComponentGenerate` | Builds `rac_llm_options_t` from JSON, calls `rac_llm_component_generate`, returns JSON | Delete; replace with `racLlmGenerateProto` + lifecycle handle | `gaps/gaps/inconsistencies/kotlin.md` (LLM struct vs proto) |
| `runanywhere_commons_jni.cpp` (1230–1645) | `racLlmComponentGenerateStream`, `racLlmComponentGenerateStreamWithCallback`, `racLlmComponentGenerateStreamWithTiming` | Struct callbacks, JSON option parsing | Delete; replace with `rac_llm_set_stream_proto_callback` + `racLlmGenerateStreamProto` (already exposed) | `gaps/gaps/inconsistencies/kotlin.md` |
| `runanywhere_commons_jni.cpp` (1869–2272) | `racSttComponent*` non-proto family (`Transcribe`, `TranscribeFile`, `TranscribeStream`, `Cancel`, `GetState`, `IsLoaded`, `GetLanguages`, `DetectLanguage`) | Struct paths, char-array → JSON | Delete; replace with `racSttComponentTranscribeProto` + lifecycle proto APIs | `gaps/gaps/inconsistencies/kotlin.md` |
| `runanywhere_commons_jni.cpp` (2274–2496) | `racTtsComponent*` non-proto family | Same | Delete; replace with `racTtsComponent*Proto` | `gaps/gaps/inconsistencies/kotlin.md` |
| `runanywhere_commons_jni.cpp` (2498–2771) | `racVadComponent*` non-proto family | Same | Delete; replace with `racVadComponent*Proto` | `gaps/gaps/inconsistencies/kotlin.md` |
| `runanywhere_commons_jni.cpp` (2773–2980) | `racModelRegistrySave`, `racModelRegistryGet`, `racModelRegistryGetAll`, `racModelRegistryGetDownloaded`, `racModelRegistryRemove`, `racModelRegistryUpdateDownloadStatus` | DELETED in B-1 (RAC_API + JNI both removed; Kotlin had already moved to `racModelRegistry*Proto`). | Already deleted. | — |
| `runanywhere_commons_jni.cpp` (4573–4732) | `racToolCallFormatPromptJson`, `racToolCallFormatPromptJsonWithFormat`, `racToolCallFormatPromptJsonWithFormatName`, `racToolCallBuildInitialPrompt`, `racToolCallBuildFollowupPrompt`, `racToolCallNormalizeJson`, `racToolCallParse` | DELETED in B-1 (legacy JSON JNI thunks removed; Kotlin had already moved to `racToolCall*Proto`). | Already deleted. | — |
| `runanywhere_commons_jni.cpp` (4810–5219) | `racVlmComponent*` non-proto family (Create/Destroy/LoadModel/Unload/Cancel/LoadModelById/IsLoaded/GetModelId/Process/ProcessStream/SupportsStreaming/GetState/GetMetrics) | Builds `rac_vlm_image_t` from JNI parameters, returns JSON | Replace with proto family (`racVlm*Proto` and lifecycle proto). Some lifecycle gaps exist (no `rac_vlm_create_proto`); migration coupled to commons API. | `gaps/gaps/inconsistencies/kotlin.md` |
| `runanywhere_commons_jni.cpp` (3812–4434) | Telemetry / Device / Analytics emit families (`racTelemetryManager*`, `racDeviceManager*`, `racAnalyticsEvent*`) | Struct/event-based platform callbacks (these are platform adapter contracts, classification: `internal`) | Keep as adapter contracts — SDK public events go via `racSdkEvent*`. Migration is on the SDK side (delete duplicate analytics shims). | `gaps/gaps/inconsistencies/kotlin.md` (telemetry KOT-11) |
| `runanywhere_commons_jni.cpp` (4398–4571) | `racDevConfig*` accessors | Pure forwarders to `rac_dev_config_*` (returns env strings). Classification: `internal`. | Keep as-is (build/test config only). |
| `runanywhere_commons_jni.cpp` (5221–5700) | `nativeExtractArchive`, `nativeFileManager*` family | Platform adapter callbacks (file ops, paths). Classification: `internal` adapter contract. | Keep as-is — these are file-system adapters, not data contracts. |
| `runanywhere_commons_jni.cpp` (7336–7560) | `racHttpDownloadExecute`, `racHttpRequestExecute` | Platform-side HTTP entrypoints for Kotlin OkHttp transport. Classification: `internal` adapter contract. | Keep as-is — internal HTTP transport bridge. |
| `runanywhere_commons_jni.cpp` (7732–7785) | `racVadComponentGetStatistics` | Builds JSON from struct values (temporary until Kotlin migrates to `racVadComponentGetStatisticsProto`). | Replace with proto once Kotlin fully switches over. | `gaps/gaps/inconsistencies/kotlin.md` |
| `runanywhere_commons_jni.cpp` | `racModelRegistryFetchAssignments` (legacy JSON shim), `racModelAssignmentFetch`, `racModelAssignmentSetCallbacks` | DELETED in B-1. Kotlin now calls `racModelRegistryFetchAssignmentsProto`. | Already deleted. | — |
| `HybridRunAnywhereCore+Registry.cpp:421` | `refreshModelRegistry(includeRemoteCatalog, rescanLocal, pruneOrphans)` | Builds `rac_model_registry_refresh_opts_t` struct, calls `rac_model_registry_refresh` | Replace with `rac_model_registry_refresh_proto` building a `ModelRegistryRefreshRequest`. Trivial in commons; needs Nitro spec change (TS contract takes booleans → SDK should pass proto bytes). | `gaps/gaps/inconsistencies/react-native.md` |
| `HybridRunAnywhereCore+Registry.cpp:390` | `checkCompatibility(modelId)` | Calls `CompatibilityBridge::checkCompatibility` and emits hand-built JSON | Replace once a `rac_model_compatibility_*_proto` ABI exists (currently absent — commons backlog). | `gaps/gaps/inconsistencies/cpp-layer.md` (item 1) |
| `HybridRunAnywhereCore+Tools.cpp:238–284` | `ragCreatePipeline`, `ragAddDocument`, `ragAddDocumentsBatch`, `ragQuery`, `ragClearDocuments`, `ragGetDocumentCount`, `ragGetStatistics`, `ragDestroyPipeline` | Calls `RAGBridge::*` which uses non-proto `rac_rag_pipeline_*` struct API + JSON | Delete; the Nitro spec already has `ragCreatePipelineProto`/`ragIngestProto`/`ragQueryProto`/`ragClearProto`/`ragStatsProto` siblings. Remove the legacy methods after RN TS callers migrate. | `gaps/gaps/inconsistencies/react-native.md` |
| `HybridRunAnywhereCore+Tools.cpp:373–454` | `embeddingsCreateProto` (despite the name) | Calls non-proto `rac_embeddings_create` / `rac_embeddings_create_with_config` / `rac_embeddings_initialize` (with `configJson`) | Currently no `rac_embeddings_create_proto` exists — commons backlog. Bridge stays as-is until commons exposes a proto-byte session create. The `embeddingsEmbedBatchProto` half is already pass-through. | `gaps/gaps/inconsistencies/cpp-layer.md` (item 1, 3) |
| `HybridRunAnywhereCore+Voice.cpp:122–134` | `getGlobalLLMHandle()` | Calls `rac_llm_component_create` directly to maintain a global handle | Move to lifecycle: `rac_model_lifecycle_load_proto` already returns the LLM handle. The bridge should treat the lifecycle proto load as the single source of the live handle. | `gaps/gaps/inconsistencies/react-native.md` |
| `HybridRunAnywhereCore+Voice.cpp` (LoRA helpers) | `callLoraRequestProto` / `callLoraCatalogProto` | Already call `rac_lora_*_proto` — pass-through | None — keep |
| `bridges/RAGBridge.cpp` | Whole file | Wraps non-proto `rac_rag_pipeline_*` struct API for the RN legacy `rag*` Nitro methods | Delete after the RN SDK switches all callers to `rag*Proto` Nitro methods | `gaps/gaps/inconsistencies/react-native.md` |
| `bridges/ModelRegistryBridge.cpp` | `addModel`, `getModel`, `getAllModels`, `getModels(filter)`, `getDownloadedModels`, `modelExists`, `isModelDownloaded`, `getModelPath`, `getModelCount` | Wraps non-proto `rac_model_registry_*` struct API and uses `ModelInfo`/`ModelFilter` C++ types | Delete after RN moves to `racModelRegistry*Proto`. `getHandle()` is the only piece commons-side still consumes (used by lifecycle/storage proto wrappers); keep that as `internal`. | `gaps/gaps/inconsistencies/react-native.md` |
| `bridges/CompatibilityBridge.cpp` | `checkCompatibility(modelId)` | Computes compatibility from struct registry data | Replace once commons exposes a compatibility proto ABI | `gaps/gaps/inconsistencies/cpp-layer.md` |
| `flutter_rag_bridge.cpp` | `flutter_rag_create_pipeline`, `flutter_rag_add_document`, `flutter_rag_add_documents_batch`, `flutter_rag_query`, `flutter_rag_clear_documents`, `flutter_rag_get_document_count`, `flutter_rag_get_statistics`, `flutter_rag_destroy_pipeline` | Wraps non-proto `rac_rag_pipeline_*` API; uses JSON + filesystem scanning (GGUF + tokenizer discovery) for model paths | Replace with `rac_rag_session_create_proto` / `rac_rag_ingest_proto` / `rac_rag_query_proto` / `rac_rag_clear_proto` / `rac_rag_stats_proto`. Commons proto APIs already exist. | `gaps/gaps/inconsistencies/flutter.md` |

### Summary

- **JNI** (Android/JVM): The proto-byte path is largely complete. Roughly half the
  JNI surface area is non-proto duplicates that no Kotlin code paths exercise
  any more (`racToolCall*Json`, `racModelRegistry{Save,Get,GetAll,...}`).
  Some active non-proto callers remain in Kotlin (`racLlmComponentGenerate`,
  `racLlmComponentGenerateStreamWithCallback`); deletion is gated on KOT-* SDK
  migration tasks.
- **WASM**: Already a thin pass-through. The bridge file only exposes
  `sizeof`/`offsetof` helpers and dev-config getters; all `rac_*_proto`
  symbols are linked in via the static C++ archive and called directly from
  TypeScript adapters.
- **Nitro** (React Native): The `*Proto` Nitro methods are all clean
  pass-throughs. The legacy `rag*` (non-proto) methods, `refreshModelRegistry`
  (struct opts), `embeddingsCreate*`-style handle creation, and
  `checkCompatibility` JSON path remain. The RN TS spec has sibling proto
  methods for RAG; legacy can be deleted after RN TS callers move.
- **Flutter**: The only C++ shim is `flutter_rag_bridge.cpp`, and it still
  calls the non-proto `rac_rag_pipeline_*` struct API. Migration to the
  proto API is straightforward in commons but requires a Dart-side change.
- **Swift**: Has no C++ shim — the Swift bridge files in
  `Sources/RunAnywhere/Foundation/Bridge/` are Swift code that calls the
  `rac_*` C ABI directly through the SPM module map. The audit above
  applies to the C side already.

### Validation

Bridge audit changes are documentation-only. To re-verify after future
migrations:

```bash
# Build commons (no JNI)
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build

# Build commons + JNI
cmake -B build-jni -DRAC_BUILD_JNI=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build-jni

# Per-SDK typecheck (RN, Web)
( cd sdk/runanywhere-react-native && yarn typecheck )
( cd sdk/runanywhere-web && npm run typecheck )
```
