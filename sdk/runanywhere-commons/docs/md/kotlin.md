# RunAnywhere Kotlin SDK — Public API Usage

Android library. Entry point is the `object RunAnywhere`; every feature is a suspend/Flow extension function on it. Structured types come from generated Wire proto messages (`RA*` typealiases).

## Initialization

```kotlin
import com.runanywhere.sdk.public.RunAnywhere

// Phase 1 — synchronous registration (call from Application.onCreate)
RunAnywhere.initialize(
    context = applicationContext,
    apiKey = "ra_...",                 // optional in development
    environment = SDK_ENVIRONMENT_DEVELOPMENT,
)

// Phase 2 — async services (auth, device registration, model assignments)
RunAnywhere.completeServicesInitialization()

// State
RunAnywhere.isInitialized        // Boolean
RunAnywhere.areServicesReady     // Boolean
RunAnywhere.version              // String
RunAnywhere.deviceId             // String (throws if identity unresolved)
RunAnywhere.isAuthenticated
```

## Models

```kotlin
// Discover / query
val models = RunAnywhere.listModels()
val downloaded = RunAnywhere.downloadedModels()
val one = RunAnywhere.getModel(ModelGetRequest(model_id = "qwen2.5-0.5b"))

// Register a remote model
val info = RunAnywhere.registerModel(
    name = "Qwen2.5 0.5B",
    url = "https://huggingface.co/.../model.gguf",
    framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
)

// Download (with progress) then load
RunAnywhere.downloadModel(info) { progress -> println("${progress.percentage}%") }
RunAnywhere.loadModel(info)

// Streaming download
RunAnywhere.downloadModelStream(info).collect { println(it.state) }
```

## LLM — text generation

```kotlin
// One-shot
val result = RunAnywhere.generate("Explain vector databases in one line.")
println(result.text)

// Streaming
RunAnywhere.generateStream("Write a haiku about the sea.").collect { event ->
    event.token?.let { print(it) }
}

RunAnywhere.cancelGeneration()
```

### Structured output

```kotlin
val schema: RAJSONSchema = /* build JSON schema */
val structured = RunAnywhere.generateStructured("Extract name + age", schema)
```

### Tool calling

```kotlin
RunAnywhere.registerTool(toolDefinition) { args -> mapOf("result" to ToolValue.string("ok")) }
val toolResult = RunAnywhere.generateWithTools(
    prompt = "What's the weather in Pune?",
    options = null, toolOptions = null, toolChoice = null, forcedToolName = null,
)

// Built-in web search tool (DuckDuckGo, over OkHttp)
RunAnywhere.registerWebSearchTool()
val definition = RunAnywhere.webSearchToolDefinition
```

## STT / TTS / VAD

```kotlin
val transcript = RunAnywhere.transcribe(pcm16Bytes)
RunAnywhere.transcribeStream(audioFlow).collect { println(it.text) }

val audio = RunAnywhere.synthesize("Hello there")
RunAnywhere.speak("Spoken aloud")
RunAnywhere.stopSpeaking()

val vad = RunAnywhere.detectVoiceActivity(pcm16Bytes)
RunAnywhere.streamVAD(audioFlow).collect { println(it.isSpeech) }
RunAnywhere.resetVAD()
```

## VLM (vision)

```kotlin
val image = VLMImage.fromBitmap(bitmap)
val out = RunAnywhere.processImage(image, VLMGenerationOptions.defaults(prompt = "Describe this."))

// Streaming — prompt inline or in options
RunAnywhere.processImageStream(image, prompt = "What is this?").collect { print(it) }
RunAnywhere.cancelVLMGeneration()
```

## RAG

```kotlin
RunAnywhere.ragCreatePipeline(embeddingModel, llmModel)
RunAnywhere.ragIngest(RARAGDocument(/* ... */))
val answer = RunAnywhere.ragQuery("What does the doc say about pricing?")
RunAnywhere.ragQueryStream("Summarize section 2").collect { print(it) }
RunAnywhere.ragCancelQuery()
```

## LoRA

```kotlin
RunAnywhere.lora.apply(catalogEntry, scale = 1.0f)
RunAnywhere.lora.applyCatalogAdapter(catalogEntry)      // named alias
val state = RunAnywhere.lora.list()
RunAnywhere.lora.download(catalogEntry) { p -> println(p.percentage) }
```

## Voice agent

```kotlin
RunAnywhere.initializeVoiceAgentWithLoadedModels()
RunAnywhere.streamVoiceAgent().collect { event -> println(event) }
val turn = RunAnywhere.processVoiceTurn(pcm16Bytes)
RunAnywhere.cleanupVoiceAgent()
```

## Events

```kotlin
RunAnywhere.events.llmEvents.collect { println(it) }
RunAnywhere.events.modelLoaded.collect { println("loaded ${it.modelId}") }

val subId = RunAnywhere.subscribeSDKEvents { event -> println(event) }
RunAnywhere.unsubscribeSDKEvents(subId)
```

## Notes

- All inference calls are `suspend`; streaming returns `Flow`.
- Android-only capability: image generation / `inpaint` runs on the Qualcomm NPU (qhexrt) — not present on iOS.
- Diffusion, when a model is loaded: `RunAnywhere.generateImage(options)` and `RunAnywhere.inpaint(...)`.
