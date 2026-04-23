# Web SDK `VoiceAgent` Stub Deletion Impact

_Phase D-1 audit deliverable for v2 close-out. Produced by grepping the
Web SDK source (`sdk/runanywhere-web/packages/core/src/`) and the Web
sample (`examples/web/RunAnywhereAI/`) for every consumer of the stub
`VoiceAgent` / `VoiceAgentSession` API._

## TL;DR

The `VoiceAgent` class in
[`src/Public/Extensions/RunAnywhere+VoiceAgent.ts`](../sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts)
was pure vapor from the day it was checked in: every method threw
`SDKError.componentNotReady('VoiceAgent', 'No WASM backend registered …')`.
No production code paths depended on its runtime behaviour; all three
surviving callers (Web SDK `index.ts` re-exports, the Web sample's README
mention, the `VoiceAgentTypes` `@deprecated` comment) point to the
replacement paths already in the tree.

Two real voice paths exist and stay:

1. **`VoicePipeline`** (`src/Public/Extensions/RunAnywhere+VoicePipeline.ts`)
   — TS-side STT → LLM → TTS orchestration via `ExtensionPoint`
   provider lookups. The "compose-your-own" path for apps that wire
   their own providers.
2. **`VoiceAgentStreamAdapter`** (`src/Adapters/VoiceAgentStreamAdapter.ts`)
   — wraps a C++-side `VoiceEvent` proto stream as an
   `AsyncIterable<VoiceEvent>`. The cross-SDK path shared with iOS,
   Android, Flutter, and React Native (see
   [`docs/migrations/VoiceSessionEvent.md`](migrations/VoiceSessionEvent.md)
   and
   [`docs/release/v0_20_0_release_plan.md`](release/v0_20_0_release_plan.md)).

## Method-by-method replacement matrix

### `VoiceAgentSession` (the returned session object)

| Stub member                                  | Behaviour in stub                           | Replacement                                                                                                                                      |
| -------------------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `new VoiceAgentSession(handle)` (ctor)       | Stored `handle: number`, never used         | No replacement needed — was always vapor                                                                                                         |
| `loadModels(models: VoiceAgentModels)`       | `throw componentNotReady('VoiceAgent', …)`  | Load each model individually via the backend package (`LlamaCPP.registerModel` / `ONNX.registerModel` + `await RunAnywhere.loadModel(modelId)`) |
| `processVoiceTurn(audioData)`                | `throw componentNotReady(…)`                | `VoicePipeline.processTurn(audioData, options, callbacks)` (TS path) OR feed audio to a `VoiceAgentStreamAdapter` (WASM path)                   |
| `get isReady`                                | Always returns `false`                      | `ExtensionPoint.hasProvider('llm' / 'stt' / 'tts')` — the `VoicePipeline` readiness is the AND of all three                                      |
| `transcribe(audioData)`                      | `throw componentNotReady(…)`                | `ExtensionPoint.requireProvider('stt', …).transcribe(audioData, …)` — exposed through the ONNX backend package's public API                     |
| `generateResponse(prompt)`                   | `throw componentNotReady(…)`                | `ExtensionPoint.requireProvider('llm', …).generate(prompt, …)` — exposed through `RunAnywhere.chat(…)` / `RunAnywhere.generate(…)`              |
| `get handle: number`                         | Returns stored handle (always 0 in stub)    | On Web, `VoiceAgentStreamAdapter(handle)` takes the WASM-side handle directly; no mirror-object indirection                                     |
| `destroy()`                                  | Zeroes `this._handle`, does nothing real    | For `VoicePipeline`: `pipeline.cancel()`. For `VoiceAgentStreamAdapter`: `break` out of the `for await` to trigger `AsyncIterator.return()`     |

### `VoiceAgent` namespace (the factory export)

| Stub member                                  | Behaviour in stub                              | Replacement                                                                                                                                     |
| -------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `VoiceAgent.create(): Promise<Session>`      | `throw componentNotReady('VoiceAgent', …)`    | `new VoicePipeline()` (TS path) OR `new VoiceAgentStreamAdapter(handle)` (WASM path — once the backend package exposes a `create` thunk)        |

### Types exported from `RunAnywhere+VoiceAgent.ts` (re-exports of `VoiceAgentTypes.ts`)

| Re-export                | Keep? | Replacement / action                                                                                                             |
| ------------------------ | ----- | -------------------------------------------------------------------------------------------------------------------------------- |
| `PipelineState`          | Keep  | Moved to be re-exported from `RunAnywhere+VoicePipeline.ts` (`VoicePipelineTypes` already imports it). Still lives in `VoiceAgentTypes.ts`.   |
| `VoiceAgentModels`       | Drop  | Ad-hoc type for the stub `loadModels(...)` call. No other consumer.                                                              |
| `VoiceTurnResult`        | Drop  | Ad-hoc type for the stub `processVoiceTurn(...)` return. Use `VoicePipelineTurnResult` (real) or `VoiceEvent` (proto stream).    |
| `VoiceAgentEventData`    | Drop  | Already marked `@deprecated` — replaced by proto `VoiceEvent` (see `docs/migrations/VoiceSessionEvent.md`).                     |
| `VoiceAgentEventCallback`| Drop  | Tied to `VoiceAgentEventData`. Gone with it.                                                                                    |

## Consumers of the deleted class

### Web SDK source — `sdk/runanywhere-web/packages/core/src/`

| File                                           | Line(s) | Action                                                                           |
| ---------------------------------------------- | ------- | -------------------------------------------------------------------------------- |
| `Public/Extensions/RunAnywhere+VoiceAgent.ts`  | whole   | **DELETE FILE**                                                                  |
| `index.ts`                                     | 27–28   | DELETE the `VoiceAgent`/`VoiceAgentSession`/`VoiceAgentModels`/... re-exports    |
| `Public/Extensions/VoiceAgentTypes.ts`         | 13–52   | Trim to only `PipelineState` (still used by `VoicePipelineTypes`)               |

### Web SDK documentation / READMEs

| File                                                        | Line | Action                                                                        |
| ----------------------------------------------------------- | ---- | ----------------------------------------------------------------------------- |
| `sdk/runanywhere-web/packages/core/README.md`               | 345  | Remove `RunAnywhere+VoiceAgent.ts` from the directory tree listing            |
| `sdk/runanywhere-web/README.md`                             | 379  | Same — package tree                                                            |
| `sdk/runanywhere-web/README.md`                             | 735  | Remove the "VoiceAgent: Complete voice agent with C API pipeline" row         |

### Web sample — `examples/web/RunAnywhereAI/src/`

The Web sample **never imported the stub class**, only `VoicePipeline`.
No delete-cascade needed. Phase D-2 migrates it onto the `VoiceEvent`
proto-stream code path (the `VoiceAgentStreamAdapter` shape) so the
sample matches iOS / Android / Flutter / RN even though the runtime
engine is still TS-side `VoicePipeline` until the Web WASM voice-agent
bindings land.

| File                                              | Reference                    | Action                                                                |
| ------------------------------------------------- | ---------------------------- | --------------------------------------------------------------------- |
| `examples/web/RunAnywhereAI/src/views/voice.ts`   | `import { VoicePipeline, …}` | Rewrite to consume a `VoiceAgentStreamAdapter.stream()` async iterable |

## Broken-state notes caught during audit

- `src/generated/streams/voice_agent_service_stream.ts` imports
  `VoiceEvent` from `../voice_agent_service` but `VoiceEvent` actually
  lives in `../voice_events`. This already breaks `yarn tsc --noEmit`
  on the core package and must be fixed as part of D-2 for the phase
  to finish green.
- `src/Adapters/VoiceAgentStreamAdapter.ts` has the same broken import.
- `VoiceAgentStreamAdapter` is not exported from `src/index.ts` — every
  other SDK exports the equivalent type from its top-level barrel (see
  `sdk/runanywhere-react-native/packages/core/src/index.ts:224-225`).
  D-2 fixes this.

## Replacement-path readiness

| Path                                       | Today                                              | After D-2                                                                                      |
| ------------------------------------------ | -------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `VoicePipeline` (TS composition)           | Green. Sample uses it.                             | Still green. Sample drives it through a `VoiceAgentStreamAdapter` transport (pipeline-backed). |
| `VoiceAgentStreamAdapter` (WASM proto)     | Compiles after D-2 import fix; runtime needs WASM init. | Accepts either a `handle: number` (WASM path) or a custom `VoiceAgentStreamTransport` (pipeline/test path). Shipped in `index.ts`. |

_End of audit._
