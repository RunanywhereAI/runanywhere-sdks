# RunAnywhere Web SDK — Public API Usage

Browsers via Emscripten WASM + TypeScript. Entry point is the `RunAnywhere` object (flat facade). Async calls return `Promise`; streaming returns `AsyncIterable`. Requires cross-origin isolation (COOP/COEP) for `SharedArrayBuffer`.

## Initialization

```ts
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';

await RunAnywhere.initialize({
  apiKey: 'ra_...',                  // optional in development
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
await RunAnywhere.completeServicesInitialization();

// State
RunAnywhere.isInitialized;
RunAnywhere.areServicesReady;
RunAnywhere.version;
RunAnywhere.deviceId;                 // throwing getter
RunAnywhere.isAuthenticated;

// Web-only: acceleration runtime + browser storage
RunAnywhere.setRuntime('webgpu');    // or 'wasm'
await RunAnywhere.hydrateModelRegistry();
```

## Models

```ts
const models = RunAnywhere.listModels();
const downloaded = RunAnywhere.downloadedModels();
const one = RunAnywhere.getModel('qwen2.5-0.5b');
const framework = RunAnywhere.getDefaultFramework(ModelCategory.MODEL_CATEGORY_LANGUAGE);
const role = RunAnywhere.inferModelFileRole('mmproj.gguf', ModelCategory.MODEL_CATEGORY_MULTIMODAL);

const info = RunAnywhere.registerModel('https://.../model.gguf', 'Qwen2.5 0.5B', framework);

await RunAnywhere.downloadModel(info.id, { onProgress: (p) => console.log(p.percentage) });
await RunAnywhere.loadModel({ modelId: info.id });

for await (const p of RunAnywhere.downloadModelStream(info.id)) console.log(p.state);
```

## LLM — text generation

```ts
const result = await RunAnywhere.generate({ prompt: 'Explain vector databases in one line.' });
console.log(result.text);

// generateStream returns { events, stream, result, cancel }
const streaming = await RunAnywhere.generateStream({ prompt: 'Write a haiku.' });
for await (const token of streaming.stream) process.stdout.write(token);
const final = await streaming.result;

RunAnywhere.cancelGeneration();
```

### Structured output & tools

```ts
const structured = await RunAnywhere.generateStructured('Extract', schema);
RunAnywhere.registerTool(def, async (args) => ({ result: { stringValue: 'ok' } }));
const toolResult = await RunAnywhere.generateWithTools('Weather in Pune?', undefined, {
  signal: abortController.signal,
});
```

## STT / TTS / VAD

```ts
const transcript = await RunAnywhere.transcribe(pcm16);
for await (const p of RunAnywhere.transcribeStream(audioStream)) console.log(p.text);

const audio = await RunAnywhere.synthesize('Hello there');
for await (const chunk of RunAnywhere.synthesizeStream('Streamed speech')) { /* ... */ }
await RunAnywhere.speak('Spoken aloud');
RunAnywhere.stopSpeaking();
RunAnywhere.stopSynthesis();

const vad = await RunAnywhere.detectVoiceActivity(float32);
for await (const r of RunAnywhere.streamVAD(frameStream)) console.log(r.isSpeech);
RunAnywhere.resetVAD();
```

## VLM (vision)

```ts
const out = await RunAnywhere.processImage(image, options);

// prompt overload
const stream = await RunAnywhere.processImageStream(image, 'Describe this.');
for await (const event of stream) console.log(event);

await RunAnywhere.cancelVLMGeneration();
```

## RAG

```ts
await RunAnywhere.ragCreatePipeline(embeddingModelId, llmModelId);
await RunAnywhere.ragIngest(document);
const answer = await RunAnywhere.ragQuery('What about pricing?');
for await (const event of RunAnywhere.ragQueryStream('Summarize')) console.log(event);
const count = await RunAnywhere.ragDocumentCount();
```

## LoRA

```ts
await RunAnywhere.lora.applyCatalogAdapter(entry, { scale: 1.0 });
const state = await RunAnywhere.lora.list();
await RunAnywhere.lora.download(entry, (p) => console.log(p));
// Browser import takes a File/Blob
await RunAnywhere.lora.importAdapter(file, 'adapter.bin');
```

## Voice agent

```ts
await RunAnywhere.initializeVoiceAgentWithLoadedModels();
for await (const event of RunAnywhere.streamVoiceAgent()) console.log(event);
const turn = await RunAnywhere.processVoiceTurn(float32);
await RunAnywhere.cleanupVoiceAgent();
```

## Events

```ts
// Flat aliases (Swift-named) delegate to the sdkEvents adapter
const unsubscribe = RunAnywhere.subscribeSDKEvents((event) => console.log(event));
unsubscribe?.();
RunAnywhere.publishSDKEvent(event);
const next = RunAnywhere.pollSDKEvent();

// Reactive EventBus
RunAnywhere.events.modelLoaded; // async-iterable stream
```

## Notes

- `generateStream` returns a rich `LLMStreamingResult` (`events`, `stream`, `result`, `cancel`) rather than a bare iterable.
- Component-handle namespaces (`RunAnywhere.stt/tts/vad.*`) exist for advanced use; the flat methods are lifecycle-auto (no handle).
- Web-only surface: browser storage / OPFS (`RunAnywhere.storage.*`), runtime modes, hybrid STT (`RunAnywhere.hybrid.*`).
- Not available on Web: `setHfToken`, web-search tool, standalone id-based `unsubscribeSDKEvents` (use the closure returned by `subscribeSDKEvents`). Diffusion is Apple-only.
