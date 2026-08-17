# runanywhere_mlx

**Apple MLX backend for the RunAnywhere Flutter SDK** — on-device LLM, VLM, speech, and embeddings on physical iOS 17.5+ devices.

[![pub package](https://img.shields.io/pub/v/runanywhere_mlx.svg)](https://pub.dev/packages/runanywhere_mlx)

---

## Installation

```yaml
dependencies:
  runanywhere: 0.20.24
  runanywhere_mlx: 0.20.24
```

Requires Xcode 26+ and a physical iOS device for MLX execution. See the [Flutter SDK README](../../README.md) for Podfile setup.

---

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_mlx/runanywhere_mlx.dart';

final registered = await MLX.register(); // false on simulator / unsupported targets
if (registered) {
  await RunAnywhere.initialize();
  // Model registration, download, load, and inference via core RunAnywhere APIs
}
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
