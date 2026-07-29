# RunAnywhere React Native SDK

On-device AI for React Native — run LLMs, speech-to-text, text-to-speech, and voice pipelines locally. Private, offline-capable, production-ready.

<p align="center">
  <a href="https://docs.runanywhere.ai/react-native/introduction"><img src="https://img.shields.io/badge/Docs-docs.runanywhere.ai-000000?style=flat-square" alt="Documentation" /></a>
  <a href="https://discord.gg/N359FBbDVd"><img src="https://img.shields.io/badge/Discord-Join-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Discord" /></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" /></a>
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/React%20Native-0.83.1+-61DAFB?style=flat-square&logo=react&logoColor=white" alt="React Native 0.83.1+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Node.js-22.12+-339933?style=flat-square&logo=nodedotjs&logoColor=white" alt="Node.js 22.12+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/iOS-17.5+-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17.5+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Android-API%2024+-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android API 24+" /></a>
</p>

---

## Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **React Native** | 0.83.1+ | 0.85.3 |
| **Node.js** | 22.12+ | 24 LTS |
| **iOS** | 17.5+ | 17.5+ |
| **Android** | API 24 (7.0+) | API 28+ |
| **Xcode** | 26+ | 26+ |
| **RAM** | 3 GB | 6 GB+ for larger models |

Apple Silicon devices and Android phones with 6 GB+ RAM are recommended for 3B+ models.

---

## Installation

Install the core package plus the backends you need. Pin to **0.20.11**:

```bash
npm install @runanywhere/core@0.20.11 @runanywhere/llamacpp@0.20.11
```

| Package | Purpose |
|---------|---------|
| `@runanywhere/core` | Core SDK — required |
| `@runanywhere/llamacpp` | LLM / VLM (GGUF via llama.cpp) |
| `@runanywhere/onnx` | STT, TTS, VAD (Whisper, Piper, Silero) |
| `@runanywhere/mlx` | Apple MLX on physical iOS devices |
| `@runanywhere/qhexrt` | Optional Qualcomm Hexagon NPU acceleration (Snapdragon Android) |

**iOS:** run `cd ios && pod install && cd ..` after installing packages.

**Android:** no extra setup — native libraries are bundled and downloaded during the Gradle build.

---

## Quick Start

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});

await LlamaCPP.register();

await RunAnywhere.downloadModel('smollm2-360m');
await RunAnywhere.loadModel('smollm2-360m');

const result = await RunAnywhere.generate('What is the capital of France?');
console.log(result.text);
```

For streaming tokens, voice (STT/TTS), vision, RAG, and tool calling, see the [documentation](https://docs.runanywhere.ai/react-native/introduction).

### Production initialization

```typescript
await RunAnywhere.initialize({
  apiKey: '<YOUR_API_KEY>',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
});
```

| Environment | Description |
|-------------|-------------|
| `SDK_ENVIRONMENT_DEVELOPMENT` | Keyless OSS mode, verbose logging |
| `SDK_ENVIRONMENT_STAGING` | Testing with real services |
| `SDK_ENVIRONMENT_PRODUCTION` | Authenticated control plane, telemetry |

---

## Capabilities

The SDK exposes a unified `RunAnywhere` namespace. Register backend modules (`LlamaCPP`, `ONNX`, `MLX`) before downloading or loading models.

| Capability | Key APIs | Backend package |
|------------|----------|-----------------|
| **LLM** | `generate`, `generateStream` | `@runanywhere/llamacpp`, `@runanywhere/mlx` |
| **VLM** | `processImage`, `processImageStream` | `@runanywhere/llamacpp`, `@runanywhere/mlx` |
| **STT** | `transcribe`, `transcribeStream` | `@runanywhere/onnx` |
| **TTS** | `synthesize`, `synthesizeStream` | `@runanywhere/onnx` |
| **VAD** | Voice activity detection helpers | `@runanywhere/onnx` |
| **Voice agent** | `initializeVoiceAgent`, `streamVoiceAgent`, `processVoiceTurn` | Core + ONNX + LLM backend |
| **Models** | `registerModel`, `downloadModel`, `loadModel`, `listModels` | `@runanywhere/core` |
| **RAG / tools** | `ragQuery`, `generateWithTools` | `@runanywhere/core` |

### Supported model formats

| Format | Use case | Backend |
|--------|----------|---------|
| **GGUF** | LLM, some VLM | LlamaCPP |
| **ONNX / Sherpa archives** | STT, TTS, VAD | ONNX |
| **MLX bundles** | LLM, VLM, speech on Apple silicon | MLX |
| **QHexRT bundles** | NPU-accelerated models on Snapdragon | QHexRT |

Built-in catalog models (e.g. `smollm2-360m`) are discovered automatically after initialization — no manual `registerModel` call required for catalog entries.

---

## Error Handling

Errors throw `SDKException` with a proto `ErrorCode`:

```typescript
import { SDKException, ErrorCode, isSDKException } from '@runanywhere/core';

try {
  await RunAnywhere.generate('Hello!');
} catch (error) {
  if (isSDKException(error)) {
    console.error(error.code, error.message);
  }
}
```

---

## Documentation & Examples

| Resource | Link |
|----------|------|
| **Docs site** | [docs.runanywhere.ai/react-native/introduction](https://docs.runanywhere.ai/react-native/introduction) |
| **API reference** | [Docs/Documentation.md](Docs/Documentation.md) |
| **Example app** | [examples/react-native/RunAnywhereAI/](../../examples/react-native/RunAnywhereAI/) |
| **Contributing / building from source** | [Docs/DEVELOPMENT.md](Docs/DEVELOPMENT.md) |

---

## FAQ

**Do I need an internet connection?**  
Only for initial model download. Inference runs entirely on-device afterward.

**Is user data sent to the cloud?**  
No. All inference is local. Production mode may collect anonymous telemetry (configurable).

**Can I use custom models?**  
Yes — register any compatible GGUF, ONNX/Sherpa, or MLX bundle via `RunAnywhere.registerModel()`.

---

## Support

- **Documentation:** [docs.runanywhere.ai](https://docs.runanywhere.ai)
- **Discord:** [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- **GitHub Issues:** [github.com/RunanywhereAI/runanywhere-sdks/issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email:** [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](../../LICENSE) for details.
