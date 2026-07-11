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
    id: 'my-hnpu-model',
    name: 'My HNPU Model',
    url: 'https://huggingface.co/your-org/your-model_HNPU/model.json',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
  ),
  supportedArches: const [
    HexagonArch.HEXAGON_ARCH_V79,
    HexagonArch.HEXAGON_ARCH_V81,
  ],
);
```

`probeNpu()` returns the generated `runanywhere.v1.NpuCapability` proto
message (`socModel`, `socId`, `hexagonArch`, `qhexrtSupported`, `archName`),
decoded from QHexRT's `rac_qhexrt_probe_proto()` — no hand-mirrored types.
The app owns URLs and presentation metadata. QHexRT owns chip selection and
composes commons' registry, Hugging Face resolver, download, extraction,
validation, and local-path workflow. A null model is a normal device mismatch.

## Native libraries

The private QHexRT natives are **staged, not committed**: the
`android/src/main/jniLibs/arm64-v8a/` directory is gitignored and must be
populated before a real (non-stub) build:

```bash
scripts/stage-natives.sh --natives-from /path/to/android-libs
```

The script copies `librac_backend_qhexrt*.so` (QHexRT engine), the QAIRT
runtime/skel set (`libQnnHtp*.so`, `libQnnSystem.so`, per-arch
v75/v79/v81 Skel/Stub/CalculatorStub) and `libc++_shared.so` — the same set
the React Native `package-sdk.sh` stages for its qhexrt package.
`librac_commons.so` is provided by the core `runanywhere` plugin.

Building without staged natives is allowed (the Gradle build prints a
warning): the plugin then behaves as a stub and reports the NPU as
unavailable at runtime.
