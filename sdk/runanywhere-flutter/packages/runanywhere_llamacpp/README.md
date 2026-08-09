# runanywhere_llamacpp

**Llama.cpp LLM backend for the RunAnywhere Flutter SDK** — GGUF text generation on iOS and Android.

[![pub package](https://img.shields.io/pub/v/runanywhere_llamacpp.svg)](https://pub.dev/packages/runanywhere_llamacpp)

---

## Installation

```yaml
dependencies:
  runanywhere: 0.20.14
  runanywhere_llamacpp: 0.20.14
```

Platform setup (Podfile, permissions) is documented in the [Flutter SDK README](../../README.md).

---

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

await RunAnywhere.initialize();
await LlamaCpp.register();

// Register, download, load models and generate via core RunAnywhere APIs
final result = await RunAnywhere.llm.generate(
  'Hello!',
  LLMGenerationOptions(maxTokens: 64),
);
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
