# RunAnywhere Flutter SDK — Public API Usage

iOS + Android via Dart FFI. Entry point is `class RunAnywhere` with `static` members. Two equivalent access styles: **flat** `RunAnywhere.x(...)` (mirrors Swift) and **capability objects** `RunAnywhere.vad.x(...)`. Streaming uses Dart `Stream`; async uses `Future`.

## Initialization

```dart
import 'package:runanywhere/runanywhere.dart';

// Phase 1
await RunAnywhere.initialize(
  apiKey: 'ra_...',                  // optional in development
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
);

// Phase 2
await RunAnywhere.completeServicesInitialization();

// State
RunAnywhere.isInitialized;
RunAnywhere.areServicesReady;
RunAnywhere.version;
RunAnywhere.deviceId;                 // getter, throws if unresolved
RunAnywhere.isAuthenticated;
```

## Models

```dart
final models = await RunAnywhere.listModels();
final downloaded = await RunAnywhere.downloadedModels();
final one = await RunAnywhere.getModel(ModelGetRequest(modelId: 'qwen2.5-0.5b'));

final info = await RunAnywhere.registerModel(
  name: 'Qwen2.5 0.5B',
  url: 'https://huggingface.co/.../model.gguf',
  framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
);

await RunAnywhere.downloadModel(info.id, onProgress: (p) async => print(p.percentage));
await RunAnywhere.loadModel(ModelLoadRequest(modelId: info.id));

RunAnywhere.downloadModelStream(info.id).listen((p) => print(p.state));
```

## LLM — text generation

```dart
final result = await RunAnywhere.generate('Explain vector databases in one line.');
print(result.text);

RunAnywhere.generateStream('Write a haiku.').listen((e) => print(e.token));
RunAnywhere.cancelGeneration();

// Dart has no method overloading — the request forms are distinct names:
await RunAnywhere.generateRequest(LLMGenerateRequest(/* ... */));
RunAnywhere.generateStreamRequest(LLMGenerateRequest(/* ... */));
```

### Structured output

```dart
final structured = await RunAnywhere.generateStructured(prompt: 'Extract', schema: schema);
final extracted = RunAnywhere.extractStructuredOutput(text: raw, schema: schema);
```

### Tool calling

```dart
RunAnywhere.registerTool(toolDefinition, (args) async => {'result': ToolValues.string('ok')});
final toolResult = await RunAnywhere.generateWithTools('Weather in Pune?');
```

## STT / TTS / VAD

```dart
final transcript = await RunAnywhere.transcribe(pcm16);
RunAnywhere.transcribeStream(audioStream).listen((p) => print(p.text));

final audio = await RunAnywhere.synthesize('Hello there');
RunAnywhere.synthesizeStream('Streamed speech').listen((chunk) {});
await RunAnywhere.speak('Spoken aloud');
await RunAnywhere.stopSpeaking();

final vad = await RunAnywhere.detectVoiceActivity(pcm16);
RunAnywhere.streamVAD(audioStream).listen((r) => print(r.isSpeech));
RunAnywhere.resetVAD();
```

## VLM (vision)

```dart
final out = await RunAnywhere.processImage(image, prompt: 'Describe this.');
RunAnywhere.processImageStream(image, prompt: 'What is this?').listen(print);
await RunAnywhere.cancelVLMGeneration();
```

## Diffusion (Apple / CoreML only)

```dart
final image = await RunAnywhere.generateImage(diffusionOptions);
RunAnywhere.generateImageStream(diffusionOptions).listen(print);
await RunAnywhere.cancelImageGeneration();
```

## RAG

```dart
await RunAnywhere.ragCreatePipelineForModels(embeddingModel: emb, llmModel: llm);
await RunAnywhere.ragIngest(document);
final answer = await RunAnywhere.ragQuery(RAGQueryOptions(question: 'Pricing?'));
RunAnywhere.ragQueryStream(RAGQueryOptions(question: 'Summarize')).listen(print);
```

## LoRA

```dart
await RunAnywhere.lora.applyCatalogAdapter(catalogEntry, scale: 1.0);
final state = await RunAnywhere.lora.list();
await RunAnywhere.lora.download(catalogEntry, onProgress: (p) => print(p));
```

## Voice agent

```dart
await RunAnywhere.initializeVoiceAgentWithLoadedModels();
RunAnywhere.streamVoiceAgent().listen((event) => print(event));
final turn = await RunAnywhere.processVoiceTurn(pcm16);
RunAnywhere.cleanupVoiceAgent();
```

## Events

```dart
RunAnywhere.events.llmEvents.listen(print);
RunAnywhere.events.modelLoaded.listen((c) => print('loaded ${c.modelId}'));

final sub = RunAnywhere.subscribeSDKEvents((event) => print(event));
await RunAnywhere.unsubscribeSDKEvents(sub);
```

## Notes

- Flat methods mirror Swift 1:1; capability objects (`RunAnywhere.vad`, `.vlm`, `.voice`, `.models`, `.lora`, ...) offer the same features plus Dart-only conveniences (`load`/`unload`/`isLoaded`, `query(question)`, etc.).
- Dart has no method overloading, so Swift's overloaded `generate`/`registerModel` map to distinct names (`generateRequest`, `registerArchiveModel`, `registerMultiFileModel`).
- Streaming uses `Stream`; cancel by cancelling the `StreamSubscription`.
