# runanywhere-qhexrt-android

**Optional Qualcomm Hexagon NPU backend for the RunAnywhere Kotlin SDK** — on-device LLM, VLM, STT, TTS, embeddings, and diffusion routed to Snapdragon Hexagon V75/V79/V81 NPUs. Android `arm64-v8a` only.

The AAR is binary-only: it bundles the QHexRT engine, JNI bridge, redistributable Qualcomm QAIRT/QNN host libraries, and Hexagon DSP skels. Model conversion / CoreML / forge tooling is not included. Register the dedicated model URL supplied by the model publisher through the core SDK.

---

## Installation

Requires the core SDK. Add both to your app module's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("io.github.sanchitmonga22:runanywhere-sdk:0.20.37")
    implementation("io.github.sanchitmonga22:runanywhere-qhexrt-android:0.20.37")
}
```

The examples below target this source tree (SDK `0.20.37`). For changes not yet
released, use local SDK packages and native libraries built from the same
checkout; a matching version number alone does not include unreleased changes.

---

## Usage

Probe capability, register once at startup, then use standard RunAnywhere APIs — the SDK routes supported models to the NPU:

```kotlin
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.ModelRegistration
import com.runanywhere.sdk.public.api.models
import ai.runanywhere.proto.v1.InferenceFramework
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

lifecycleScope.launch {
    RunAnywhere.initialize(context = this@MainActivity)

    val npu = QHexRT.probeNpu() // safe on any device
    if (npu.supported) {
        QHexRT.register() // also installs DSP skels from AAR assets
        if (QHexRT.isRegistered) {
            RunAnywhere.models.register(
                ModelRegistration.url(
                    id = "my-qhexrt-model",
                    name = "My QHexRT Model",
                    url = "https://huggingface.co/organization/dedicated-qhexrt-model/model.json",
                    framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                ),
            )
            // Download, load, and infer via core APIs.
        }
    }
}
```

See the [Kotlin SDK README](../../README.md) for full setup.

The URL above is a logical bundle reference: Commons selects the device's architecture folder and registers the manifest with its companion files. A direct `/resolve/main/model.json` URL registers only that file. Explicitly pinned bundle references are preserved as supplied; registration does not reject a pin for a different device architecture. Before registration, compare each pinned bundle's required architecture with `QHexRT.probeNpu()` and skip incompatible rows. Catalog eligibility and any required HF-auth preflight are application-owned.

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

QHexRT does not seed or select models. Register the exact model URL intended for the target device. Use `QHexRT.probeNpu()` as an optional preflight when your UI needs to report device support before registration.

---

## Requirements

- Android `arm64-v8a` only (no `armeabi-v7a` / `x86_64` package)
- Qualcomm Snapdragon device with Hexagon **V75**, **V79**, or **V81** NPU
- Matching model manifests for the device Hexagon arch (a V81-only bundle will not run on V75)
- Core artifact `runanywhere-sdk:0.20.37`

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
