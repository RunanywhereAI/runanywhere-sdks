# runanywhere-qhexrt-android

**Optional Qualcomm Hexagon NPU backend for the RunAnywhere Kotlin SDK** — on-device LLM, VLM, STT, TTS, embeddings, and diffusion routed to Snapdragon Hexagon V75/V79/V81 NPUs. Android `arm64-v8a` only.

The AAR is binary-only: it bundles the QHexRT engine, JNI bridge, redistributable Qualcomm QAIRT/QNN host libraries, and Hexagon DSP skels. Model conversion / CoreML / forge tooling is not included — download models at runtime through the SDK catalog.

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
    QHexRT.register() // also installs DSP skels from AAR assets
}

RunAnywhere.initialize(context = this, /* ... */)
// Register, download, load, and infer via core APIs
```

See the [Kotlin SDK README](../../README.md) for full setup.

---

## Explicit bundle registration

When registering a bundle URL through the core model-registration API with the QHexRT backend registered, Commons selects the device's architecture folder for logical references such as `https://huggingface.co/organization/model-repository/model.json` and includes the manifest's companion files.

A known architecture pin in the first repository folder, such as `/v79` or `/v79/model.json`, is checked before network resolution or registry changes. A mismatched pin returns `RAC_ERROR_INVALID_ARGUMENT` with a message naming the bundle and device architectures; a matching pin is kept unchanged. Probe failures and unsupported devices return the same errors as logical references.

Direct `/resolve/` or `/blob/` URLs register a single file and do not receive this bundle-folder check.

---

## Modalities

| Primitive | Examples |
|-----------|----------|
| LLM text generation | LFM2.5, Cosmos3-Edge text |
| VLM | Cosmos3-Edge VLM |
| STT / ASR | Whisper, Parakeet, Canary, Moonshine |
| TTS | Magpie, Kokoro, Kitten, Melo |
| Embeddings | Nemotron Embed, EmbeddingGemma |
| Diffusion | Cosmos3-Edge / LaMa inpaint |

Exact catalog rows and Hexagon arch support are returned by the runtime model catalog after `QHexRT.register()`.

---

## Requirements

- Android `arm64-v8a` only (no `armeabi-v7a` / `x86_64` package)
- Qualcomm Snapdragon device with Hexagon **V75**, **V79**, or **V81** NPU
- Matching model manifests for the device Hexagon arch (a V81-only bundle will not run on V75)
- Core artifact `runanywhere-sdk:0.20.11`

---

## What's inside the AAR

- `librac_backend_qhexrt.so` + `librac_backend_qhexrt_jni.so`
- Redistributable QAIRT host libs (`libQnnHtp*.so`, `libQnnSystem.so`, …)
- DSP skels for V75/V79/V81 (extracted at runtime by `QHexRTSkelInstaller`)
- `META-INF/THIRD-PARTY-NOTICES-QAIRT.txt` (Qualcomm redistributable notice)
- `META-INF/LICENSE.runanywhere-qhexrt.txt`

---

## Support

- [Kotlin SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

Proprietary RunAnywhere License for the engine binaries — see [LICENSE](../../../../LICENSE).
Qualcomm QAIRT runtime libraries remain under Qualcomm's SDK redistribution terms — see `META-INF/THIRD-PARTY-NOTICES-QAIRT.txt` inside the AAR.
