# Phase D Close-out Report — Web `VoiceAgent` stub deletion

_v2 close-out (v0.20.0) / Phase D — execution summary._

Related docs:
- Plan: [`docs/release/v0_20_0_release_plan.md`](release/v0_20_0_release_plan.md) § 4
- Impact audit (D-1): [`docs/web_voiceagent_deletion_impact.md`](web_voiceagent_deletion_impact.md)
- Web SDK docs (D-4): [`docs/sdks/web-sdk.md`](sdks/web-sdk.md)
- Cross-SDK migration: [`docs/migrations/VoiceSessionEvent.md`](migrations/VoiceSessionEvent.md)

## Summary

Phase D deleted the vapor `VoiceAgent` / `VoiceAgentSession` stub class
from the Web SDK, unified the voice surface on two real paths, and
wrote the missing `docs/sdks/web-sdk.md`. The Web SDK core now compiles
and builds green, the Web sample builds green, and `grep` confirms no
references to the deleted symbols remain in the public-facing
extensions directory.

## Files deleted

| Path                                                                                                   | Reason                                                                                         |
| ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| `sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts`                    | Every method was a `throw SDKError.componentNotReady('VoiceAgent', …)` stub. Pure vapor.       |

The stub types `VoiceAgentModels`, `VoiceTurnResult`, `VoiceAgentEventData`,
`VoiceAgentEventCallback` (previously exported through `VoiceAgentTypes.ts`)
have also been removed from the type bundle — no consumer depended on
them. Only `PipelineState` is retained in `VoiceAgentTypes.ts` because
`VoicePipelineTypes.ts` re-exports it.

## Files modified

| Path                                                                                                   | Change                                                                                                                                           |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `sdk/runanywhere-web/packages/core/src/index.ts`                                                       | Dropped `VoiceAgent` / `VoiceAgentSession` / stub-type re-exports. Added `VoiceAgentStreamAdapter`, `VoiceAgentStreamTransport`, `VoiceEvent` (and payload types), proto enums, `setRunanywhereModule`, `EmscriptenRunanywhereModule`. |
| `sdk/runanywhere-web/packages/core/src/Adapters/VoiceAgentStreamAdapter.ts`                            | Fixed broken `VoiceEvent` import (was from `voice_agent_service`, now from `voice_events`). Extended constructor to accept either a `handle: number` (WASM path) or a `VoiceAgentStreamTransport` (pluggable / test path). |
| `sdk/runanywhere-web/packages/core/src/generated/streams/voice_agent_service_stream.ts`                | Fixed the same broken `VoiceEvent` import that blocked `yarn tsc --noEmit`.                                                                      |
| `sdk/runanywhere-web/packages/core/src/Public/Extensions/VoiceAgentTypes.ts`                           | Trimmed to just `PipelineState` (the only surviving consumer is `VoicePipelineTypes`).                                                           |
| `sdk/runanywhere-web/packages/core/README.md`, `sdk/runanywhere-web/README.md`                         | Removed `RunAnywhere+VoiceAgent.ts` from package-tree listings. Updated the "exports" row for voice to describe `VoicePipeline` + `VoiceAgentStreamAdapter`. |
| `examples/web/RunAnywhereAI/src/views/voice.ts`                                                        | Full rewrite of the Voice tab (see diff summary below).                                                                                          |

## Files created

| Path                                                                                                   | Purpose                                                                                                  |
| ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `docs/web_voiceagent_deletion_impact.md`                                                               | D-1 deliverable: per-member mapping table for `VoiceAgent` / `VoiceAgentSession`.                        |
| `docs/sdks/web-sdk.md`                                                                                 | D-4 deliverable: B32 doc that was previously missing. Mirrors the shape of `kotlin-sdk.md` / `flutter-sdk.md` / `react-native-sdk.md`. |
| `docs/v2_closeout_phase_d_report.md`                                                                   | This report.                                                                                             |

## Sample-app migration diff summary

`examples/web/RunAnywhereAI/src/views/voice.ts` (~445 LOC changed):

- **Before** — imports `VoicePipeline` + `PipelineState` from the Web
  SDK and drives the Voice tab via `pipeline.processTurn(audio, opts,
  callbacks)` with imperative UI updates inside `onTranscription`,
  `onResponseToken`, `onResponseComplete`, `onSynthesisComplete`,
  `onStateChange`, and `onError`.

- **After** — imports `VoicePipeline`, `VoiceAgentStreamAdapter`, proto
  `VoiceEvent`, `VADEventType`, plus the app-level `PipelineState`. A
  new in-file `createPipelineTransport(pipeline, opts)` factory returns:
  - a `VoiceAgentStreamTransport` that emits proto `VoiceEvent`s from
    `VoicePipeline` callbacks,
  - a `feedTurn(audio)` thunk that triggers a turn,
  - a `cancel()` thunk that cancels in-flight LLM generation.

  The Voice tab then does **literally** `new
  VoiceAgentStreamAdapter(pipelineTransport).stream()` and consumes the
  `AsyncIterable<VoiceEvent>` via `for await (const event of
  adapter.stream())`, switching on `event.userSaid`, `event.assistantToken`,
  `event.state`, `event.audio`, `event.vad`, `event.error` — the same
  shape the iOS / Android / Flutter / RN samples consume off their own
  `VoiceAgentStreamAdapter`.

  UI state machine (listening → processing → speaking → idle) is
  preserved, but transitions are now driven by `VoiceEvent` cases:
  - `event.state.current === PROTO_STATE_THINKING` → "Thinking…"
  - `event.state.current === PROTO_STATE_SPEAKING` → "Speaking…"
  - `event.userSaid.text` renders the user's transcript
  - `event.assistantToken.text` appends to the streaming UI buffer
  - `event.audio.pcm` is played via `AudioPlayback`, then the session
    resumes listening
  - `event.vad.type === VAD_EVENT_VOICE_END_OF_UTTERANCE` flips status to "Transcribing…"
  - `event.error.message` surfaces in the status bar

Subscription is opened via `openEventStream()` on session start and
torn down via `closeEventStream()` (iterator `return()` call) on session
stop. `VoicePipeline` stays untouched as the runtime engine because the
Web WASM voice-agent bindings are not yet landed; once they are, the
sample swaps one line (`new VoiceAgentStreamAdapter(handle)`) and
deletes `createPipelineTransport`.

## New `docs/sdks/web-sdk.md` outline

1. Title / intro (pure-TS core, backends ship WASM).
2. Installation — `npm install @runanywhere/core @runanywhere/web-llamacpp @runanywhere/web-onnx`. Peer deps. Bundler notes.
3. Platform requirements — browser matrix, SharedArrayBuffer, OPFS.
4. Quick Start — initialize, register backends, register + download + load a model, `RunAnywhere.chat('Hello!')`.
5. Architecture — package structure, ExtensionPoint-based backend registration.
6. **Voice — two paths** (the core of the doc):
   - Path 1: `VoicePipeline` (TS composition).
   - Path 2: `VoiceAgentStreamAdapter` (proto `VoiceEvent` stream — cross-SDK parity). Covers both the WASM handle constructor and the custom transport constructor. Notes that the v0.20.0 release deleted the stub `VoiceAgent` class and links to both the release plan and the deletion impact audit.
7. Voice turn example using `VoiceAgentStreamAdapter` — full snippet mirroring the sample.
8. LLM / STT / TTS / VAD at a glance — short sections with minimal code.
9. Links — impact audit, migration guide, release plan, other SDK docs, `idl/voice_events.proto`.

## Final verification outputs

```
=== 1. yarn tsc --noEmit (Web SDK core) ===
$ /.../tsc --noEmit
Done in 0.75s.
(exit 0)

=== 2. yarn build (Web SDK core) ===
$ tsc
Done in 0.88s.
(exit 0)

=== 3. Web sample build (examples/web/RunAnywhereAI, vite build) ===
✓ 108 modules transformed.
dist/index.html                           0.76 kB │ gzip:  0.47 kB
…
dist/assets/index-BFMdYkRV.js           276.02 kB │ gzip: 73.67 kB
✓ built in 325ms
Done in 0.63s.
(exit 0)

=== 4. grep -rn "VoiceAgent\b\|VoiceAgentSession" sdk/runanywhere-web/packages/core/src/Public/Extensions/ ===
(no output — grep returns 1, as required)

=== Orphan-reference sweep (sdk/runanywhere-web + examples/web) ===
grep VoiceAgentSession / RunAnywhere+VoiceAgent / VoiceAgentModels / VoiceAgentEventData / VoiceAgentEventCallback / VoiceTurnResult
(no output in source, comments, or docs under those trees outside node_modules/dist)
```

## Guardrails observed

- **No `@deprecated` annotations added.** The stub was DELETED, not deprecated. Any pre-existing `@deprecated` comments were on a separate type (`VoiceAgentEventData`) that is now also deleted wholesale.
- **No stub shims.** The new `VoiceAgentStreamAdapter` accepting a custom transport is a real generalisation (used by the sample today, by the WASM path once bindings land) — it is not a shim for the deleted class.
- **No barrel exports left dangling.** `src/index.ts` was audited and rewritten; `dist/` was rebuilt and contains no stale `RunAnywhere+VoiceAgent.*` artifacts.
- **Every boundary compiled.** `yarn tsc --noEmit`, `yarn build`, and `vite build` all pass.

## Follow-ups that are intentionally out of scope

- Wiring a backend package (e.g. `@runanywhere/web-llamacpp`) to call `setRunanywhereModule(mod)` and surface a voice-agent-handle factory. This is the last thing needed before the Web sample can drop `createPipelineTransport` and swap in `new VoiceAgentStreamAdapter(handle)` at runtime. Tracked as part of the Web `VoiceAgent` backend wiring work called out in the v0.20 release plan preamble.
- Turning the handle-factory work into `@runanywhere/web-llamacpp`'s public API (`LlamaCPP.voiceAgent.create(…)`) so apps don't have to touch `runanywhereModule` directly.

_End of report._
