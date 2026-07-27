# runanywhere-qhexrt-android

**Optional Qualcomm Hexagon NPU backend for the RunAnywhere Kotlin SDK** — on-device LLM, VLM, STT, and TTS routed to Snapdragon V75/V79/V81 NPUs. Android `arm64-v8a` only.

---

## Installation

Requires the core SDK. Add both to your app module's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("io.github.sanchitmonga22:runanywhere-sdk:0.20.11")
    implementation("io.github.sanchitmonga22:runanywhere-qhexrt-android:0.20.11")
}
```

---

## Usage

Probe capability, register once at startup, then use standard RunAnywhere APIs — the SDK routes supported models to the NPU:

```kotlin
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import com.runanywhere.sdk.public.RunAnywhere

val npu = QHexRT.probeNpu() // safe on any device
if (npu.qhexrt_supported) {
    QHexRT.register()
}

RunAnywhere.initialize(context = this, /* ... */)
// Register, download, load, and infer via core APIs
```

See the [Kotlin SDK README](../../README.md) for full setup.

---

## Requirements

- Android `arm64-v8a`
- Qualcomm Snapdragon device with Hexagon V75, V79, or V81 NPU
- Core artifact `runanywhere-sdk:0.20.11`

---

## Support

- [Kotlin SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

Proprietary. See [LICENSE](../../../../LICENSE).
