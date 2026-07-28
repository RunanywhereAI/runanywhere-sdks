# runanywhere-llamacpp

**Optional llama.cpp LLM backend for the RunAnywhere Kotlin SDK** — on-device text generation with GGUF models on Android.

[![Maven Central](https://img.shields.io/maven-central/v/io.github.sanchitmonga22/runanywhere-llamacpp)](https://central.sonatype.com/artifact/io.github.sanchitmonga22/runanywhere-llamacpp)

---

## Installation

Requires the core SDK. Add both to your app module's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("io.github.sanchitmonga22:runanywhere-sdk:0.20.11")
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp:0.20.11")
}
```

---

## Usage

Register the backend before `RunAnywhere.initialize()`, then use the core SDK for model lifecycle and inference:

```kotlin
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.loadModel
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.types.RAModelLoadRequest

// At app startup
LlamaCPP.register()
RunAnywhere.initialize(context = this, /* ... */)

// After download/register model via core APIs
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "my-gguf-model",
        category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ),
)
val result = RunAnywhere.generate("What is on-device AI?")
println(result.text)
```

For registration, downloads, streaming, and model catalogs, see the [Kotlin SDK README](../../README.md).

---

## Requirements

- Android API 24+ (ARM64 recommended)
- Core artifact `runanywhere-sdk:0.20.11`

---

## Support

- [Kotlin SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](../../../../LICENSE).
