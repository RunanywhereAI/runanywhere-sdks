# runanywhere_qhexrt

Private QHexRT backend for the RunAnywhere Flutter SDK — runs prebuilt QNN
context binaries on Qualcomm Snapdragon Hexagon NPUs (V75/V79/V81), serving
LLM, VLM, STT and TTS through the standard SDK APIs.

Android only, `arm64-v8a` only. Other architectures are declined and inference
stays disabled (NPU-only — no CPU fallback in this package).

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

await RunAnywhere.initialize();

final npu = QHexRT.probeNpu();      // pre-flight, no QNN load
if (npu.qhexrtSupported) {          // generated runanywhere.v1.NpuCapability
  await QHexRT.register();          // registers the QHexRT engine
}

final model = await QHexRT.registerModelForDevice(
  request: RegisterModelFromUrlRequest(
    id: 'qwen3_5_0_8b',
    name: 'Qwen3.5 0.8B (HNPU)',
    url: 'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
  ),
);
```

`probeNpu()` returns the generated `runanywhere.v1.NpuCapability` proto
message (`socModel`, `socId`, `hexagonArch`, `qhexrtSupported`, `archName`),
decoded from QHexRT's `rac_qhexrt_probe_proto()` — no hand-mirrored types.
The app owns URLs and presentation metadata. QHexRT owns stable product IDs,
per-model architecture/auth policy, chip selection, and
composes commons' registry, Hugging Face resolver, download, extraction,
validation, and local-path workflow. A null model is a normal device mismatch.

## Native libraries

The private QHexRT natives are **staged, not committed**. Android host/stub
libraries go under `android/src/main/jniLibs/arm64-v8a/`; DSP `Skel.so` files
go under `android/src/main/assets/runanywhere/qhexrt/skels/arm64-v8a/` and are
extracted to an app-private, versioned directory before QHexRT registration:

```bash
scripts/stage-natives.sh --natives-from /path/to/android-libs
```

The script copies `librac_backend_qhexrt*.so` (QHexRT engine), the QAIRT
runtime set (`libQnnHtp*.so`, `libQnnSystem.so`, per-arch v75/v79/v81
Skel/Stub/CalculatorStub) and `libc++_shared.so`. Skels are deliberately not
Android JNI libraries: FastRPC discovers the extracted private directory via
QHexRT's `rac_qhexrt_set_skel_directory()` contract.
`librac_commons.so` is provided by the core `runanywhere` plugin.

Building without staged natives is allowed (the Gradle build prints a
warning): the plugin then behaves as a stub and reports the NPU as
unavailable at runtime.
