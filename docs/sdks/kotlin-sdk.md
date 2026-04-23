# RunAnywhere Kotlin Multiplatform SDK

Cross-platform SDK for on-device AI inference with intelligent routing. Supports JVM, Android, and (planned) Native targets.

## Installation

### Gradle (Maven Central)

```kotlin
dependencies {
    // Core SDK (required)
    implementation("io.github.sanchitmonga22:runanywhere-sdk:0.1.5-SNAPSHOT")

    // Backend modules (pick what you need)
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp:0.1.5-SNAPSHOT")  // LLM
    implementation("io.github.sanchitmonga22:runanywhere-onnx:0.1.5-SNAPSHOT")     // STT/TTS/VAD
    implementation("io.github.sanchitmonga22:runanywhere-genie-android:0.1.5-SNAPSHOT") // Qualcomm NPU (stub)
}
```

### JitPack

```kotlin
repositories {
    maven { url = uri("https://jitpack.io") }
}
dependencies {
    implementation("com.github.RunanywhereAI.runanywhere-sdks:sdk-runanywhere-kotlin:main-SNAPSHOT")
}
```

## Platform Requirements

| Platform | Requirement |
|----------|-------------|
| Kotlin | 2.1.21 |
| JVM Target | Java 17 |
| Android Min SDK | 24 |
| Android Target SDK | 36 |
| Gradle | 8.11.1+ |

## Quick Start

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.extensions.Models.ModelCategory

// 1. Initialize SDK
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

// 2. Register backends
LlamaCPP.register(priority = 100)
ONNX.register(priority = 100)
Genie.register(priority = 200) // Qualcomm NPU

// 3. Register a model
RunAnywhere.registerModel(
    id = "qwen3-4b-q4_k_m",
    name = "Qwen3 4B",
    url = "https://huggingface.co/.../Qwen3-4B-Q4_K_M.gguf",
    framework = InferenceFramework.LLAMA_CPP,
    modality = ModelCategory.LANGUAGE,
    memoryRequirement = 2_800_000_000
)

// 4. Download and load
RunAnywhere.downloadModel("qwen3-4b-q4_k_m").collect { progress ->
    println("${(progress.progress * 100).toInt()}%")
}
RunAnywhere.loadLLMModel("qwen3-4b-q4_k_m")

// 5. Generate text
val response = RunAnywhere.chat("Hello!")
println(response)
```

## Architecture

### Module Structure

```
runanywhere-kotlin/
├── src/
│   ├── commonMain/          # Cross-platform business logic, interfaces, types
│   ├── jvmAndroidMain/      # Shared JVM/Android: C++ bridge, JNI, HTTP
│   ├── androidMain/         # Android-specific: secure storage, device info
│   └── jvmMain/             # JVM/Desktop: IntelliJ plugin support
├── modules/
│   ├── runanywhere-core-llamacpp/   # llama.cpp backend (LLM, VLM)
│   └── runanywhere-core-onnx/      # ONNX Runtime backend (STT, TTS, VAD)
```

### Two-Phase Initialization

**Phase 1 — Core Init** (synchronous, ~1-5ms, no network):
```
RunAnywhere.initialize()
  ├─ CppBridge.initialize()
  │   ├─ PlatformAdapter.register()   ← File ops, logging, keychain
  │   ├─ Events.register()            ← Analytics callback
  │   ├─ Telemetry.initialize()       ← HTTP callback
  │   └─ Device.register()            ← Device info
  └─ Mark: isInitialized = true
```

**Phase 2 — Services Init** (async, ~100-500ms):
```
RunAnywhere.completeServicesInitialization()
  ├─ CppBridge.initializeServices()
  │   ├─ ModelAssignment.register()   ← Backend model assignments
  │   └─ Platform.register()          ← LLM/TTS service callbacks
  └─ Mark: areServicesReady = true
```

Phase 2 runs automatically on first API call, or can be awaited explicitly.

---

## API Reference

### SDK Lifecycle

```kotlin
// Initialize (Phase 1)
fun RunAnywhere.initialize(
    apiKey: String? = null,
    baseURL: String? = null,
    environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
)

// Complete services (Phase 2) — auto-called on first API use
suspend fun RunAnywhere.completeServicesInitialization()

// State
val RunAnywhere.isInitialized: Boolean
val RunAnywhere.areServicesReady: Boolean
val RunAnywhere.isActive: Boolean
val RunAnywhere.version: String
val RunAnywhere.environment: SDKEnvironment?

// Cleanup
suspend fun RunAnywhere.reset()
suspend fun RunAnywhere.cleanup()
```

### Text Generation (LLM)

```kotlin
// Simple chat
suspend fun RunAnywhere.chat(prompt: String): String

// Full generation with metrics
suspend fun RunAnywhere.generate(
    prompt: String,
    options: LLMGenerationOptions? = null
): LLMGenerationResult

// Streaming (token-by-token)
fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions? = null
): Flow<String>

// Streaming with final metrics
suspend fun RunAnywhere.generateStreamWithMetrics(
    prompt: String,
    options: LLMGenerationOptions? = null
): LLMStreamingResult

// Control
fun RunAnywhere.cancelGeneration()

// Model loading
suspend fun RunAnywhere.loadLLMModel(modelId: String)
suspend fun RunAnywhere.unloadLLMModel()
suspend fun RunAnywhere.isLLMModelLoaded(): Boolean
val RunAnywhere.currentLLMModelId: String?
```

**Generation Options:**
```kotlin
data class LLMGenerationOptions(
    val maxTokens: Int = 1000,
    val temperature: Float = 0.7f,
    val topP: Float = 1.0f,
    val stopSequences: List<String> = emptyList(),
    val streamingEnabled: Boolean = false,
    val preferredFramework: InferenceFramework? = null,
    val structuredOutput: StructuredOutputConfig? = null,
    val systemPrompt: String? = null
)
```

**Generation Result:**
```kotlin
data class LLMGenerationResult(
    val text: String,
    val thinkingContent: String? = null,
    val tokensUsed: Int,
    val modelUsed: String,
    val latencyMs: Double,
    val tokensPerSecond: Double = 0.0,
    val timeToFirstTokenMs: Double? = null,
    val thinkingTokens: Int? = null,
    val responseTokens: Int = tokensUsed
)
```

### Speech-to-Text (STT)

```kotlin
suspend fun RunAnywhere.transcribe(audioData: ByteArray): String

suspend fun RunAnywhere.transcribeWithOptions(
    audioData: ByteArray,
    options: STTOptions
): STTOutput

suspend fun RunAnywhere.loadSTTModel(modelId: String)
suspend fun RunAnywhere.unloadSTTModel()
suspend fun RunAnywhere.isSTTModelLoaded(): Boolean
```

### Text-to-Speech (TTS)

```kotlin
suspend fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions = TTSOptions()
): TTSOutput

suspend fun RunAnywhere.speak(
    text: String,
    options: TTSOptions = TTSOptions()
): TTSSpeakResult

suspend fun RunAnywhere.loadTTSVoice(voiceId: String)
suspend fun RunAnywhere.unloadTTSVoice()
suspend fun RunAnywhere.availableTTSVoices(): List<String>
```

### Voice Activity Detection (VAD)

```kotlin
suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): VADResult
fun RunAnywhere.streamVAD(audioSamples: Flow<FloatArray>): Flow<VADResult>
suspend fun RunAnywhere.resetVAD()
```

### Vision Language Models (VLM)

```kotlin
// Simple
suspend fun RunAnywhere.describeImage(
    image: VLMImage,
    prompt: String = "What's in this image?"
): String

// Full with metrics
suspend fun RunAnywhere.processImage(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions? = null
): VLMResult

// Streaming
fun RunAnywhere.processImageStream(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions? = null
): Flow<String>

// Image construction
VLMImage.fromFilePath(path: String): VLMImage
VLMImage.fromBase64(data: String): VLMImage
VLMImage.fromRGBPixels(data: ByteArray, width: Int, height: Int): VLMImage
```

### Voice Agent (Complete Pipeline)

The voice agent uses a proto-event stream backed by the C++
voice agent. There is no `VoiceSessionEvent` sealed class anymore —
consume the `VoiceEvent` proto directly via `VoiceAgentStreamAdapter`.

```kotlin
import com.runanywhere.sdk.adapters.VoiceAgentStreamAdapter
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import ai.runanywhere.proto.v1.VoiceEvent
import ai.runanywhere.proto.v1.StateChangeEvent
import ai.runanywhere.proto.v1.VADEvent

// 1. Models must already be loaded (loadSTT/loadLLM/loadTTS).
// 2. Get the native voice-agent handle (lazily creates + initializes).
val handle: Long = CppBridgeVoiceAgent.getHandle()

// 3. Wrap as a Flow<VoiceEvent>.
val adapter = VoiceAgentStreamAdapter(handle)

// 4. Collect proto events; switch on the populated payload arm.
adapter.stream().collect { event: VoiceEvent ->
    when {
        event.user_said != null -> {
            println("User said: ${event.user_said!!.text}")
        }
        event.assistant_token != null -> {
            // Streaming: per-token (typewriter UX). Append to UI.
            print(event.assistant_token!!.text)
        }
        event.state != null -> {
            // event.state.current ∈ IDLE / LISTENING / THINKING / SPEAKING / STOPPED
            println("State: ${event.state!!.current}")
        }
        event.vad != null -> {
            // event.vad.type ∈ VAD_EVENT_VOICE_START / VOICE_END_OF_UTTERANCE
            println("VAD: ${event.vad!!.type}")
        }
        event.audio != null -> {
            // TTS audio frame; routed by the C++ voice agent.
        }
        event.error != null -> {
            println("Error: ${event.error!!.message}")
        }
    }
}
```

#### Cancellation

Cancel the Flow's collecting Job to stop the voice agent:

```kotlin
val job = scope.launch { adapter.stream().collect { /* ... */ } }
// Later:
job.cancel()                          // unwires the C-side callback
CppBridgeVoiceAgent.destroy()         // tears down the native handle
```

See [docs/migrations/VoiceSessionEvent.md](../migrations/VoiceSessionEvent.md)
for migration of consumers using the deleted `VoiceSessionEvent` sealed class.

### Model Management

```kotlin
// Registration
fun RunAnywhere.registerModel(
    id: String? = null,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.LANGUAGE,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
    supportsLora: Boolean = false
): ModelInfo

fun RunAnywhere.registerMultiFileModel(
    id: String,
    name: String,
    files: List<ModelFileDescriptor>,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MULTIMODAL,
    memoryRequirement: Long? = null
): ModelInfo

// Discovery
suspend fun RunAnywhere.availableModels(): List<ModelInfo>
suspend fun RunAnywhere.downloadedModels(): List<ModelInfo>
suspend fun RunAnywhere.model(modelId: String): ModelInfo?

// Download
fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress>
suspend fun RunAnywhere.cancelDownload(modelId: String)
suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean

// Lifecycle
suspend fun RunAnywhere.deleteModel(modelId: String)
suspend fun RunAnywhere.deleteAllModels()
```

### LoRA Adapters

```kotlin
suspend fun RunAnywhere.loadLoraAdapter(config: LoRAAdapterConfig)
suspend fun RunAnywhere.removeLoraAdapter(path: String)
suspend fun RunAnywhere.clearLoraAdapters()
suspend fun RunAnywhere.getLoadedLoraAdapters(): List<LoRAAdapterInfo>
fun RunAnywhere.registerLoraAdapter(entry: LoraAdapterCatalogEntry)
fun RunAnywhere.downloadLoraAdapter(adapterId: String): Flow<DownloadProgress>
```

### RAG (Retrieval-Augmented Generation)

```kotlin
suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfiguration)
suspend fun RunAnywhere.ragIngest(text: String, metadataJson: String? = null)
suspend fun RunAnywhere.ragQuery(
    question: String,
    options: RAGQueryOptions? = null
): RAGResult
suspend fun RunAnywhere.ragClearDocuments()
suspend fun RunAnywhere.ragDestroyPipeline()
```

### NPU Chip Detection

```kotlin
fun RunAnywhere.getChip(): NPUChip?
```

Returns the detected Qualcomm NPU chipset, or `null` if unsupported.

```kotlin
enum class NPUChip(
    val identifier: String,
    val displayName: String,
    val socModel: String,
    val npuSuffix: String
) {
    SNAPDRAGON_8_ELITE("8elite", "Snapdragon 8 Elite", "SM8750", "8elite"),
    SNAPDRAGON_8_ELITE_GEN5("8elite-gen5", "Snapdragon 8 Elite Gen 5", "SM8850", "8elite-gen5");

    fun downloadUrl(modelSlug: String, quant: String = "w4a16"): String
    companion object {
        fun fromSocModel(socModel: String): NPUChip?
    }
}
```

**Detection strategy (Android):**
1. `Build.SOC_MODEL` (API 31+) — e.g. "SM8750"
2. `Build.HARDWARE` — fallback codename
3. `/proc/cpuinfo` Hardware line — last resort

### Event Bus

```kotlin
val RunAnywhere.events: EventBus

// Subscribe to events
RunAnywhere.events.llmEvents.collect { event -> /* ... */ }
RunAnywhere.events.modelEvents.collect { event -> /* ... */ }
RunAnywhere.events.errorEvents.collect { event -> /* ... */ }

// Event categories
enum class EventCategory {
    SDK, MODEL, LLM, STT, TTS, VOICE, STORAGE, DEVICE, NETWORK, ERROR, RAG
}
```

### Storage

```kotlin
suspend fun RunAnywhere.storageInfo(): StorageInfo
suspend fun RunAnywhere.checkStorageAvailability(requiredBytes: Long): StorageAvailability
suspend fun RunAnywhere.cacheSize(): Long
suspend fun RunAnywhere.clearCache()
```

### Logging

```kotlin
fun RunAnywhere.setLogLevel(level: LogLevel)
fun RunAnywhere.getLogLevel(): LogLevel

enum class LogLevel { TRACE, DEBUG, INFO, WARNING, ERROR, FAULT }
```

---

## Core Types

### Inference Frameworks

```kotlin
enum class InferenceFramework(val rawValue: String) {
    ONNX("ONNX"),              // ONNX Runtime — STT, TTS, VAD, embeddings
    LLAMA_CPP("LlamaCpp"),     // llama.cpp — LLM, VLM (GGUF models)
    GENIE("Genie"),            // Qualcomm Genie — NPU inference
    FOUNDATION_MODELS("FoundationModels"),
    SYSTEM_TTS("SystemTTS"),
    FLUID_AUDIO("FluidAudio"),
    BUILT_IN("BuiltIn"),
    NONE("None"),
    UNKNOWN("Unknown")
}
```

### Model Categories

```kotlin
enum class ModelCategory(val value: String) {
    LANGUAGE("language"),
    SPEECH_RECOGNITION("speech-recognition"),
    SPEECH_SYNTHESIS("speech-synthesis"),
    VISION("vision"),
    IMAGE_GENERATION("image-generation"),
    MULTIMODAL("multimodal"),
    AUDIO("audio"),
    EMBEDDING("embedding")
}
```

### Error Handling

```kotlin
data class SDKError(
    val code: ErrorCode,
    val category: ErrorCategory,
    override val message: String,
    override val cause: Throwable? = null
) : Exception(message, cause)

// 40+ factory methods:
SDKError.notInitialized()
SDKError.modelNotFound(modelId)
SDKError.modelLoadFailed(message)
SDKError.network(message)
SDKError.download(message)
// ... etc
```

---

## Build System

### Build Commands

```bash
cd sdk/runanywhere-kotlin/

# Build all platforms
./scripts/sdk.sh build

# Individual targets
./scripts/sdk.sh jvm          # JVM JAR only
./scripts/sdk.sh android      # Android AAR only

# Test
./scripts/sdk.sh test         # All tests
./scripts/sdk.sh test-jvm     # JVM tests only

# Publish to Maven Local
./scripts/sdk.sh publish

# Clean
./scripts/sdk.sh clean
./scripts/sdk.sh deep-clean   # Including Gradle caches
```

### Native Library Modes

Controlled by `gradle.properties`:

```properties
# Local development (build C++ from source)
runanywhere.useLocalNatives=true

# CI/Release (download pre-built from GitHub releases)
runanywhere.useLocalNatives=false
runanywhere.nativeLibVersion=0.1.4
```

### Build Output

```
build/libs/RunAnywhereKotlinSDK-jvm-0.1.0.jar
build/outputs/aar/RunAnywhereKotlinSDK-debug.aar
~/.m2/repository/com/runanywhere/sdk/   (after publish)
```

---

## Genie NPU Models

Available models on HuggingFace (`runanywhere/genie-npu-models`):

| Model | Slug | Quant | Supported Chips | Size |
|-------|------|-------|-----------------|------|
| Qwen3 4B | `qwen3-4b` | w4a16 | 8 Elite Gen 5 | 2.5 GB |
| Llama 3.2 1B Instruct | `llama3.2-1b-instruct` | w4a16 | 8 Elite, 8 Elite Gen 5 | 1.3 GB |
| SEA-LION v3.5 8B Instruct | `sea-lion3.5-8b-instruct` | w4a16 | 8 Elite, 8 Elite Gen 5 | 4.5 GB |
| Qwen 2.5 7B Instruct | `qwen2.5-7b-instruct` | w8a16 | 8 Elite | 3.9 GB |

**URL format:** `https://huggingface.co/runanywhere/genie-npu-models/resolve/main/{slug}-genie-{quant}-{chip}.tar.gz`

```kotlin
val chip = RunAnywhere.getChip() ?: return
val url = chip.downloadUrl("qwen3-4b")           // w4a16 (default)
val url = chip.downloadUrl("qwen2.5-7b-instruct", quant = "w8a16")
```
