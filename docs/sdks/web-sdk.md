# RunAnywhere Web SDK

Pure-TypeScript SDK for on-device AI inference in the browser. The core
package is 100% TypeScript (no WASM); inference binaries ship with the
backend packages (`@runanywhere/web-llamacpp` for LLM / VLM /
embeddings / diffusion, `@runanywhere/web-onnx` for STT / TTS / VAD).

## Installation

```bash
# Core SDK (required)
npm install @runanywhere/core

# Backend modules (pick what you need)
npm install @runanywhere/web-llamacpp    # LLM text generation (GGUF via llama.cpp WASM)
npm install @runanywhere/web-onnx        # STT, TTS, VAD (Sherpa ONNX WASM)
```

### Peer dependencies

The core has two runtime deps:

```bash
npm install long protobufjs
```

Bundler requirements: a modern build tool that understands `new URL(..., import.meta.url)` for WASM asset resolution (Vite, webpack 5, esbuild, Parcel 2). The sample in `examples/web/RunAnywhereAI/` uses Vite.

## Platform Requirements

| Platform         | Requirement             |
| ---------------- | ----------------------- |
| Browser          | Chrome / Edge 113+, Firefox 127+, Safari 17+ |
| Node (tooling)   | 18+                     |
| Emscripten heap  | SharedArrayBuffer with COOP/COEP (for threading) or single-threaded fallback |
| Storage         | OPFS (Origin Private File System) for model cache |

## Quick Start

```typescript
import { RunAnywhere } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/web-llamacpp';
import { ONNX } from '@runanywhere/web-onnx';

// 1. Initialize SDK.
await RunAnywhere.initialize({ environment: 'development' });

// 2. Register backends. Each backend loads its own WASM lazily.
await LlamaCPP.register();
await ONNX.register();

// 3. Register a model (ONNX Whisper, llama.cpp GGUF, …).
await RunAnywhere.registerModel({
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  framework: 'llamacpp',
  memoryRequirement: 500_000_000,
});

// 4. Download + load.
await RunAnywhere.downloadModel('smollm2-360m-q8_0', (p) => {
  console.log(`${Math.round(p.progress * 100)}%`);
});
await RunAnywhere.loadModel('smollm2-360m-q8_0');

// 5. Generate.
const response = await RunAnywhere.chat('Hello!');
console.log(response);
```

## Architecture

### Package structure

```
sdk/runanywhere-web/
├── packages/
│   ├── core/                   # @runanywhere/core — pure TS
│   │   └── src/
│   │       ├── Public/         # RunAnywhere class + extensions (e.g. VoicePipeline)
│   │       ├── Adapters/       # VoiceAgentStreamAdapter (proto VoiceEvent stream)
│   │       ├── Foundation/     # ErrorTypes, Logger, EventBus, AsyncQueue
│   │       ├── Infrastructure/ # ExtensionPoint, ModelManager, OPFSStorage, AudioCapture/Playback
│   │       ├── Features/       # LLM helpers (LlmThinking)
│   │       ├── generated/      # ts-proto codegen from idl/ (VoiceEvent, streams)
│   │       ├── runtime/        # EmscriptenModule typed surface
│   │       └── services/       # HTTPService, AnalyticsEmitter
│   ├── llamacpp/               # @runanywhere/web-llamacpp (ships racommons-llamacpp.wasm)
│   └── onnx/                   # @runanywhere/web-onnx (ships sherpa-onnx.wasm)
```

### Extension registration

Every backend package registers through `ExtensionPoint`. The core
package never imports a backend directly; it looks up capability
providers by name at runtime:

```
@runanywhere/web-llamacpp  ──►  ExtensionPoint.registerProvider('llm', …)
@runanywhere/web-onnx      ──►  ExtensionPoint.registerProvider('stt' | 'tts' | 'vad', …)
```

This is how the `VoicePipeline` below composes STT / LLM / TTS without
importing any specific backend.

---

## Voice — two paths

The Web SDK exposes two voice orchestration surfaces. Pick one based on
how much TS-side composition your app needs.

### Path 1 — `VoicePipeline`: TS-side composition

`VoicePipeline` is the "compose-your-own" path. It drives STT → LLM
(streaming) → TTS via `ExtensionPoint` provider lookups, with
callback-style hooks for each stage. Use it when:

- you want to wire custom STT / LLM / TTS providers (e.g. a cloud STT
  fallback, a RAG-augmented LLM call);
- you don't care about `VoiceEvent` proto parity with the mobile SDKs;
- you're prototyping and want one object that drives the full turn.

```typescript
import { VoicePipeline, PipelineState } from '@runanywhere/core';

const pipeline = new VoicePipeline();

const result = await pipeline.processTurn(
  audioFloat32,                                  // Float32Array PCM @ 16 kHz
  {
    maxTokens: 150,
    temperature: 0.7,
    systemPrompt: 'You are a helpful voice assistant.',
  },
  {
    onStateChange: (state) => {
      if (state === PipelineState.ProcessingSTT)      console.log('STT…');
      else if (state === PipelineState.GeneratingResponse) console.log('LLM…');
      else if (state === PipelineState.PlayingTTS)    console.log('TTS…');
    },
    onTranscription: (text)              => console.log('User said:', text),
    onResponseToken: (_tok, accumulated) => console.log('Assistant:', accumulated),
    onSynthesisComplete: (audio, sr)     => playAudio(audio, sr),
  },
);

console.log(result.transcription, result.response, result.timing.totalMs);
```

### Path 2 — `VoiceAgentStreamAdapter`: proto `VoiceEvent` stream

`VoiceAgentStreamAdapter` is the **cross-SDK parity path**. It exposes
the same `AsyncIterable<VoiceEvent>` shape that iOS, Android, Flutter,
and React Native already use (see
[`docs/migrations/VoiceSessionEvent.md`](../migrations/VoiceSessionEvent.md)
and each SDK's voice section). Use it when:

- you're sharing UI state-machine code across platforms;
- you want the proto `VoiceEvent` shape for telemetry / replay;
- the backend has WASM voice-agent bindings wired and you want the fully
  native path (`_rac_voice_agent_set_proto_callback` under the hood).

The constructor accepts either a WASM handle (the canonical path) or a
custom `VoiceAgentStreamTransport` (useful for TS-backed orchestrators
and tests):

```typescript
import {
  VoiceAgentStreamAdapter,
  VoiceEvent,
  setRunanywhereModule,
} from '@runanywhere/core';

// Canonical (WASM-backed) path — once a backend registers the
// Emscripten module via setRunanywhereModule(mod) and creates a
// voice-agent handle through its own WASM entry point.
const adapter = new VoiceAgentStreamAdapter(handle);

for await (const event of adapter.stream()) {
  if (event.userSaid)        console.log('User said:', event.userSaid.text);
  else if (event.assistantToken) console.log('Token:', event.assistantToken.text);
  else if (event.state)      console.log('State:', event.state.current);
  else if (event.vad)        console.log('VAD:', event.vad.type);
  else if (event.audio)      void playPcm(event.audio.pcm, event.audio.sampleRateHz);
  else if (event.error)      console.error('Error:', event.error.message);
}
```

#### Cancellation

`break` out of the `for await` — the iterator's `return()` method calls
the transport's cancel function, which clears the C++ callback slot
(WASM path) or detaches the TS transport.

```typescript
for await (const event of adapter.stream()) {
  if (shouldStop(event)) break;   // deregisters automatically
}
```

#### `VoiceAgent` stub was DELETED in v0.20.0

Prior to v0.20.0 the Web SDK shipped a `VoiceAgent` / `VoiceAgentSession`
class stub at `Public/Extensions/RunAnywhere+VoiceAgent.ts`. Every
method threw `SDKError.componentNotReady('VoiceAgent', …)` — it was
never wired to anything. The class has been **deleted**, not
deprecated. See
[`docs/release/v0_20_0_release_plan.md`](../release/v0_20_0_release_plan.md)
(§ 4 "Web SDK: `VoiceAgent` stub class DELETED") and
[`docs/web_voiceagent_deletion_impact.md`](../web_voiceagent_deletion_impact.md)
for the replacement matrix.

---

## Voice turn example using `VoiceAgentStreamAdapter`

End-to-end example: capture audio with `AudioCapture`, run the Silero
VAD to segment speech, feed each utterance to a voice-agent stream, and
drive a UI state machine off `VoiceEvent` cases. This is the same
pattern the Web sample uses
(`examples/web/RunAnywhereAI/src/views/voice.ts`).

```typescript
import {
  RunAnywhere,
  AudioCapture,
  AudioPlayback,
  VoicePipeline,
  VoiceAgentStreamAdapter,
  type VoiceAgentStreamTransport,
  type VoiceEvent,
  PipelineState,
  VADEventType,
} from '@runanywhere/core';
import { VAD } from '@runanywhere/web-onnx';

// 1. Set up the orchestrator. Until the Web WASM voice-agent bindings
//    land, the sample uses a VoicePipeline-backed transport so the UI
//    code still consumes VoiceEvents. Once the WASM path is wired, swap
//    the transport for `new VoiceAgentStreamAdapter(handle)` and the UI
//    code below is unchanged.
const pipeline = new VoicePipeline();
const transport: VoiceAgentStreamTransport = makePipelineTransport(pipeline);
const adapter = new VoiceAgentStreamAdapter(transport);

// 2. Consume the event stream.
(async () => {
  for await (const event of adapter.stream()) {
    if (event.userSaid)           showUser(event.userSaid.text);
    else if (event.assistantToken) appendToken(event.assistantToken.text);
    else if (event.state)         updateStateLabel(event.state.current);
    else if (event.audio)         playFrame(event.audio.pcm, event.audio.sampleRateHz);
    else if (event.vad && event.vad.type === VADEventType.VAD_EVENT_VOICE_END_OF_UTTERANCE) {
      setStatus('Transcribing…');
    } else if (event.error) {
      console.error('Voice error:', event.error.message);
    }
  }
})();

// 3. Feed audio from the mic.
const mic = new AudioCapture();
VAD.reset();
await mic.start(
  (samples) => VAD.processSamples(samples),
  (_level)  => { /* drive visualiser */ },
);
VAD.onSpeechActivity((activity) => {
  if (activity === 'ended') {
    const segment = VAD.popSpeechSegment();
    if (segment) feedTurn(segment.samples);   // hands audio to the transport above
  }
});
```

The `makePipelineTransport` + `feedTurn` helpers live in
`examples/web/RunAnywhereAI/src/views/voice.ts` — they translate
`VoicePipeline` callbacks into `VoiceEvent` messages so the UI can
share code with the other SDKs.

---

## LLM / STT / TTS / VAD at a glance

### LLM text generation

```typescript
// Simple chat
const answer = await RunAnywhere.chat('Hello!');

// With options + metrics
const result = await RunAnywhere.generate('Write a haiku', {
  maxTokens: 60, temperature: 0.7,
});

// Streaming
const { stream, result: finalPromise, cancel } =
  await RunAnywhere.generateStream('Tell me a story');
for await (const token of stream) process.stdout.write(token);
const final = await finalPromise;   // { text, tokensUsed, tokensPerSecond, … }
```

### Speech-to-text

```typescript
import { ExtensionPoint } from '@runanywhere/core';

const stt = ExtensionPoint.requireProvider('stt', '@runanywhere/web-onnx');
const { text } = await stt.transcribe(audioFloat32, { sampleRate: 16_000 });
```

### Text-to-speech

```typescript
const tts = ExtensionPoint.requireProvider('tts', '@runanywhere/web-onnx');
const { audioData, sampleRate } = await tts.synthesize('Hello world', { speed: 1.0 });
new AudioPlayback({ sampleRate }).play(audioData, sampleRate);
```

### VAD

```typescript
import { VAD } from '@runanywhere/web-onnx';
import { AudioCapture, SpeechActivity } from '@runanywhere/core';

await VAD.load();                 // auto-downloads Silero, ~5 MB
VAD.reset();
const mic = new AudioCapture();
await mic.start(
  (samples) => VAD.processSamples(samples),
  () => {},
);
VAD.onSpeechActivity((activity) => {
  if (activity === SpeechActivity.Ended) {
    const segment = VAD.popSpeechSegment();
    if (segment) handle(segment.samples);
  }
});
```

---

## Links

- [Web SDK impact audit — deletion of the stub `VoiceAgent` class](../web_voiceagent_deletion_impact.md)
- [Cross-SDK voice migration guide (proto `VoiceEvent`)](../migrations/VoiceSessionEvent.md)
- [v0.20.0 release plan](../release/v0_20_0_release_plan.md)
- [RunAnywhere v2 architecture](../../runanywhere_v2_architecture.md)
- Other SDK docs:
  [Flutter](./flutter-sdk.md),
  [Kotlin](./kotlin-sdk.md),
  [React Native](./react-native-sdk.md)
- [`idl/voice_events.proto`](../../idl/voice_events.proto) — source of truth for the `VoiceEvent` shape
