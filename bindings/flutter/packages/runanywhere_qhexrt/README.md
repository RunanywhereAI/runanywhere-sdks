# runanywhere_qhexrt

**Qualcomm Hexagon NPU backend for the RunAnywhere Flutter SDK** — on-device LLM, VLM, STT, and TTS on Snapdragon V75/V79/V81 NPUs. Android `arm64-v8a` only.

[![pub package](https://img.shields.io/pub/v/runanywhere_qhexrt.svg)](https://pub.dev/packages/runanywhere_qhexrt)

---

## Installation

```yaml
dependencies:
  runanywhere: 0.20.37
  runanywhere_qhexrt: 0.20.37
```

See the [Flutter SDK README](../../README.md) for Android setup.

The examples below target this source tree (SDK `0.20.37`). For changes not yet
released, use local SDK packages and native libraries built from the same
checkout; a matching version number alone does not include unreleased changes.

---

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_qhexrt/qhexrt.dart';

await RunAnywhere.initialize();

final npu = QHexRT.probeNpu(); // safe on any device
if (npu.supported && await QHexRT.register()) {
  await RunAnywhere.models.register(
    ModelRegistration.url(
      id: 'my-qhexrt-model',
      name: 'My QHexRT Model',
      url: 'https://huggingface.co/organization/dedicated-qhexrt-model/model.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    ),
  );
  // Download, load, and infer via core RunAnywhere APIs.
}
```

See the [Flutter SDK README](../../README.md) for full examples.

The URL above is a logical bundle reference: Commons selects the device's architecture folder and registers the manifest with its companion files. A direct `/resolve/main/model.json` URL registers only that file. Explicitly pinned bundle references are preserved as supplied; registration does not reject a pin for a different device architecture. Before registration, compare each pinned bundle's required architecture with `QHexRT.probeNpu()` and skip incompatible rows. Catalog eligibility and any required HF-auth preflight are application-owned.

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
