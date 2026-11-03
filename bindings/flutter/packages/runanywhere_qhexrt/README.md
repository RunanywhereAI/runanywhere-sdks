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

## Explicit bundle registration

When registering a bundle URL through the core model-registration API with the QHexRT backend registered, Commons selects the device's architecture folder for logical references such as `https://huggingface.co/organization/model-repository/model.json` and includes the manifest's companion files.

A known architecture pin in the first repository folder, such as `/v79` or `/v79/model.json`, is checked before network resolution or registry changes. A mismatched pin returns `RAC_ERROR_INVALID_ARGUMENT` with a message naming the bundle and device architectures; a matching pin is kept unchanged. Probe failures and unsupported devices return the same errors as logical references.

Direct `/resolve/` or `/blob/` URLs register a single file and do not receive this bundle-folder check.

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
