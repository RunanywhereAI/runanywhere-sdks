# RunAnywhere React Native SDK — Public API Usage

iOS + Android via NitroModules (JSI). Entry point is the `RunAnywhere` object. Async calls return `Promise`; streaming returns `AsyncIterable` consumed with a manual `iterator.next()` loop (Hermes does not support `for await` over Nitro async iterables).

## Initialization

```ts
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';

// Single options-bag initialize (carries RN-only phase-2 knobs too)
await RunAnywhere.initialize({
  apiKey: 'ra_...',                  // optional in development
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
await RunAnywhere.completeServicesInitialization();

// State (bridge reads are async → Promise)
RunAnywhere.isInitialized;
RunAnywhere.areServicesReady;
RunAnywhere.version;
await RunAnywhere.deviceId;           // Promise<string>
await RunAnywhere.isAuthenticated();
```

## Models

```ts
const models = await RunAnywhere.listModels();
const downloaded = await RunAnywhere.downloadedModels();
const one = await RunAnywhere.getModel({ modelId: 'qwen2.5-0.5b' });

const info = await RunAnywhere.registerModel({
  name: 'Qwen2.5 0.5B',
  url: 'https://huggingface.co/.../model.gguf',
  framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
});

await RunAnywhere.downloadModel(info, (p) => console.log(p.percentage));
await RunAnywhere.loadModel({ modelId: info.id });
```

## LLM — text generation

```ts
const result = await RunAnywhere.generate('Explain vector databases in one line.');
console.log(result.text);

// Streaming — manual iterator loop (Hermes-safe)
const it = RunAnywhere.generateStream('Write a haiku.')[Symbol.asyncIterator]();
for (let r = await it.next(); !r.done; r = await it.next()) {
  process.stdout.write(r.value.token ?? '');
}

await RunAnywhere.cancelGeneration();
```

### Structured output & tools

```ts
const structured = await RunAnywhere.generateStructured('Extract', schema);
await RunAnywhere.registerTool(def, async (args) => ({ result: { stringValue: 'ok' } }));
const toolResult = await RunAnywhere.generateWithTools('Weather in Pune?', undefined, {
  signal: abortController.signal,   // RN uses AbortSignal for cancellation
});
```

## STT / TTS / VAD

```ts
const transcript = await RunAnywhere.transcribe(pcm16);
const audio = await RunAnywhere.synthesize('Hello there');
await RunAnywhere.speak('Spoken aloud');
await RunAnywhere.stopSpeaking();

const vad = await RunAnywhere.detectVoiceActivity(pcm16);
await RunAnywhere.resetVAD();
```

## VLM (vision)

```ts
const out = await RunAnywhere.processImage(image, { prompt: 'Describe this.' });

// prompt overload — applied onto options.prompt
const stream = await RunAnywhere.processImageStream(image, 'What is this?');
const vit = stream[Symbol.asyncIterator]();
for (let r = await vit.next(); !r.done; r = await vit.next()) console.log(r.value);

await RunAnywhere.cancelVLMGeneration();
```

## RAG

```ts
await RunAnywhere.ragCreatePipeline({ embeddingModel: emb, llmModel: llm });
await RunAnywhere.ragIngest(document);
const answer = await RunAnywhere.ragQuery('What about pricing?');
const rit = RunAnywhere.ragQueryStream('Summarize')[Symbol.asyncIterator]();
for (let r = await rit.next(); !r.done; r = await rit.next()) console.log(r.value);
```

## LoRA

```ts
await RunAnywhere.lora.applyCatalogAdapter(entry, { scale: 1.0 });
await RunAnywhere.lora.apply(entry);                 // catalog-entry overload
const state = await RunAnywhere.lora.list();
await RunAnywhere.lora.download(entry, (p) => console.log(p));
```

## Voice agent

```ts
await RunAnywhere.initializeVoiceAgentWithLoadedModels();
const vit = RunAnywhere.streamVoiceAgent()[Symbol.asyncIterator]();
for (let r = await vit.next(); !r.done; r = await vit.next()) console.log(r.value);
const turn = await RunAnywhere.processVoiceTurn(pcm16);
await RunAnywhere.cleanupVoiceAgent();
```

## Events

```ts
RunAnywhere.events.on((event) => console.log(event));

// Imperative SDK events — subscribe returns a numeric id
const id = await RunAnywhere.subscribeSDKEvents((event) => console.log(event));
await RunAnywhere.unsubscribeSDKEvents(id);
```

## Notes

- All streams are `AsyncIterable`; use manual `iterator.next()` loops (never `for await` — Hermes limitation).
- Cancellation uses `AbortSignal` (passed via the `extra` bag on `generateWithTools`, etc.).
- Web-search tool is not available on RN (RN core routes HTTP through native, not JS).
- Diffusion is Apple-gated; on non-Apple it throws.
