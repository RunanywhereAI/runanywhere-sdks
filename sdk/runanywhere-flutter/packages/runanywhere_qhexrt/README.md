# runanywhere_qhexrt

Private QHexRT backend for the RunAnywhere Flutter SDK — runs prebuilt QNN
context binaries on Qualcomm Snapdragon Hexagon NPUs (v79/v81), serving LLM,
VLM, STT and TTS through the standard SDK APIs.

Android only, `arm64-v8a` only. On non-v79/v81 devices the backend declines to
register and inference stays disabled (NPU-only — no CPU fallback in this
package).

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

await RunAnywhere.initialize();

final npu = QHexRT.probeNpu();      // pre-flight, no QNN load
if (npu.supported) {
  await QHexRT.register();          // registers the QHexRT engine
}
```

## Native libraries

`android/src/main/jniLibs/arm64-v8a/` bundles `librac_backend_qhexrt.so`
(QHexRT engine, QNN runtime statically linked) + `libc++_shared.so`.
`librac_commons.so` is provided by the core `runanywhere` plugin.
