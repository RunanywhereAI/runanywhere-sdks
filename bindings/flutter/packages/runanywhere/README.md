# runanywhere

**Core Flutter SDK for RunAnywhere** — privacy-first, on-device AI (LLM, STT, TTS, voice, and model lifecycle).

[![pub package](https://img.shields.io/pub/v/runanywhere.svg)](https://pub.dev/packages/runanywhere)

---

## Installation

```yaml
dependencies:
  runanywhere: 0.20.19
```

Add backend packages as needed (`runanywhere_llamacpp`, `runanywhere_onnx`, etc.). See the [Flutter SDK README](../../README.md) for iOS Podfile, Android permissions, and platform setup.

---

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RunAnywhere.initialize();
  runApp(MyApp());
}
```

For backends, model registration, downloads, and inference examples, see the [Flutter SDK README](../../README.md).

---

## Support

- [Flutter SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
