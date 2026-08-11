# RunAnywhere Kotlin SDK

Privacy-first, on-device AI for Android. Run large language models, speech-to-text, text-to-speech, and voice agents locally with a single Kotlin API — optional cloud fallback, OTA model updates, and built-in observability.

[![Maven Central](https://img.shields.io/maven-central/v/io.github.sanchitmonga22/runanywhere-sdk)](https://central.sonatype.com/artifact/io.github.sanchitmonga22/runanywhere-sdk)
[![License: RunAnywhere](https://img.shields.io/badge/License-RunAnywhere-blue.svg)](../../LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%207.0%2B-green)](https://developer.android.com)
[![Kotlin](https://img.shields.io/badge/Kotlin-2.0%2B-blue?logo=kotlin)](https://kotlinlang.org)

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| Android | API 24+ (Android 7.0+) |
| Kotlin | 2.0+ |
| JVM | Java 17+ |

---

## Installation

Add dependencies to your app module's `build.gradle.kts`:

```kotlin
dependencies {
    // Core SDK (required)
    implementation("io.github.sanchitmonga22:runanywhere-sdk:0.20.15")

    // LLM support via llama.cpp (~34 MB)
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp:0.20.15")

    // Optional: STT, TTS, VAD via ONNX/Sherpa (~25 MB)
    implementation("io.github.sanchitmonga22:runanywhere-onnx:0.20.15")
}
```

Ensure `INTERNET` permission is declared for model downloads and SDK authentication:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

---

## Quick Start

```kotlin
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.SDKEnvironment
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.downloadModelStream
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.launch

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        LlamaCPP.register()

        RunAnywhere.initialize(
            context = this,
            environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
        )
    }
}

// In a coroutine scope (e.g. lifecycleScope):
suspend fun runInference() {
    val modelId = "smollm2-360m-instruct-q8_0"

    RunAnywhere.downloadModelStream(RAModelInfo(id = modelId)).collect { progress ->
        // Update UI with progress.overall_progress
    }

    RunAnywhere.loadModel(
        RAModelLoadRequest(
            model_id = modelId,
            category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
        ),
    )

    val result = RunAnywhere.generate("What is the capital of France?")
    println(result.text)
}
```

Register optional backends before initialization when needed:

```kotlin
import com.runanywhere.sdk.core.onnx.ONNX

ONNX.register()  // STT, TTS, VAD (requires runanywhere-onnx artifact)
```

---

## Capabilities

| Capability | Artifact | Model formats | Notes |
|------------|----------|---------------|-------|
| **LLM** | `runanywhere-llamacpp` | GGUF (`.gguf`) | Streaming, structured output, tool calling |
| **STT** | `runanywhere-onnx` | ONNX (`.onnx`, `.ort`) | Whisper, Sherpa streaming |
| **TTS** | `runanywhere-onnx` | ONNX, Piper voices | System TTS via Android `TextToSpeech` |
| **VLM** | `runanywhere-llamacpp` | GGUF multimodal | Image + text inference |
| **Voice** | Core + backends | — | VAD → STT → LLM → TTS pipeline |
| **NPU** | `runanywhere-qhexrt-android` (optional) | QNN / Hexagon | Qualcomm devices only |

### Supported model formats

| Format | Extension | Backend | Use case |
|--------|-----------|---------|----------|
| GGUF | `.gguf` | llama.cpp | LLM, VLM text generation |
| ONNX | `.onnx` | ONNX Runtime | STT, TTS, VAD |
| ORT | `.ort` | ONNX Runtime | Optimized STT/TTS |

Models are managed through the SDK catalog and lifecycle APIs: `RunAnywhere.downloadModelStream()`, `RunAnywhere.loadModel()`, and `RunAnywhere.listModels()`.

### Connect (trusted LAN client)

`ConnectSession` is an **Android client** for a language model hosted by a **macOS Swift** app on the same local network. Android does **not** host in this release.

- Discovery: Android NSD for `_runanywhere-connect._tcp` (published by the Mac host via Bonjour)
- Commons owns role policy, handshake validation, and generation request checks; Kotlin owns NSD + framed TCP
- `startBrowsing()` is opt-in and is the point that may trigger local-network permission UI
- Trust model: **trusted LAN only** — no TLS or pairing PIN. Do not use across untrusted networks
- React Native and Flutter SDKs do **not** ship Connect clients; use this Kotlin API (or the Swift client on iOS/iPadOS)

See [`examples/android/RunAnywhereAI/`](../../examples/android/RunAnywhereAI/) for the model-selection Connect UI and status banner.

---

## Documentation and Examples

| Resource | Link |
|----------|------|
| **Docs** | [docs.runanywhere.ai/kotlin/introduction](https://docs.runanywhere.ai/kotlin/introduction) |
| **API reference** | [docs/Documentation.md](docs/Documentation.md) |
| **Example app** | [`examples/android/RunAnywhereAI/`](../../examples/android/RunAnywhereAI/) |
| **Contributing / local build** | [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) |
| **Architecture** | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |

---

## Privacy

Inference runs on-device after models are downloaded. Network access is used for SDK authentication, model downloads, and optional analytics — prompts, responses, and audio are not sent to the cloud for inference by default.

Compliance with regulations such as HIPAA or GDPR depends on your deployment, data handling practices, and backend configuration. Review your architecture and consult legal counsel for regulated use cases.

---

## Support

- **Documentation:** [docs.runanywhere.ai](https://docs.runanywhere.ai)
- **Discord:** [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- **Email:** founders@runanywhere.ai
- **Issues:** [github.com/RunanywhereAI/runanywhere-sdks/issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)

---

## License

Copyright © 2026 RunAnywhere AI. All rights reserved.

This SDK is distributed under the [RunAnywhere License](../../LICENSE). For commercial licensing inquiries, contact founders@runanywhere.ai.
