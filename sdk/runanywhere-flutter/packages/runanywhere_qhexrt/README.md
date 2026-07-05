# runanywhere_qhexrt

Private QHexRT backend for the RunAnywhere Flutter SDK — runs prebuilt QNN
context binaries on Qualcomm Snapdragon Hexagon NPUs (v75+), serving
LLM, VLM, STT and TTS through the standard SDK APIs.

Android only, `arm64-v8a` only. On parts older than v75, the backend
declines to register and inference stays disabled (NPU-only — no CPU fallback
in this package).

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

await RunAnywhere.initialize();

final npu = QHexRT.probeNpu();      // pre-flight, no QNN load
if (npu.qhexrtSupported) {          // generated runanywhere.v1.NpuCapability
  await QHexRT.register();          // registers the QHexRT engine
}
```

`probeNpu()` returns the generated `runanywhere.v1.NpuCapability` proto
message (`socModel`, `socId`, `hexagonArch`, `qhexrtSupported`, `archName`),
decoded from commons' `rac_npu_probe_proto()` — no hand-mirrored types.

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
