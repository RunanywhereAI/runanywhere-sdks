# runanywhere-core-qhexrt

Private QHexRT backend for the RunAnywhere Kotlin SDK. Runs prebuilt QNN context
binaries on Qualcomm Snapdragon Hexagon NPUs (v79/v81), serving LLM, VLM, STT and
TTS through the standard SDK APIs.

Android only, `arm64-v8a` only. On non-v79/v81 devices the backend declines to
register and the SDK falls back to CPU engines.

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
if (npu.supported) {
    QHexRT.register()
} else {
    // arch = npu.arch (e.g. "v73"); warn and use CPU engines
}
```

Once registered, inference flows through the regular SDK APIs; the C++ plugin
router selects QHexRT for QNN-context models by priority.
