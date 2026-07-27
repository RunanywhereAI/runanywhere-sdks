# runanywhere-onnx

**Optional ONNX/Sherpa backend for the RunAnywhere Kotlin SDK** — on-device STT, TTS, and VAD on Android.

[![Maven Central](https://img.shields.io/maven-central/v/io.github.sanchitmonga22/runanywhere-onnx)](https://central.sonatype.com/artifact/io.github.sanchitmonga22/runanywhere-onnx)

---

## Installation

Requires the core SDK. Add both to your app module's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("io.github.sanchitmonga22:runanywhere-sdk:0.20.11")
    implementation("io.github.sanchitmonga22:runanywhere-onnx:0.20.11")
}
```

---

## Usage

Register the backend before `RunAnywhere.initialize()`, then use the core SDK for speech APIs:

```kotlin
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.transcribe

// At app startup
ONNX.register()
RunAnywhere.initialize(context = this, /* ... */)

// After download/load an STT model via core APIs
val output = RunAnywhere.transcribe(audioData)
println(output.text)
```

For model registration, TTS, VAD, and voice-agent flows, see the [Kotlin SDK README](../../README.md).

---

## Requirements

- Android API 24+
- `RECORD_AUDIO` permission for microphone capture
- Core artifact `runanywhere-sdk:0.20.11`

---

## Support

- [Kotlin SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](../../../../LICENSE).
