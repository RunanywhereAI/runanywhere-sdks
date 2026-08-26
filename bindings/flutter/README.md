# RunAnywhere Flutter SDK

On-device AI for Flutter — run LLMs, speech-to-text, text-to-speech, and voice pipelines locally. Private, offline-capable, production-ready.

<p align="center">
  <img src="../../docs/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <a href="https://docs.runanywhere.ai/flutter/introduction"><img src="https://img.shields.io/badge/Docs-docs.runanywhere.ai-000000?style=flat-square" alt="Documentation" /></a>
  <a href="https://discord.gg/N359FBbDVd"><img src="https://img.shields.io/badge/Discord-Join-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Discord" /></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" /></a>
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.44+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.44+" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.12+-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart 3.12+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/iOS-17.5+-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17.5+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Android-API%2024+-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android API 24+" /></a>
</p>

---

## Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Flutter** | 3.44+ | 3.44.6 (see `pubspec.yaml`) |
| **Dart** | 3.12+ | 3.12.2 (workspace constraint) |
| **iOS** | 17.5+ | 17.5+ |
| **Android** | API 24 (7.0+) | API 28+ |
| **Xcode** | 26+ | 26+ |
| **RAM** | 2 GB | 4 GB+ for larger models |

ARM64 devices are recommended. Metal on iOS and NEON on Android provide significant speedups.

> **Platform setup:** iOS requires static CocoaPods linkage and microphone permissions for voice features. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for Podfile and manifest details.

---

## Installation

Add the packages you need to `pubspec.yaml`. Pin to **0.20.29**:

**Core + LlamaCpp (LLM):**

```yaml
dependencies:
  runanywhere: 0.20.29
  runanywhere_llamacpp: 0.20.29
```

**Core + ONNX (STT / TTS / VAD):**

```yaml
dependencies:
  runanywhere: 0.20.29
  runanywhere_onnx: 0.20.29
```

**Core + MLX (Apple LLM / VLM / speech on physical iOS devices):**

```yaml
dependencies:
  runanywhere: 0.20.29
  runanywhere_mlx: 0.20.29
```

**Optional NPU (Snapdragon Android):**

```yaml
  runanywhere_qhexrt: 0.20.29
```

Then run:

```bash
flutter pub get
cd ios && pod install && cd ..   # iOS only
```

| Package | Purpose |
|---------|---------|
| `runanywhere` | Core SDK — required |
| `runanywhere_llamacpp` | LLM / VLM (GGUF) |
| `runanywhere_onnx` | STT, TTS, VAD |
| `runanywhere_mlx` | Apple MLX |
| `runanywhere_qhexrt` | Qualcomm Hexagon NPU (optional) |

---

## Quick Start

The public API is **namespaced** — each capability is accessed via a static accessor on `RunAnywhere`:

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RunAnywhere.initialize();
  LlamaCpp.register();

  await RunAnywhere.downloadModel('smollm2-360m');
  await RunAnywhere.llm.load('smollm2-360m');

  final response = await RunAnywhere.llm.chat('What is the capital of France?');
  print(response);
}
```

For streaming, voice, vision, RAG, and tool calling, see the [documentation](https://docs.runanywhere.ai/flutter/introduction).

### Production initialization

```dart
await RunAnywhere.initialize(
  apiKey: '<YOUR_API_KEY>',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
);
```

---

## Capabilities

Register backend modules (`LlamaCpp`, `Onnx`, `Mlx`) before downloading or loading models.

| Accessor | Purpose | Example |
|----------|---------|---------|
| `RunAnywhere.llm` | Text generation | `llm.chat()`, `llm.generate()`, `llm.generateStream()` |
| `RunAnywhere.stt` | Speech-to-text | `stt.transcribe()`, `stt.transcribeStream()` |
| `RunAnywhere.tts` | Text-to-speech | `tts.synthesize()`, `tts.speak()` |
| `RunAnywhere.vad` | Voice activity detection | `vad.detectVoiceActivity()`, `vad.streamVAD()` |
| `RunAnywhere.vlm` | Vision-language | `vlm.processImage()` |
| `RunAnywhere.voice` | Voice agent pipeline | `voice.initializeWithLoadedModels()` |
| `RunAnywhere.models` | Model registry | `models.register()`, `models.available()` |
| `RunAnywhere.downloads` | Download lifecycle | `downloads.start()`, `downloads.delete()` |
| `RunAnywhere.rag` | Retrieval-augmented generation | `rag.query()` |
| `RunAnywhere.tools` | Tool / function calling | `tools.generateWithTools()` |

Flat aliases such as `RunAnywhere.downloadModel()` and `RunAnywhere.loadModel()` mirror the Swift/Kotlin/RN APIs for cross-platform parity.

### Supported model formats

| Format | Use case | Backend |
|--------|----------|---------|
| **GGUF** | LLM, some VLM | `runanywhere_llamacpp` |
| **ONNX / Sherpa archives** | STT, TTS, VAD | `runanywhere_onnx` |
| **MLX bundles** | LLM, VLM, speech on Apple silicon | `runanywhere_mlx` |
| **QHexRT bundles** | NPU models on Snapdragon | `runanywhere_qhexrt` |

Built-in catalog models (e.g. `smollm2-360m`) are discovered automatically — no manual registration required for catalog entries.

---

## Error Handling

Errors throw `SDKException` with a proto `ErrorCode`:

```dart
try {
  final result = await RunAnywhere.llm.generate(
    'Hello!',
    LLMGenerationOptions(maxTokens: 64),
  );
} on SDKException catch (error) {
  print('SDK error [${error.errorCode}]: ${error.message}');
}
```

---

## Documentation & Examples

| Resource | Link |
|----------|------|
| **Docs site** | [docs.runanywhere.ai/flutter/introduction](https://docs.runanywhere.ai/flutter/introduction) |
| **API reference** | [docs/Documentation.md](docs/Documentation.md) |
| **Example app** | [bindings/flutter/example/](../../bindings/flutter/example/) |
| **Contributing / platform setup** | [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) |

---

## FAQ

**Do I need an internet connection?**
Only for initial model download. Inference runs entirely on-device afterward.

**Is user data sent to the cloud?**
No. All inference is local. Production mode may collect anonymous telemetry (configurable).

**Can I use custom models?**
Yes — register GGUF, ONNX/Sherpa, or MLX bundles via `RunAnywhere.models.register()`.

**How do I test Apple MLX?**
MLX execution requires a physical arm64 iOS device. The simulator slice is for compile/link validation only.

---

## Support

- **Documentation:** [docs.runanywhere.ai](https://docs.runanywhere.ai)
- **Discord:** [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- **GitHub Issues:** [github.com/RunanywhereAI/runanywhere-sdks/issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email:** [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](../../LICENSE) for details.
