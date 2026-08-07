# runanywhere_qhexrt

**Qualcomm Hexagon NPU backend for the RunAnywhere Flutter SDK** — on-device LLM, VLM, STT, and TTS on Snapdragon V75/V79/V81 NPUs. Android `arm64-v8a` only.

[![pub package](https://img.shields.io/pub/v/runanywhere_qhexrt.svg)](https://pub.dev/packages/runanywhere_qhexrt)

---

## Installation

```yaml
dependencies:
  runanywhere: 0.20.11
  runanywhere_qhexrt: 0.20.11
```

See the [Flutter SDK README](../../README.md) for Android setup.

---

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_qhexrt/qhexrt.dart';

await RunAnywhere.initialize();

final npu = QHexRT.probeNpu(); // safe on any device
if (npu.supported) {
  await QHexRT.register();
}
// Register, download, load, and infer via core RunAnywhere APIs
```

See the [Flutter SDK README](../../README.md) for full examples.

---

## Requirements

- Android `arm64-v8a`
- Qualcomm Snapdragon device with Hexagon V75, V79, or V81 NPU

---

## Support

- [Flutter SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

Proprietary. See [LICENSE](LICENSE).
