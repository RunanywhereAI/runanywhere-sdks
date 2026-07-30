# Proto and SDK noise reduction

Status: Phases 0, 1, and 2 complete. Phase 3 next.

Phase 2 result: comments went from 41% of the corpus to 19%, and `idl/` from 9,682 to 6,890 lines.
Twenty files rewritten. Because these were whole-file rewrites of wire contracts, every declaration
was diffed against HEAD: all 130 error enum name/value pairs, all 28 `rac_default` values, and all
VLM, LLM, and model field numbers are byte-identical apart from the messages Phase 1 deleted.

Four annotation bounds corrected to match commons: `frame_length_ms` min 1 to 20, `sample_rate`
min 1 to 8000, `calibration_multiplier` min 1.5 to 1.2, and the activation-threshold comment now
states the real warn band.

Deliberately kept: the ~120 inline `// RAC_ERROR_*` annotations in `ErrorCode`, which are the
cross-reference into `rac_error.h`. Stripping them meant retyping 120 wire values by hand.

Phase 1 result: `idl/` went 10,578 to 9,682 lines (896 lines, 8.5%). 43 dead types deleted, 24
service blocks, 43 of 47 `reserved` statements, 11 unused stream wrappers, and one whole file
(`lifecycle_service.proto`). Flutter's public proto surface went from 355 generated classes to 24
named ones. Electron unexported 30 internal symbols.

Verified: commons 95/96 ctest (the one failure, `auth_secure_storage_tests`, is a pre-existing Linux
segfault unrelated to protos), Kotlin compile + 94/94 + ktlint, Flutter `dart analyze` clean on SDK
and example, RN `tsc` clean, Web typecheck clean, Electron build + 390/390, Python 593 passed /
10 skipped, centralization gate clean.

Not verified here: Swift. `protoc-gen-swift` is not installable on this Linux host, so
`sdk/runanywhere-swift/Sources/RunAnywhere/Generated/` is now stale relative to the IDL. That
regeneration must happen on macOS before this lands.

Decisions taken at review: delete `Interruption` (D7), collapse `ReasoningOptions` (D11), delete the
deprecation shims (open question 3).

Companion to `public_api_spec.md`, which defined the v3 shape. That work reorganized the surface.
This work removes what shouldn't be in it at all.

## Why now

Five audits ran against `idl/` (10,578 lines, 37 files) and the eight SDK public surfaces, plus three
studies of reference SDKs (Pinecone, AssemblyAI, Google Gen AI, Cactus Compute, OpenAI, LiveKit).

The headline numbers:

| Layer | Today | Target |
|---|---|---|
| `idl/` lines | 10,578 | ~7,600 (26 to 28% cut) |
| `idl/` comment lines | 4,292 (41% of the corpus) | ~15%, matching `segmentation.proto` and `download_service.proto` |
| Dead message/enum blocks | 69 | 0 |
| Dead fields | 123 | 0 |
| Public types, Flutter | ~533 | 48 |
| Public types, Electron | 157 | 48 |
| Public types, Kotlin | 120 | 48 |
| Public types, Swift | 75 | 48 |
| Public types, Web | 68 | 48 |
| Public types, Python | 111 | 48 |
| Public types, React Native | 104 | 48 |

The 48 is a floor with a rule attached: no field in it gets silently dropped before reaching native.
That rule is what makes the number meaningful. Today we ship option fields that lie.

## What the reference SDKs settled

Three of the vendors we studied have already run the migration we're contemplating, and all three
moved the same direction.

**Google dissolved its fat config object.** `GenerateContentConfig` carried 35 fields, about ten of
them nested config objects. The replacement promotes the fields people actually set to top-level
request params and keeps a 9-field `generation_config`. `temperature`, `top_p`, and `top_k` are gone
from the primary surface entirely.

**Correlated knobs became one ordinal enum.** `thinkingConfig{include_thoughts, thinking_budget}`
became `thinking_level: minimal|low|medium|high`. OpenAI landed in the same place with
`reasoning.effort`. Both replaced a boolean plus a numeric budget that required a per-model lookup
table to use correctly.

**Nesting won, but only after both vendors shipped flat first.** LiveKit deprecated eleven flat
constructor arguments into one `turn_handling` struct. OpenAI moved `reasoning_effort` to
`reasoning.effort` and `response_format` to `text.format`. We already have `turnHandling`, so we are
on the right side of this one.

**AssemblyAI has no diarization result type.** Setting `speaker_labels: true` fills `utterances[]` on
the same transcript and stamps `.speaker` onto the existing words. One result object, two views over
it. We model the same capability with five messages and two enums.

**Pinecone's user constructs zero objects.** Records are plain maps where `_id` is reserved and
every other key is user data. Reranking is a sub-object of `search`, not a second call.
`create_index_for_model` provisions the embedding model so the caller never downloads or dimensions
one.

**Cactus loads lazily.** `CactusLM.complete()` calls `init()` itself, so a fresh instance with a
downloaded model just works: four lines to first token. Their own Flutter and Kotlin SDKs skip the
lazy path and are visibly more verbose, which is the pattern arguing for itself.

Two things worth knowing about the competition. Cactus has no real Swift SDK; their binding is one
line of `@_exported import cactus` and users call `cactus_complete` with ten positional arguments,
five consecutive nils, and a caller-sized 65536-byte buffer. And their four platforms disagree with
each other on nearly every name (`complete` vs `generateCompletion`, `destroy` vs `unload`,
`functionCalls` vs `toolCalls`, `decodeTps` vs `tokensPerSecond`). Our proto-generated types prevent
that class of drift, which is an edge worth protecting.

What not to copy: OpenAI carries three spellings for the same concept across its three APIs
(`response.completed` vs `response.done`, `response.audio.delta` vs `response.output_audio.delta`,
`input_tokens` vs `prompt_tokens`). That is the exact failure our proto-canonical-types rule exists
to prevent.

## Decisions

### D1. Delete the dead proto types and fields

**Revised after verification. The audit's list was 71 types; only 36 are safe to delete.**

The audit asked one question: does any SDK read this symbol? That misses two ways a type stays
alive, and both bite:

1. **Another `.proto` references it as a field type.** `ModelRuntimeCompatibility` was listed as
   "fully orphaned, no external ref and no proto ref." It is `ModelInfo.compatibility = 29`
   (`model_types.proto:370`), a field on the one message we persist to `.rac-manifest.binpb`.
   Deleting it would have changed the manifest shape.
2. **Commons produces it even when no SDK consumes it.** The audit called 13 `*EventKind` enums dead
   because "no SDK ever switches on them." Commons sets them: `STORAGE_EVENT_KIND_*`
   (`events.cpp:517`, `:525`, `:534`), `DEVICE_EVENT_KIND_*` (`:545`, `:554`),
   `NETWORK_EVENT_KIND_*` (`:568`). Those events flow to telemetry, so the backend is the consumer
   the corpus scan could not see.

Re-verified with `scratchpad/verify_dead_v2.sh`, which checks proto field types, oneof arms, map
values, native producers, and enum-member usage:

- **36 confirmed dead**, deletable with no change to any surviving message:
  `ChatConversationState`, `ChatGenerationResult`, `ChatStreamEvent`, `ClassificationResult`,
  `ComponentLifecycleSnapshotRequest`, `DiffusionConfig`, `DiffusionServiceState`,
  `EmbeddingsServiceState`, `EntityExtractionResult`, `HardwareAcceleratorPreferenceRequest`,
  `HardwareAcceleratorPreferenceResult`, `HardwareAcceleratorsRequest`, `HardwareProfileRequest`,
  `HybridCapability`, `LLMGenerationStatus`, `ModelDeleteRequest`, `NERResult`, `NpuProbeRequest`,
  `PipelineCompileResult`, `PipelineHandle`, `PipelineStartRequest`, `PipelineStopResult`,
  `PluginInfoList`, `RAGIngestRequest`, `RAGIngestResult`, `RAGQueryRequest`, `RAGServiceState`,
  `SDKEventPublishRequest`, `SDKEventPublishResult`, `SDKEventSubscribeRequest`, `SentimentResult`,
  `STTLanguageDetectionResult`, `ToolCallingSessionCreateResult`,
  `ToolCallingSessionDestroyRequest`, `ToolCallingStreamEvent`, `ToolRegistrySnapshot`.

- **35 referenced by a surviving proto.** Most are transitively dead (`ChatStreamEventKind` exists
  only for `ChatStreamEvent.kind`, and `ChatStreamEvent` is dead; same for `PipelineStatus`,
  `SDKEventFilter`, `Sentiment`, `ClassificationCandidate`, `DiffusionTokenizerSource*`). Deleting
  those needs a transitive pass. The rest are genuinely live and stay: `ModelRuntimeCompatibility`,
  `PerformanceMetrics`, `VLMChatTemplate`, `DiffusionCapabilities`, `AudioPipelineConfig`, `NPUChip`,
  and the `*EventKind` enums commons populates.

**Scope consequence:** deleting a type whose only referent is a field on a *live* message means
changing that message's shape, which this plan deliberately put in Phase 3. So Phase 1 does the 36,
and the transitive tail moves to Phase 3 where field-number movement is already in scope.


69 message and enum blocks with no consumer outside `idl/` and generated code. 123 dead fields.
Both lists are enumerated in the audit with the greps that came back empty.

Two clusters worth naming. `DiffusionCapabilities` has eleven fields and all eleven are dead, so the
message goes. The NLP-task half of `structured_output.proto` (`Sentiment`, `SentimentResult`,
`NERResult`, `ClassificationResult`, `ClassificationCandidate`, `EntityExtractionResult`) is dead
wholesale.

One caveat found during the audit: `sdk/runanywhere-electron/src/proto/*.ts` is a vendored copy of
`@runanywhere/proto-ts`, not a codegen output path, so a naive scan counts it as a real consumer.
Thirty of the 69 dead types only looked alive because of it. Any re-verification pass has to exclude
that directory.

### D2. Delete the `service` blocks

24 blocks, 272 lines, and no codegen consumes them. `generate_ts.sh` passes
`outputServices=false`, `generate_swift.sh` deletes `*.grpc.swift`, `generate_kotlin.sh` deletes
`*Client.kt`, `generate_dart.sh` strips `*.pbgrpc.dart`, and the C++ and Python scripts never invoke
a grpc plugin. `generate_streams.sh` works off a hardcoded 12-tuple table and does not parse the
service declarations at all.

Only 2 of the 13 emitted stream wrappers are ever imported (`voice_agent_service_stream`,
`llm_service_stream`). The other 11 have zero importers.

`lifecycle_service.proto` is 49 lines containing nothing but a service block, and both types it
names are dead. Delete the file.

### D3. Unify the four audio-encoding enums into one

`AudioEncoding` (voice_events), `DiarizationAudioEncoding`, `VADAudioEncoding`, and
`STTAudioEncoding`. Three are byte-identical; the fourth adds `CONTAINER = 3`. One
`AudioEncoding` lives in `model_types.proto`, which already owns `AudioFormat` for container formats.

Same treatment for the audio shape generally. Sample rate has 18 declarations across three spellings
(`sample_rate`, `sample_rate_hz`, `mic_sample_rate_hz`) and channel count has four
(`channels`, `num_channels`, `mic_channels`). One `AudioStreamFormat { AudioEncoding encoding;
int32 sample_rate_hz; int32 channels; }` embedded everywhere replaces all of it. Note
`hybrid_router.proto:215` declares a bare `int32 audio_format` where every other file uses the enum.

### D4. One `TokenUsage` message

The input/output/total triple plus throughput is copied eight times: `LLMGenerationResult`,
`LLMStreamFinalResult`, `PerformanceMetrics`, `VLMResult`, `VLMServiceState`, `RAGResult`,
`GenerationEvent`, `PerformanceEvent`. `RAGResult` uses the OpenAI legacy names
(`prompt_tokens`/`completion_tokens`) while everything else uses input/output.

Follow the OpenAI Responses naming, which is the newer of their two: `input_tokens`,
`output_tokens`, `total_tokens`, `tokens_per_second`. Nest details if we ever need them rather than
adding sibling fields.

The same consolidation applies on the SDK side. Web and Electron already have a shared
`GenerationMetrics` (`sdk/runanywhere-electron/src/api/types.ts:254`); the other six SDKs write the
six-field block out three times each, in `GenerationResult`, `StructuredResult`, and `RagResult`.
Hoisting it removes 108 field declarations and keeps every field name intact, so nothing in the
example apps breaks.

### D5. Use `SDKError` instead of loose error strings

`error_message` appears 90 times across 22 files. `bool success` appears 24 times. Meanwhile
`errors.proto` models category, severity, code, and context properly, and is used seven times.
Worst offenders: `lora_options.proto` (14 copies), `model_types.proto` (12),
`download_service.proto` (9).

### D6. Fold diarization into STT

`SttOptions.diarization` and `SttOptions.maxSpeakers` already lower to `enable_diarization` and
`max_speakers`, so we ship two ways to ask the same question. And `DiarizationOptions` is
`VadOptions` with three renamed fields:

| concept | `VadOptions` | `DiarizationOptions` |
|---|---|---|
| score cutoff | `activationThreshold` | `threshold` |
| minimum span | `minSpeechMs` | `minimumDurationMs` |
| gap tolerance | `minSilenceMs` | `mergeGapMs` |

AssemblyAI's answer is the one to copy: speaker labels enrich the transcript instead of producing a
parallel result. That deletes `DiarizationOptions`, `DiarizationResult`, `SpeakerSegment`, and the
whole `diarization` namespace from the public surface, and reuses `Word` with a `speakerId`. Python's
implementation is already a stub that throws, so one of the eight has nothing to migrate.

The C++ primitive stays. This is a public-surface change, not an ABI change.

### D7. Delete the option fields that don't reach native

**`LoadOptions.contextLength` / `threads` / `useGpu`.** The root cause is in the IDL:
`ModelLoadRequest` (`idl/model_types.proto:620-626`) carries only `model_id`, `category`,
`framework`, `force_reload`, and `validate_availability`. There is nowhere for these three to go.
So the same three fields are currently ignored silently (Kotlin, Swift, Flutter, Python, Electron),
warned-and-ignored (RN), a hard error (Web), and partly honoured (Web `useGpu` switches WebGPU).
Delete all three, keep `framework`, and move Web's `useGpu` behaviour to `runtime.setAcceleration`
where it already lives. `LoadOptions` then has one field, so inline it as
`models.load(id, framework)` and delete the type.

**`Interruption` and `Endpointing.maxDelayMs`.** `Interruption` reaches native in zero of eight
SDKs. Only Web maps `maxDelayMs`. Kotlin drops the entire `turnHandling` block; Swift and RN map
`minDelayMs` only; Python throws before the parameter is read; and Flutter reads the wrong field
(`voice.dart:76` assigns `maxDelayMs` to `silenceDurationMs`, so silence endpointing gets 3000 ms
instead of 500 ms by default).

Replace all three types with one `silenceMs` parameter, defaulted to LiveKit's 500.

This is the one decision where I want to flag a tension. LiveKit's real `InterruptionOptions` has
eight fields with documented defaults, and it is genuinely useful. But shipping a struct that eight
SDKs ignore is worse than not shipping it. The honest sequence is: delete it now, implement barge-in
in commons, then add the struct back with LiveKit's field names once it does something.

**Fifteen more option fields commons never reads**, each with a grep that proves it:
`LLMGenerationOptions.repeat_last_n`, `.echo_prompt`, `.execution_target`,
`LLMGenerationResult.performance` and `.executed_on`, `VLMGenerationOptions.custom_chat_template`,
`DiffusionGenerationOptions.return_latents`, `STTOptions.chunk_duration_ms`, `.endpoint_silence_ms`,
`.suppress_blank`, `VADConfiguration.window_size_samples`,
`StructuredOutputOptions.strict_mode`, `LoRAAdapterConfig.target_modules`, all four
`LoggingConfiguration` fields, five `VoiceSessionConfig` fields, and
`EmbeddingsConfiguration.max_sequence_length`.

`custom_chat_template` is the interesting one. The C feature works
(`engines/llamacpp/rac_vlm_llamacpp.cpp:387`, `:750-802`), but commons' VLM proto path never
converts field 13, so the proto field is a dead end into a working feature. Either wire the
conversion or delete the field and document the template as engine-internal.

### D8. Stop re-exporting the generated proto set from Flutter

`sdk/runanywhere-flutter/packages/runanywhere/lib/runanywhere.dart:60-75` does
`export 'runanywhere_protos.dart' hide (14 names)`, which puts roughly 445 generated classes in the
public surface. Deleting one line removes 84% of Flutter's public types. The Flutter example already
imports `runanywhere_protos.dart` with a prefix where it needs protos, so the blast radius is small.

### D9. Delete Electron's pre-v3 surface

About 70 names at `sdk/runanywhere-electron/src/index.ts:140-226`, including nine `Legacy*`
duplicates of v3 types (`LegacyRagSession`, `LegacyVadOptions`, `LegacyRagConfig`, and so on). The
spec allowed one release of deprecated forwarders; these are full parallel implementations. Also
unexport the 14 `*Namespace` interfaces and the 15 `*_DEFAULTS` and `toNative*` symbols, which are
internal lowering plumbing.

### D10. Collapse the event grammar

Kotlin has 8 sealed families and 25 nested variants, so 33 nameable event types. Flutter has 30.
Python has 9 event classes plus 9 paired `*EventKind` enums. RN, Web, and Electron use discriminated
string unions with zero variant types, which is the target shape.

Structurally identical pairs are everywhere. `GenerationEvent.Token(text, kind)` and
`RagEvent.Token(text, kind)` are byte-identical. Five separate names mean "here is the result"
(`GenerationEvent.Completed`, `RagEvent.Completed`, `ImageEvent.Completed`,
`DownloadEvent.Completed`, `TranscriptionEvent.Final`). `SdkEvent.Error` and `VoiceEvent.Error` have
the same two fields. All three `VadEvent` variants carry exactly one `VadResult`, and
`VadResult.isSpeech` already encodes the transition.

Target: `Started | Delta(text, kind) | Item(T) | Completed(R)`, parameterised per stream.

On naming, adopt OpenAI's suffix grammar: `.delta` for every increment, `.done` for every terminal,
`in_progress` to `completed` or `failed` for anything async. A consumer can then handle an unknown
event correctly from the suffix alone. LiveKit covers a full duplex voice stack with 15 events;
`sdk_events.proto` is 1313 lines and 30 messages.

This is the most expensive item here because every example app's stream loop touches it. It goes
last.

### D11. Reconsider `ReasoningOptions`

We ship `ReasoningOptions{mode: ON|OFF, includeInOutput, pattern}`. Google and OpenAI both moved to
a tiered enum (`thinking_level`, `reasoning.effort`) from exactly this shape.

I am not proposing we adopt effort tiers, because on-device we cannot honour them: there is no
per-tier budget to spend. What I am proposing is that `mode: ON|OFF` and `includeInOutput` are one
concept wearing two fields, since `ON` with `includeInOutput = false` and `OFF` are nearly the same
request from the caller's point of view. Worth a decision either way rather than drift.

### D12. Delete the single-use option wrappers

`SegmentationOptions` has one boolean. `EmbedOptions` has two fields and drags two public enums
(`NormalizeMode`, `PoolingMode`) along; Web and Flutter already don't export the enums, which
suggests they aren't needed. `LoraState`, `SttState`, `ModelsState`, and `RagStats` wrap a payload
that could be returned directly.

Also `AudioFormatSpec` and `AudioEncoding` on the input side: the four `AudioInput` factories
(`pcm16`, `float32`, `wav`, `file`) already encode the format, so exposing the spec as well is
redundant. And `ImagePixelLayout` exists in Kotlin only.

Beyond that: 28 public types carry exactly one verb each. Each is a candidate for inlining into
parameters.

### D13. Fix the naming collisions

| Current | Proposed | Notes |
|---|---|---|
| `max_tokens` and `max_output_tokens` | `max_output_tokens` | `vlm_options.proto` uses both spellings in the same file (`:221`, `:267`). `embeddings_options.proto` means input truncation, so rename that one to `max_input_tokens`. |
| five `threshold` spellings | `activation_threshold` for gates, `confidence_threshold` for scores | `diarization.proto:46`, `voice_agent_service.proto:158`, `sdk_defaults.proto:191`, `vad_options.proto:352`, `hybrid_router.proto:113` |
| `top_k` meaning two things | `top_k` for sampling, `retrieval_top_k` for depth | `rag.proto:61` collides with `llm_options.proto:90`. `rag.proto:168` already uses the right name. `rerank.proto:35` uses `top_n` for the same idea. |
| three names for TTFT | `ttft_ms` | `llm_options.proto:171` vs `sdk_events.proto:395` (`first_token_latency_ms`) vs `:430` (`time_to_first_token_ms`). Two of the three are in the same message. |
| `similarity_score` | `relevance_score` | `rag.proto:203`. `rerank.proto:47` already argues for the industry-standard name. |
| `int32 framework` | `InferenceFramework framework` | `sdk_events.proto:437`, `:541`. The comment says "enum stored as int32" and there is no wire reason for it. |
| `throughput_tokens_per_sec` | `tokens_per_second` | `llm_options.proto:322` is the outlier |
| `processing_duration_ms` | `processing_time_ms` | `sdk_events.proto:547` is the outlier |

### D14. Cut the comments to 15%

4,292 comment lines against 4,974 schema lines. `segmentation.proto`, `diarization.proto`, and
`download_service.proto` sit at 14 to 15% and read perfectly well, so that is the target.

What goes:

**663 lines of pre-IDL provenance tables.** Blocks of the form "Sources pre-IDL: / Swift `X.swift:15`
/ Kotlin `X.kt:26` / Dart ... / C ABI `rac_x_types.h:63`". Of the 188 source files these blocks
cite, 78 no longer exist. Worse, protoc attaches them to the message, so an iOS developer reading
`RASTTOptions` in Xcode gets a table of deleted Kotlin line numbers.

**Every C ABI line citation, roughly 40 of them.** All checked, all wrong. `rac_stt_config_t` is at
line 119, not 76. `rac_stt_result_t` is at 222, not 191. `rac_vad_config_t` is at 103, not 63.
`rac_vlm_options_t` is at 243, not 143. Line numbers in comments cannot be kept true, so cite the
type name or nothing.

**The header essays.** `rac_options.proto` opens with 77 comment lines before 24 lines of schema,
including a paragraph on how protoc attaches comments and a reference to "Phase 4 of the Swift
simplification plan." `llm_options.proto` opens with an essay that mentions removing "~1,500 LOC of
duplicated shape definitions." `sdk_defaults.proto` carries 155 comment lines for 146 schema lines,
mostly a changelog about which of three drifted OkHttp copies won, and two of the values it argues
about turn out to be unread.

**About 250 trailing comments that restate the field name.** "PCM sample rate in Hz" on
`sample_rate`. "Whether speech was detected in this frame" on `is_speech`. "Voice id used for
synthesis" on `voice_id`.

**Internal C struct mappings.** "Mirrors `rac_vad_output_t::energy_level`" and its cousins land in
the public doc comment of every generated SDK type.

**165 lines of retired-value narrative** matching `was deleted|retired|pre-IDL|previously|formerly|
no longer|deprecated|legacy|never reuse|drifted|promoted from`. Highest density in
`structured_output.proto` (17), `diffusion_options.proto` (16), `model_types.proto` (15).

Section banners go too. "SECTION 3 STT / SECTION 4 TTS / SECTION 5 VAD" in a 1313-line file is a
sign the file should be split, not annotated.

### D15. Fix the mis-documented entries

These comments are actively wrong, so they are worse than absent. The full list is in the audit;
these are the ones that mislead about behaviour.

| Location | Claim | Reality |
|---|---|---|
| `vad_options.proto:87-91` | `frame_length_ms` floor is 1 ms (`rac_min = 1`) | Commons enforces 20 ms (`RAC_VAD_MIN_FRAME_LENGTH 0.02f`, `rac_vad_types.h:59`). A 1 ms frame passes proto validation and is rejected by commons. |
| `vad_options.proto:108-112` | `calibration_multiplier` floor is 1.5 | Commons: 1.2 (`rac_vad_types.h:65`) |
| `vad_options.proto:93-99` | activation threshold "recommended range 0.01 to 0.05", annotated 0.0 to 1.0 | Commons warns below 0.002 and above 0.1 (`vad_module.cpp:1069-1076`). Three ranges for one field. |
| `vad_options.proto:78` | sample rate floor is 1, and credits `RAC_VAD_DEFAULT_SAMPLE_RATE` as the source | The macro is generated *from this field*. And `RAC_VAD_MIN_SAMPLE_RATE` is 8000, which `sdk_defaults.proto:123` also says. |
| `vad_options.proto:258-260` | "segment counts and totals belong on a future `VADAnalytics` message and are intentionally NOT included here" | Fields 6 through 9 of that same message are `total_speech_segments`, `total_speech_duration_ms`, `average_energy`, `peak_energy`. |
| `stt_options.proto:281` | "language: Promoted to STTLanguage enum" | `:91-92`, 190 lines earlier in the same file: "STTLanguage enum deleted." |
| `rac_options.proto:47-52` | six files adopt these extensions | Eighteen do. |
| `rac_options.proto:16-25` | `rac_min`/`rac_max` are "used by `validate()`" | `validate()` is generated (17 functions in Swift alone) and called once repo-wide, at `SDKEnvironment.kt:159`. Commons hand-rolls the same checks; `vad_module.cpp:1058` says so in a comment. |
| `sdk_defaults.proto:1-19` | "every SDK reads the generated `defaults()`" | Three pool entries have no reader: `connect_timeout_ms`, `stream_chunk_bytes`, `mic_tap_buffer_frames`. The OkHttp transports still hardcode `connectTimeout`. |
| `sdk_events.proto:425-428` | metrics are on the event stream so there is "no parallel struct path" | The parallel path is `rac_telemetry_types.h` plus `telemetry_manager.cpp`, which is what actually runs. |
| `errors.proto:470` | "C ABI cap is `RAC_MAX_METADATA_STRING` (256)" | No such macro exists anywhere in commons, engines, or runtimes. |
| `errors.proto:441`, `:459` | references `rac_stack_frame_t[32]` | No such type exists. |
| `voice_agent_service.proto:35`, `:74` | `rac_voice_agent_init()`, `rac_voice_agent_result_t` | Neither exists. Line 200 of the same file correctly says `rac_voice_agent_initialize()`. |
| `sdk_init.proto:53` | values "must match `RAC_ENV_*`" | No `RAC_ENV_*` symbol exists. |

On the annotations: either wire the generated `validate()` into the SDK entry points, or change the
comment to say callers must invoke it explicitly. Right now the schema describes enforcement that
never runs.

### D16. Drop the useless-but-live entries

**Derived values stored next to their inputs.** `real_time_factor` (= `processing_time_ms` /
`audio_length_ms`, both present), `characters_per_second` (= `character_count` /
`processing_time_ms`, both present), `LLMGenerationResult.total_tokens`, `RAGResult.total_tokens`.
Each field's own comment tells the consumer they may recompute it.

**`model_id` echoed on every result.** Six or more copies. It belongs on the session or handle.

**Stream-envelope bookkeeping.** `seq`, `timestamp_us`, and `request_id` on all 12 `*StreamEvent`
messages, so 36 fields. `seq` has no consumer outside the commons emitters. `timestamp_us` is read
by exactly two Web files. Keep `request_id`.

**27 single-field messages.** `ModelGetRequest.model_id`, `ModelFormatFromUrlRequest.url`,
`LoraAdapterCatalogGetRequest.adapter_id`, and so on. Six are already dead; the rest could take a
scalar.

**`HybridCascade` is a oneof with one arm.** A union of one.

**`SdkInitEnvironment` duplicates `SDKEnvironment`.** Same two values, and both carry the identical
`reserved` pair for the same retired `STAGING` member. Merge.

### D17. Delete the reserved debris

47 `reserved` statements, and wire compatibility is a real constraint for exactly one message family.
The only persisted proto payload is `.rac-manifest.binpb`, written from a `ModelInfo`
(`model_registry_manifest.cpp:245-248`). Everything else is in-process producer to consumer inside a
single build, and there is no gRPC and no proto over the network.

So keep the reserved ranges on `ModelInfo` and its artifact subgraph. Delete the other 42, including
`llm_service.proto:38` (`reserved 2 to 13`) and `:42` (`reserved 17 to 24`), which hold 20 numbers
on a message with no wire consumer.

### D18. Merge and split files

- `hardware_profile.proto` into `device_info.proto`. Only five of its types are live; all six
  request/result envelopes are dead.
- `router.proto` into `component_types.proto`. Two single-field messages, 44 lines.
- Delete `lifecycle_service.proto`.
- `pipeline.proto`: the spec half is live via `config_loader.cpp`; the RPC envelope half is dead.
- `chat.proto`: keep `ChatMessage`, `MessageRole`, `ChatAttachment`. The rest is dead.
- `sdk_events.proto` is the hard one. `GenerationEvent` has 34 fields and `VoiceLifecycleEvent` has
  27, and both restate `LLMGenerationResult`, `TranscriptionMetadata`, and `TTSSynthesisMetadata`
  field for field. Embedding those messages instead of flattening them is worth about 450 lines and
  removes the collisions the comments currently exist to explain (`audio_size_bytes` at field 16 vs
  `audio_size_bytes_tts` at 25; `duration_ms` at 7 vs `audio_duration_ms` at 24).

### D19. Fix the ceremony in the two worst SDKs

**Android needs 30-plus lines before `initialize`.**
`examples/android/RunAnywhereAI/.../RunAnywhereApplication.kt:87-119` is per-backend
`try { LlamaCPP.register() } catch { BackendAvailability.reportRegistration(...) }` blocks followed
by a four-argument `initialize`. Kotlin also ships three `initialize` overloads
(`RunAnywhere.kt:389`, `:405`, `:424`), one taking a `Context` the spec does not have. Compare
Python, where the whole path is two statements.

**Web still needs a second phase the spec forbids.** `examples/web/RunAnywhereAI/src/main.ts:421`
calls `RunAnywhere.storage.restore()` after `initialize()`, while the facade doc at
`RunAnywhere.ts:200-201` says "There is no second phase." Fold it into `initialize()`. Also
`AudioInput` is exported both free (`index.ts:32`) and mounted on the facade
(`RunAnywhere.ts:256-262`), so there are two spellings for one constructor.

**RN uses argument bags where every other SDK uses positionals**, which is the only reason
`RagOpenOptions` and `VoiceCreateSessionOptions` exist. Switching to positionals deletes both types.

### D20. CLI

Delete the six alias subcommands (`run`, `chat`, `list`, `pull`, `rm`, `show` at `commands.h:50-51`),
which duplicate `llm.*` and `models.*`. Move `serve`, `bench`, `backends`, `info`, `auth`, and
`telemetry` under one `admin` group so the top level mirrors the namespaces exactly. That takes 23
groups plus 4 aliases down to 14 groups plus `admin`.

### D21. Replace the boolean enums with booleans

Six enums are a two-valued choice dressed as an enum, and the `UNSPECIFIED` member proto3 forces on
them is never a legal value:

| Enum | Members besides `UNSPECIFIED` | Replacement |
|---|---|---|
| `EmbeddingsNormalizeMode` (embeddings_options.proto) | `NONE`, `L2` | `bool normalize` |
| `ReasoningMode` (thinking_tag_pattern.proto) | `OFF`, `ON` | folded into D11 |
| `HybridModelType` (hybrid_router.proto) | `OFFLINE`, `ONLINE` | `bool is_local` |
| `HybridRank` (hybrid_router.proto) | `PREFER_LOCAL_FIRST`, `PREFER_ONLINE_FIRST` | `bool prefer_local` |
| `ModelQuerySortOrder` (model_types.proto) | `ASCENDING`, `DESCENDING` | `bool descending` |
| `PipelineStatus` (pipeline.proto) | `OK`, `FAILED` | already dead, delete with D1 |

`EmbeddingsNormalizeMode` is the clearest case. It costs a public enum in five SDKs, a wire enum, a
generated typealias per language, and a three-way switch in every mapper, to express one bit. Pinecone
and Google both take normalization as a boolean or not at all.

Three more enums are a genuine two-way choice but pick their values badly:
`SdkInitEnvironment` duplicates `SDKEnvironment` (see D16), `VectorStore` has two members where the
second (`PGVECTOR`) has no on-device implementation, and `ToolCallFormatName` names one model family
(`LFM2`) in a wire enum, which is the hardcoded-model-name pattern we already ban elsewhere.

Separately, `DiarizationAudioEncoding`, `VADAudioEncoding`, and `AudioEncoding` show up in this scan
too, which is D3 arriving from the other direction: three of the six two-member enums are the same
encoding enum copied three times.

### D22. Delete the C type references from comments

98 mentions of `rac_*_t` types across 19 files, concentrated in `stt_options.proto` (14),
`vad_options.proto` (13), `errors.proto` (12), `tts_options.proto` (11). They take two forms and both
go:

- "Mirrors `rac_embeddings_normalize_t`" style provenance, which tells an app developer nothing and
  is often wrong (three of the named types do not exist at all: `rac_stack_frame_t`,
  `rac_voice_agent_result_t`, `rac_tool_value_t`).
- Field-level mappings like "Mirrors `rac_vad_output_t::energy_level`", which protoc attaches to the
  generated type so a Swift or Kotlin developer reading autocomplete gets C struct member names.

The direction of dependency is backwards in these comments anyway. Several of the C types are
generated from the proto, so the proto citing them as the source is inverted.

## Bugs found along the way

These are correctness defects, not surface reduction. They should land first, since they are small
and independently verifiable.

1. **`ToolChoice.required` is a no-op on iOS.** `Options.swift:203-206` maps `.required` to `.auto`
   with a comment claiming commons has no REQUIRED mode. Commons implements and enforces it
   (`tool_calling_run_loop.cpp:160-166` rejects REQUIRED with zero tools, `:197-205` is
   `tool_choice_requires_call`, and `tool_calling_generation_internal.h:276` suppresses the
   abstention hint under REQUIRED). Kotlin maps it correctly. Fix Swift and delete the false comment.

2. **Kotlin's tool loop ignores inline tools.** `LlmNamespace.kt:80` and `:99` guard on
   `ToolCallingOrchestrator.getRegisteredTools().isNotEmpty()`, never on `opts.tools`. Passing
   `LlmOptions(tools = listOf(myTool))` without also calling `llm.tools.register` lowers the tools to
   the wire and then falls through to plain `generateUnary`, so the orchestrated loop never runs.

3. **Flutter's endpointing reads the wrong field.** `voice.dart:76` assigns
   `turns.endpointing.maxDelayMs` to `silenceDurationMs`. Default silence endpointing is therefore
   3000 ms instead of 500.

4. ~~Kotlin collapses null to zero for nine nullable fields.~~ **Not a defect. The audit was wrong.**
   None of the nine fields is `optional` in the proto; each is a plain scalar whose declared default
   is 0, and commons uses `> 0` as the has-value test everywhere: `vad_module.cpp:1211`, `:1279`,
   `:1558`, `:1645`, `rac_vad_stream.cpp:203`, and `engines/llamacpp/rac_llm_llamacpp.cpp:85` for
   `top_k`. `STTOptions.max_speakers` even documents it inline (`// 0 = auto`). So zero is the
   "use the calibrated default" sentinel, which is exactly what the Kotlin doc comment promises.
   `?: 0` is the correct lowering and Swift's `if let` reaches the same wire bytes.

5. **VLM silently drops six `LlmOptions` fields**, and the cause is the proto, not the mappers.
   `VLMGenerationOptions` (`idl/vlm_options.proto:264-303`) has no `frequency_penalty`,
   `presence_penalty`, `structured_output`, or tool-calling fields at all, so `toVlmProto`
   (`MappingOptions.kt:62-75`) and `toVLMProto` (`Options.swift:213-228`) have nowhere to put them.
   `vlm.generate(image, prompt, LlmOptions(frequencyPenalty = 0.5f))` compiles and does nothing on
   every SDK. Same class of defect as `LoadOptions` in D7: a public field with no wire home.

   Not a Phase 0 fix, because the honest options are both larger than a bug fix. Either add the four
   fields to `VLMGenerationOptions` and wire them through the commons VLM path, or narrow the VLM verb
   to take a smaller options type than `LlmOptions`. Moved to Phase 4 as a decision. Phase 0 only
   records it.

   Note `VLMGenerationOptions` also carries `n_threads`, `use_gpu`, and `max_image_size`, which no
   public option maps onto, so the mismatch runs both directions.

6. **`ImageEvent.Progress` has no producer anywhere, so it is dead surface, not a bug.**
   `rac_proto_adapters.cpp:732` converts the proto flag into
   `rac_diffusion_types.h:254 report_intermediate_images`, and the C struct even declares the payload
   fields (`intermediate_image_data`, `_size`, `_width`, `_height` at `:306-315`). No engine reads any
   of it, because there is no diffusion engine under `engines/` at all. So `reportPartials`,
   `ImageEvent.Progress`, and partial `ImageData` join the D7 list of surface with no wire home.

   Kotlin's fake stream at `ImagesNamespace.kt:47-51` (emit `Started`, then
   `Completed(generate(...))`) stays until there is something real to stream. Writing a synthetic
   progress feed would be a mock, so it is out of scope.

7. ~~Possible unit hazard in VAD frame length.~~ **Not a defect. The audit was wrong.** The
   conversion exists in both places. `rac_vad_types.h:56-58` is
   `#define RAC_VAD_DEFAULT_FRAME_LENGTH (RAC_DEFAULT_VAD_CONFIGURATION_FRAME_LENGTH_MS / 1000.0f)`,
   with a comment stating "Seconds here, milliseconds in the proto, so this converts rather than
   aliases", and `vad_module.cpp:1207-1208` does `frame_length_ms() / 1000.0f` on the runtime path.

   One real leftover from this cluster: `vad_options.proto:87-91` annotates `rac_min = 1` on
   `frame_length_ms` while `RAC_VAD_MIN_FRAME_LENGTH` is 0.02 seconds, and the runtime check at
   `vad_module.cpp:571` tests `<= 0.0f || > 1.0f` rather than the 20 ms floor, so the declared
   minimum, the C constant, and the enforced check are three different bounds. Annotation fix, so it
   belongs in Phase 2 with D15.

### Phase 0 outcome

Three real bugs, fixed. Two audit misdiagnoses, corrected above. Two missing capabilities moved to
later phases. The lesson for the remaining phases: the audits are leads, not verdicts, and each
deletion claim gets checked against commons before the edit lands.

## Phasing

Ordered so each phase is independently shippable and the risky work comes after the cheap wins.

**Phase 0. The seven bugs above.** Small, verifiable, no surface change. Regenerate where the proto
is touched.

**Phase 1. Pure deletion, no renames.** D1, D2, D8, D9, D17. Dead types, service blocks, Flutter's
proto re-export, Electron's legacy block, reserved debris. Nothing that survives changes shape, so
regeneration should be mechanical and no example app should need an edit. Expect roughly 1,100 proto
lines and about 500 public types gone.

**Phase 2. Comments.** D14, D15. Comment-only, so generated code changes but no behaviour does. Fix
the four wrong annotation bounds while in there (`rac_min` on frame length and sample rate, the two
multiplier floors). About 1,000 lines.

**Phase 3. Consolidation.** D3, D4, D5, D16, D18. Audio format, `TokenUsage`, `SDKError`, derived
fields, file merges. This one moves field numbers, so it needs the manifest compatibility check from
D17 applied carefully: `ModelInfo` and its artifact subgraph are the only messages where a number
must not move.

**Phase 4. Public surface.** D6, D7, D12, D13, D19, D20. Diarization into STT, dead option fields
out, wrapper types inlined, naming fixed, ceremony cut, CLI flattened. Every SDK and every example
app is touched. This is where the 48-type floor gets hit.

**Phase 5. Events.** D10. Last, because every stream loop in every example app changes.

D11 is a decision, not a phase. It slots into Phase 4 if we take it.

## Open questions

1. **`ReasoningOptions`.** Collapse `mode` and `includeInOutput`, or leave it? See D11.

2. **`Interruption`.** Delete now and re-add after commons implements barge-in, or keep the struct
   and accept that it does nothing? See D7.

3. **Deprecation shims.** Still unresolved from the last round: 93 Swift `@available(*, deprecated)`
   declarations plus Web's `Deprecated.ts` fail `check_deprecated_surfaces.sh`, whose allowlist
   header says exceptions do not authorize deprecated declarations. This plan makes it worse by
   deleting more. My read is that pre-1.0 with nothing shipped, we delete rather than deprecate.
   Kotlin's `ModelBootstrap` and `LoraViewModel` reach LoRA catalog verbs through the deprecated
   path and need real replacements first.

4. **`chat.proto`'s future.** `ChatGenerationRequest` is live only from
   `examples/android/.../ChatViewModel.kt` and `ChatGenerationOwnership.kt`. Is the `Chat` service
   concept intended, or an abandoned parallel to `LLMGenerateRequest`? Product call.

5. **`pipeline.proto` and `solutions.proto`.** `PipelineSpec` and friends are live via
   `config_loader.cpp`, but they are consumed as YAML config shapes rather than as protos. Are the
   proto definitions load bearing, or documentation for the YAML schema?

6. **`hybrid_router.proto`.** Sixteen of seventeen types are live, but only seven reach commons. The
   other nine may be TypeScript-only routing policy that belongs in the Web SDK rather than shared
   IDL. Note `HybridQualityFilter` is documented as a no-op at `hybrid_routing_policy.dart:43`.

7. **`logging.proto`.** None of its three types reach commons, even though commons owns `RAC_LOG_*`.
   Wire it, or mark the proto SDK-local?

## Verification per phase

Same gates as the v3 round, all of which passed there: commons 134/134 ctest; Kotlin compile plus
ktlint plus detekt plus 94/94; Flutter `dart analyze` on five packages plus 68/68; RN `tsc` clean
plus 50/50; Web typecheck, build, and lint; Python 577 passed; Electron build plus 390/390 plus the
demo self-test; CLI build plus 3/3 plus a live TTS to STT to VAD round trip. Swift is static-only
here, since there is no Xcode on this machine.

Plus, for every phase: `idl-drift-check` must be clean, and `check_no_hardcoded_defaults.sh` and
`check_deprecated_surfaces.sh` must pass.

## Audit coverage gaps

Declared so nobody treats the lists as exhaustive.

- 33 `map<>` fields were not parsed by the field census. A follow-up pass should scan them.
- Enum members other than `*_UNSPECIFIED` were not individually reference-checked. Since 13
  `*EventKind` enums turned out to be dead wholesale, the survivors likely contain dead members;
  `GenerationEventKind` has 25 members and none were individually verified.
- 55 unreferenced `*_UNSPECIFIED` members are listed for awareness only. Proto3 requires a zero
  value, so they stay.
