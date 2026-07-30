# Public API shaping (task 22)

Reshape the developer-facing surface of all 8 SDKs against industry references: OpenAI (Responses, audio, embeddings, images), LiveKit Agents (voice pipeline), Cohere (rerank), Cactus Compute (on-device competitor). The v2 IDL contract already fixed field names; this plan fixes the verbs, namespaces, stream contracts, session model, and defaults that developers actually touch.

Kotlin is the source SDK for this work. The shape lands in `sdk/runanywhere-kotlin` first; the other seven mirror it. Business-logic behavior still defers to commons.

Inputs: industry-standards research, Cactus Kotlin research, and the full current-state inventory (123 flat Swift members, 10 verbs for "run inference", 5 stream shapes, 4 session models, 5 temperature defaults). All three reports are in the task-22 session records; the inventory's per-modality pain lists are the checklist for this plan.

## Design principles

1. Two or three required params per call (payload, sometimes model); everything else defaulted in one options object per modality. Unsupported combinations raise an error instead of silently doing nothing.
2. One stream contract everywhere: the factory throws on preflight failure, the stream throws (Kotlin: `Flow` that throws into the collector) on in-flight failure. No errors smuggled through `text` fields, no silent `finish()`.
3. One session model per lifetime class: one-shot calls are stateless verbs on a namespace; long-lived pipelines (voice, RAG) are session objects you create, use, and close. No hidden global singletons that a second caller can clobber.
4. Typed results with ids and metrics. Every result carries `requestId`; generation results carry `inputTokens`, `outputTokens`, `timeToFirstTokenMs`, `tokensPerSecond` (the Cactus habit worth copying).
5. Internals stay internal: no proto `has*` flags, raw handles, filesystem paths, `nThreads`, or engine names on per-request options. Placement knobs move to load/config time.
6. Names follow the host language casing over one wire vocabulary. A verb means the same thing in all 8 SDKs.

## Decisions

### D1. Namespaced facade

`RunAnywhere` keeps only lifecycle and identity (`initialize`, `reset`, `isReady`, `environment`, `deviceId`, `events`). Everything else moves under per-modality namespaces:

```
RunAnywhere.llm          RunAnywhere.stt         RunAnywhere.tts
RunAnywhere.vad          RunAnywhere.vlm         RunAnywhere.embeddings
RunAnywhere.rerank       RunAnywhere.images      RunAnywhere.diarization
RunAnywhere.segmentation RunAnywhere.voice       RunAnywhere.rag
RunAnywhere.models       RunAnywhere.lora
```

This kills the `rag*` prefix family, the Flutter/Web double-name problem (namespace only, no flat aliases), and Kotlin's import-to-discover problem (namespaces are properties on the object, so autocomplete works). Tool calling and structured output live inside `llm` (per the standup: "tool calling should be part of LLM").

### D2. Verb grammar

One table, applied everywhere. Streaming is the same verb with a `Stream` suffix, always suffix, never prefix.

| namespace | one-shot | stream | notes |
|---|---|---|---|
| llm | `generate(prompt|messages, options)` | `generateStream(...)` | `messages: List<ChatMessage>` is a first-class overload; history stops being unreachable |
| llm | `generateStructured(prompt, schema, options)` | `generateStructuredStream(...)` | the only structured-output verbs; `extract`/`generateWith*` become internal |
| llm.tools | `register`, `unregister`, `list`, `clear`, `execute` | | tool loop runs via `generate` with `options.tools` / `options.toolChoice`, OpenAI-style; `generateWithTools`' 8 params collapse into options |
| vlm | `generate(image(s), prompt, options)` | `generateStream(...)` | replaces `processImage`/`caption`; prompt leaves the options struct |
| stt | `transcribe(audio, options)` | `transcribeStream(audioFlow, options)` | audio is one typed `AudioInput` (bytes + declared format), same union in every SDK |
| tts | `synthesize(text, options)` | `synthesizeStream(...)` | `speak`/`stopSpeaking` move to a small `tts.player` helper so synthesis and playback stop sharing a stop-verb pair |
| vad | `detect(audio, options)` | `detectStream(audioFlow, options)` | replaces `detectVoiceActivity`/`streamVAD`/`process` |
| embeddings | `embed(texts, options)` | | batch-in, ordered batch-out with `index`, OpenAI shape; model comes from load, not per call |
| rerank | `rerank(query, documents, topN)` | | `documents: List<String>`, result `{index, relevanceScore}`, Cohere shape |
| images | `generate(prompt, options)` | `generateStream(...)` | replaces `generateImage`; `inpaint` becomes `options.mode` on every SDK |
| diarization | `diarize(audio, options)` | `diarizeStream(...)` | |
| segmentation | `segment(image, options)` | | gains the ergonomic overload it never had |
| rag | session verbs, see D4 | | |
| voice | session, see D5 | | |

Cancellation: every `*Stream` call returns a stream whose cancellation (Kotlin: collector cancellation) cancels the native request, request-scoped. The global `cancelGeneration`-style verbs survive one release as deprecated shims.

### D3. One options object per modality, one defaults table

Options structs stay proto-backed but are re-exported through thin Kotlin data-class wrappers with named defaults, so `hasX`, `Int32`, and reserved-field artifacts stop being the public surface. Sampling defaults unify to a single table in the IDL (`temperature 0.7`, `topP 1.0`, `maxOutputTokens 512` unless a modality has a documented reason to differ) and `rac_default` annotations get filled in for diffusion, rerank, segmentation, tool_calling, and lora so the generated defaults stop leaving zeros on the wire. `nThreads`, `useGpu`, `preferredFramework`, and `executionTarget` move off per-request options onto load requests.

### D4. RAG becomes a session object

```kotlin
val rag = RunAnywhere.rag.open(embeddingModel = "minilm", llmModel = "qwen3-0.6", config = RagConfig())
rag.ingest(document); rag.ingest(documents)
rag.search(query, topK, filters)          // retrieval only, no generation
rag.query(question, options)              // retrieval + generation
rag.queryStream(question, options)
rag.stats(); rag.clear(); rag.close()
```

Fifteen flat verbs collapse to a handle with eight members. `search` is new surface but matches the industry split (store / search / generation-integrated retrieval) and commons already implements retrieval internally. Concurrent sessions become possible instead of a hidden singleton.

### D5. Voice pipeline gets the LiveKit shape

The 5-step ritual (`loadModel` x3 + `ensureDefaultVAD` + `initializeVoiceAgentWithLoadedModels`) is replaced by one constructor that owns its prerequisites, because the SDK, not the app, does the heavy lifting:

```kotlin
val session = RunAnywhere.voice.createSession(
    stt = "whisper-tiny", llm = "qwen3-0.6", tts = "piper-en",
    vad = VadConfig(),                       // default Silero, auto-ensured
    turnHandling = TurnHandlingOptions(),    // endpointing, interruption knobs
    generation = LlmOptions(),
)
session.events                               // Flow<VoiceEvent>: userTranscribed, agentStateChanged, error(recoverable)
session.start(); session.say(text); session.interrupt(); session.close()
```

Model ids auto-download/load if missing (the Cactus lazy-load trick, gated by a `downloadIfNeeded = true` param). Mic ownership is explicit: `session.start()` starts capture, nothing starts a microphone as a side effect of iterating a stream. `ttsVoiceID` confusion resolves into `tts = ModelRef(model, voice)`.

### D6. Model management: one vocabulary, lazy by default

`RunAnywhere.models` keeps `register`, `download`, `downloadStream`, `list`, `get`, `delete`, `load`, `unload`, `state`. Every generation verb accepts an optional `model` slug and auto-loads (download included when `downloadIfNeeded`) when that model is not resident, so quickstart is two calls: `initialize()` then `llm.generate(...)`. `loadModel` starts throwing like everything else; result-object-that-never-throws goes away. LoRA's 11 catalog verbs shrink to `lora.apply/remove/list/state` plus `models.register(loraAdapter(...))`, removing the parallel registry.

### D7. Parity floor

Every SDK ships the same core: llm (incl. tools + structured), vlm, stt, tts, vad, embeddings, models, voice session, rag. Rerank, diarization, segmentation, lora, images ship where the runtime supports them but with identical shapes. Python/Electron's handle-based inversion is rewritten onto the shared shape; hybrid STT graduates from a JS-only extra to a documented capability or is dropped from the public surface.

## What does not change

The C ABI, the proto contract, and commons behavior. This is a facade-layer reshape; commons changes are limited to filling `rac_default` annotations, the unified defaults table, and a retrieval-only RAG query entry if `search` needs one. No engine, registry, or transport work.

## Phases

1. **Contract prep (commons/IDL, small):** defaults table + missing `rac_default` annotations, `AudioInput` envelope reuse, retrieval-only RAG verb. Regen bindings.
2. **Kotlin facade v3 (source):** namespaces, verb table, stream contract, RAG/voice sessions, deprecation shims for every old verb. Gate: compile + ktlint + example app migrated + on-device smoke.
3. **Swift, then Flutter/RN/Web (wave):** mirror Kotlin one-to-one; example apps migrated per SDK.
4. **Python/Electron:** rewrite onto the shared shape (their surfaces are smallest and least adopted, so they absorb the biggest change last).
5. **Docs:** regenerate `thoughts/shared/api/*.md` from the new surface; quickstarts show two-call first-token.

Old verbs stay as deprecated shims for one release, then get deleted. Pre-1.0, so shims are a courtesy for our own example apps more than for users.

## Open questions for review

1. `generate` vs `create` for the LLM verb. This plan keeps `generate` (matches on-device peers and our history); OpenAI uses `create`.
2. Should `tts.player` (playback) exist in the SDK at all, or move to example apps? iOS/Android both currently ship playback.
3. Deprecation shims: keep for one release as written, or break clean now since nothing has shipped?
4. Hybrid STT: promote to the parity floor or park it?
