# RunAnywhere Kotlin SDK

Privacy-first, on-device AI SDK for Kotlin Multiplatform (Android & JVM).

## Features

- **On-Device AI** - Run LLMs directly on device with no network required
- **Streaming Generation** - Real-time token streaming via Kotlin Flow
- **Speech-to-Text** - Transcribe audio with Whisper models
- **Text-to-Speech** - Neural voice synthesis
- **Voice Activity Detection** - Real-time speech detection
- **Multi-Platform** - Android (API 24+) and JVM (IntelliJ plugins, desktop)

## Installation

### Gradle (Kotlin DSL)

```kotlin
dependencies {
    // Android
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-android:0.1.4")

    // JVM (IntelliJ plugins, desktop apps)
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.4")
}
```

### Gradle (Groovy)

```groovy
dependencies {
    implementation 'com.runanywhere.sdk:RunAnywhereKotlinSDK-android:0.1.4'
}
```

## Quick Start

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.public.extensions.*

// 1. Initialize the SDK
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

// 2. Register a model
RunAnywhere.registerModel(
    name = "SmolLM2 360M",
    url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
    framework = InferenceFramework.LLAMA_CPP,
    memoryRequirement = 500_000_000
)

// 3. Download and load the model
RunAnywhere.downloadModel("SmolLM2-360M.Q8_0").collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}
RunAnywhere.loadLLMModel("SmolLM2-360M.Q8_0")

// 4. Generate text
val response = RunAnywhere.chat("Hello, how are you?")
println(response)
```

## Usage Examples

### Simple Chat

```kotlin
val response = RunAnywhere.chat("Explain quantum computing in one sentence")
println(response)
```

### Generation with Options

```kotlin
val result = RunAnywhere.generate(
    prompt = "Write a haiku about Kotlin",
    options = LLMGenerationOptions(
        maxTokens = 50,
        temperature = 0.7f
    )
)
println("Response: ${result.text}")
println("Speed: ${result.tokensPerSecond} tok/s")
```

### Streaming

```kotlin
RunAnywhere.generateStream("Tell me a short story")
    .collect { token ->
        print(token)
    }
```

### Streaming with Metrics

```kotlin
val result = RunAnywhere.generateStreamWithMetrics("Tell me a joke")

// Display tokens in real-time
result.stream.collect { token -> print(token) }

// Get final metrics
val metrics = result.result.await()
println("\nSpeed: ${metrics.tokensPerSecond} tok/s")
```

## Requirements

| Platform | Minimum Version |
|----------|-----------------|
| Android  | API 24 (7.0)    |
| JVM      | Java 17         |

**Build Requirements:**
- Kotlin 2.1.21+
- Gradle 8.11.1+

## Local Development

For SDK contributors:

```bash
cd sdk/runanywhere-kotlin

# First-time setup (downloads dependencies, builds native libs)
./scripts/build-kotlin.sh --setup

# Build
./gradlew build

# Run tests
./gradlew test
```

## API Reference

### Initialization

```kotlin
// Development mode
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

// Production mode
RunAnywhere.initialize(
    apiKey = "your-api-key",
    baseURL = "https://api.runanywhere.ai",
    environment = SDKEnvironment.PRODUCTION
)
```

### Text Generation

| Method | Description |
|--------|-------------|
| `chat(prompt)` | Simple text generation, returns String |
| `generate(prompt, options)` | Full generation with metrics |
| `generateStream(prompt)` | Streaming via Flow |
| `generateStreamWithMetrics(prompt)` | Streaming with final metrics |
| `cancelGeneration()` | Cancel ongoing generation |

### Model Management

| Method | Description |
|--------|-------------|
| `registerModel(...)` | Register a model from URL |
| `downloadModel(modelId)` | Download with progress Flow |
| `loadLLMModel(modelId)` | Load model for inference |
| `unloadLLMModel()` | Unload current model |
| `availableModels()` | List all models |
| `deleteModel(modelId)` | Delete downloaded model |

### Events

```kotlin
// Subscribe to LLM events
RunAnywhere.events.llmEvents.collect { event ->
    when (event) {
        is LLMEvent.GenerationStarted -> println("Started")
        is LLMEvent.GenerationCompleted -> println("Done: ${event.result.text}")
        is LLMEvent.GenerationFailed -> println("Error: ${event.error}")
    }
}
```

## License

Apache License 2.0 - See [LICENSE](../../LICENSE)

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for development guidelines.

## Support

- **Discord**: [Join Community](https://discord.gg/N359FBbDVd)
- **Issues**: [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email**: founders@runanywhere.ai
