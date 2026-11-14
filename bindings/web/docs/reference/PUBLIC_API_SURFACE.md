# Public API surface (`@runanywhere/web`)

The root package intentionally exports a small Swift-shaped surface. Prefer a
flat `RunAnywhere.*` method whenever Swift exposes a flat method for the same
operation; only reach for a namespace (`RunAnywhere.solutions`,
`RunAnywhere.pluginLoader`) when Swift itself has a namespace property there,
or when backend/package internals need a lower-level handle. Example/app code
should stick to root methods and avoid `@runanywhere/web/internal`.

See [`../../AGENTS.md`](../../AGENTS.md) for the initialization sequence this
facade sits on top of.

## Method inventory

**Model lifecycle/registry**
`RunAnywhere.loadModel`, `unloadModel`, `currentModel`,
`componentLifecycleSnapshot`, `listModels`, `queryModels`, `getModel`,
`downloadedModels`, `downloadModel`, `importModel`.

**LLM / structured output / tool calling**
`RunAnywhere.llm.generate`, `llm.generateStream`, `llm.generateStructured`,
`llm.extractStructured` (parse text you already have against a schema; async,
so it also works when the Llama BackendWorker owns the model), and
`llm.tools.register`, `llm.tools.unregister`, `llm.tools.list`.

**Speech / VLM / Voice Agent / RAG**
`RunAnywhere.transcribe`, `transcribeStream`, `synthesize`, `synthesizeStream`,
`speak`, `stopSynthesis`, `stopSpeaking`, `detectVoiceActivity`, `streamVAD`,
`resetVAD`, `processImage`, `processImageStream`, `cancelVLMGeneration`,
`initializeVoiceAgent`, `processVoiceTurn`, `streamVoiceAgent`,
`ragCreatePipeline`, `ragIngest`, `ragQuery`, etc.

## Quick-start shape

```ts
import { RunAnywhere } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';

await RunAnywhere.initialize({ environment: 'development' });
await LlamaCPP.register({ acceleration: 'auto' });

const events = RunAnywhere.llm.generateStream('Write a haiku about local AI.', {
  maxOutputTokens: 128,
});

for await (const event of events) {
  if (event.type === 'textDelta') console.log(event.text);
}
```
