# runanywhere-core-qhexrt

Private QHexRT backend for the RunAnywhere Kotlin SDK. Runs prebuilt QNN context
binaries on Qualcomm Snapdragon Hexagon V75/V79/V81 NPUs, serving LLM, VLM, STT and
TTS through the standard SDK APIs.

Android only, `arm64-v8a` only. The device-validated set is V75, V79, and V81;
all other parts are declined and the SDK can fall back to CPU engines.

## Bundled native libraries

`src/main/jniLibs/arm64-v8a/`:

- `librac_backend_qhexrt_jni.so` — JNI bridge (registration + NPU probe)
- `librac_backend_qhexrt.so` — QHexRT C++ engine (QNN runtime statically linked)
- `libc++_shared.so` — NDK C++ runtime (16 KB-aligned)

These are build outputs (gitignored). Rebuild with:

```
ANDROID_NDK_HOME=<ndk> cmake --preset android-arm64 \
  -DRAC_BACKEND_QHEXRT=ON -DQHEXRT_ROOT=<repo>/engines/qhexrt/prebuilt
cmake --build build/android-arm64 --target rac_backend_qhexrt_jni -j12
```

Then copy `librac_backend_qhexrt*.so` from `build/android-arm64/engines/qhexrt/`
into `src/main/jniLibs/arm64-v8a/`.

## Usage

```kotlin
import com.runanywhere.sdk.npu.qhexrt.QHexRT

val npu = QHexRT.probeNpu()
if (npu.qhexrt_supported) {
    QHexRT.register()
} else {
    // arch = npu.arch_name (e.g. "v73"); warn and use CPU engines
}

val request = RegisterModelFromUrlRequest(
    id = "qwen3_5_0_8b",
    name = "Qwen3.5 0.8B (HNPU)",
    url = "https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json",
    framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
)
val model = QHexRT.registerModelForDevice(request)
```

The app owns the request's URL and presentation metadata. QHexRT owns stable
product IDs, architecture/auth policy, and composes the shared native registry, Hugging Face
resolver, download, extraction, validation, and local-path workflow. `null`
means the definition is not eligible on the current device.

Once registered, inference flows through the regular SDK APIs; the C++ plugin
router selects QHexRT for QNN-context models by priority.
