# RunAnywhere Swift SDK — Public API Usage

iOS 17.5+ / macOS 14.5+. Entry point is `enum RunAnywhere`; features are `static` methods in `public extension` blocks. This is the canonical surface every other SDK mirrors. Structured types are `RA*` typealiases to generated protos.

## Initialization

```swift
import RunAnywhere

// Phase 1 — synchronous
try RunAnywhere.initialize(
    apiKey: "ra_...",                 // optional in development
    baseURL: nil,
    environment: .development
)

// Phase 2 — async services
try await RunAnywhere.completeServicesInitialization()

// State
RunAnywhere.isInitialized
RunAnywhere.areServicesReady
RunAnywhere.version
let id = try RunAnywhere.deviceId       // throwing property
RunAnywhere.isAuthenticated
```

## Models

```swift
let models = await RunAnywhere.listModels()
let downloaded = await RunAnywhere.downloadedModels()
let one = await RunAnywhere.getModel(RAModelGetRequest(id: "qwen2.5-0.5b"))

let info = try await RunAnywhere.registerModel(
    name: "Qwen2.5 0.5B",
    url: "https://huggingface.co/.../model.gguf",
    framework: .llamaCpp
)

try await RunAnywhere.downloadModel(info) { progress in print(progress.percentage) }
_ = await RunAnywhere.loadModel(RAModelLoadRequest(modelID: info.id))

for await progress in RunAnywhere.downloadModelStream(info) { print(progress.state) }
```

## LLM — text generation

```swift
let result = try await RunAnywhere.generate(prompt: "Explain vector databases in one line.")
print(result.text)

for await event in try await RunAnywhere.generateStream(prompt: "Write a haiku.") {
    if let token = event.token { print(token, terminator: "") }
}

await RunAnywhere.cancelGeneration()
```

### Structured output

```swift
let structured = try await RunAnywhere.generateStructured(prompt: "Extract fields", schema: schema)
let extracted = try RunAnywhere.extractStructuredOutput(text: raw, schema: schema)
```

### Tool calling

```swift
await RunAnywhere.registerTool(toolDefinition) { args in ["result": RAToolValue("ok")] }
let toolResult = try await RunAnywhere.generateWithTools(prompt: "Weather in Pune?")

// Built-in web search tool (DuckDuckGo, over URLSession)
await RunAnywhere.registerWebSearchTool()
let def = RunAnywhere.webSearchToolDefinition
```

## STT / TTS / VAD

```swift
let transcript = try await RunAnywhere.transcribe(audio: data)
for await partial in RunAnywhere.transcribeStream(audio: audioStream) { print(partial.text) }

let audio = try await RunAnywhere.synthesize("Hello there")
_ = try await RunAnywhere.speak("Spoken aloud")
await RunAnywhere.stopSpeaking()

let vad = try await RunAnywhere.detectVoiceActivity(data)
for await r in RunAnywhere.streamVAD(audio: audioStream) { print(r.isSpeech) }
try await RunAnywhere.resetVAD()
```

## VLM (vision)

```swift
let out = try await RunAnywhere.processImage(image, options: .defaults())

for await event in try await RunAnywhere.processImageStream(image, prompt: "Describe this.") {
    print(event)
}
await RunAnywhere.cancelVLMGeneration()
```

## Diffusion (Apple / CoreML only)

```swift
let image = try await RunAnywhere.generateImage(options)
for await event in try await RunAnywhere.generateImageStream(options) { print(event) }
await RunAnywhere.cancelImageGeneration()
```

## RAG

```swift
try await RunAnywhere.ragCreatePipeline(embeddingModel: emb, llmModel: llm)
try await RunAnywhere.ragIngest(document)
let answer = try await RunAnywhere.ragQuery(question: "What about pricing?")
for await event in try await RunAnywhere.ragQueryStream(question: "Summarize") { print(event) }
await RunAnywhere.ragCancelQuery()      // session-scoped cancel
```

## LoRA

```swift
try await RunAnywhere.lora.apply(catalogEntry, scale: 1.0)
try await RunAnywhere.lora.applyCatalogAdapter(catalogEntry)
let state = try await RunAnywhere.lora.list()
_ = try await RunAnywhere.lora.download(catalogEntry) { p in print(p.percentage) }
```

## Voice agent

```swift
try await RunAnywhere.initializeVoiceAgentWithLoadedModels()
for await event in RunAnywhere.streamVoiceAgent() { print(event) }
let turn = try await RunAnywhere.processVoiceTurn(data)
await RunAnywhere.cleanupVoiceAgent()
```

## Events

```swift
RunAnywhere.events.llmEvents.sink { print($0) }.store(in: &cancellables)
RunAnywhere.events.modelLoaded.sink { print("loaded \($0.modelId)") }.store(in: &cancellables)

let id = RunAnywhere.subscribeSDKEvents { event in print(event) }
RunAnywhere.unsubscribeSDKEvents(id)
```

## Notes

- Inference calls are `async`; some are `throws`. Streaming returns `AsyncStream`.
- `deviceId` is a throwing computed property.
- Diffusion is Apple/CoreML only (no `inpaint` convenience on the facade; use `generateImage`).
- Events use Combine publishers.
