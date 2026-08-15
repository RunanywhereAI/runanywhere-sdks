# runanywhere_onnx

**ONNX/Sherpa backend for the RunAnywhere Flutter SDK** — on-device STT, TTS, and VAD on iOS and Android.

[![pub package](https://img.shields.io/pub/v/runanywhere_onnx.svg)](https://pub.dev/packages/runanywhere_onnx)

---

## Installation

```yaml
dependencies:
  runanywhere: 0.20.22
  runanywhere_onnx: 0.20.22
```

Platform setup (Podfile, microphone permissions) is documented in the [Flutter SDK README](../../README.md).

---

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

await RunAnywhere.initialize();
await Onnx.register();

// Register, download, load models and transcribe via core RunAnywhere APIs
final result = await RunAnywhere.stt.transcribe(audioData);
print(result.text);
```

See the [Flutter SDK README](../../README.md) for full examples.

---

## Support

- [Flutter SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
