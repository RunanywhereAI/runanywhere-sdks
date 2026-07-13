# runanywhere_qhexrt

On-device NPU acceleration backend for the RunAnywhere Flutter SDK. Runs LLM, VLM, STT and TTS entirely on-device on Qualcomm Snapdragon Hexagon NPUs (V75 / V79 / V81). Android `arm64-v8a` only.

## Install
```yaml
dependencies:
  runanywhere_qhexrt: ^0.20.9
```

## Use
Register the backend, then use the standard RunAnywhere APIs — the SDK automatically routes supported models to the NPU.

```dart
import 'package:runanywhere_qhexrt/qhexrt.dart';

final npu = QHexRT.probeNpu(); // pre-flight capability probe, safe on any device
```

## Requirements
- Android `arm64-v8a`
- A Qualcomm Snapdragon device with a Hexagon V75 / V79 / V81 NPU

## License
Proprietary. See `LICENSE`.
