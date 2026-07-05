<p align="center">
  <img src="examples/logo.svg" alt="RunAnywhere Logo" width="140"/>
</p>

<h1 align="center">RunAnywhere</h1>

<p align="center">
  <strong>On-device AI for every platform.</strong><br/>
  Run LLMs, vision, speech-to-text, and text-to-speech locally. Private, offline, fast.<br/>
  One SDK for iOS, Android, Flutter, React Native, and Web, with Hexagon NPU acceleration on Snapdragon.
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App_Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on App Store" />
  </a>
  &nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://img.shields.io/badge/Google_Play-Download-34A853?style=for-the-badge&logo=google-play&logoColor=white" alt="Get it on Google Play" />
  </a>
</p>

<p align="center">
  <a href="https://github.com/RunanywhereAI/runanywhere-sdks/stargazers"><img src="https://img.shields.io/github/stars/RunanywhereAI/runanywhere-sdks?style=flat-square" alt="GitHub Stars" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square" alt="License" /></a>
  <a href="https://docs.runanywhere.ai"><img src="https://img.shields.io/badge/Docs-docs.runanywhere.ai-000000?style=flat-square" alt="Documentation" /></a>
  <a href="https://huggingface.co/runanywhere/models"><img src="https://img.shields.io/badge/Models-Hugging%20Face-FFD21E?style=flat-square" alt="Hugging Face Models" /></a>
  <a href="https://discord.gg/N359FBbDVd"><img src="https://img.shields.io/badge/Discord-Join-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Discord" /></a>
</p>

---

## What is RunAnywhere?

RunAnywhere lets you add AI features to your app that run entirely on-device, with no cloud, no latency, and no data leaving the device:

- **LLM Chat**: Llama, Qwen, Gemma, Phi, LFM, Mistral, and more
- **Vision (VLM)**: image understanding and captioning
- **Speech-to-Text**: Whisper- and Moonshine-based transcription
- **Text-to-Speech**: neural voice synthesis
- **Voice Assistant**: a full speech-to-text, LLM, and text-to-speech pipeline

One API spans iOS, Android, Flutter, React Native, and Web, and routes to the best engine on each device: Core ML on Apple, WebGPU in the browser, llama.cpp everywhere as a fallback, and the Hexagon NPU on Snapdragon.

---

## Hexagon NPU acceleration (QHexRT)

QHexRT is RunAnywhere's inference runtime for the Qualcomm Hexagon NPU. It runs LLM, vision, speech, and text-to-speech models directly on the Snapdragon NPU (Hexagon v79 / v81) and ships as a built-in accelerator: your app calls the same `loadModel` and `generate`, and it uses the NPU automatically on supported devices.

- Runs LLM, VLM, speech-to-text, and text-to-speech on the NPU, including text-to-speech, which other runtimes run on the CPU.
- Runs Mixture-of-Experts and hybrid-attention models on the NPU (Phi-tiny-MoE, Qwen3.5).
- Fast prefill and low time-to-first-token, with context that extends past the compiled window.
- Prebuilt model bundles published on [Hugging Face](https://huggingface.co/runanywhere/models); the SDK downloads the one matching the device.

Measured on a Samsung Galaxy S25 (Snapdragon 8 Elite, Hexagon v79):

| Model | Task | Params | Decode | Time to first token |
|---|---|---|---|---|
| LFM2.5-230M | LLM | 0.23 B | 164 tok/s | 32 ms |
| Qwen3-0.6B | LLM | 0.6 B | 33 tok/s (prefill up to 3,692 tok/s) | 127 ms |
| Llama-3.2-1B | LLM | 1.2 B | 16.3 tok/s | 56 ms |
| Phi-tiny-MoE | MoE LLM | 3.8 B (1.1 B active) | 5-7 tok/s | ~2.5 s |
| InternVL3.5-1B | VLM | 1 B | 37 tok/s | 290 ms |
| Whisper base | ASR | 74 M | ~5x real-time | n/a |
| MeloTTS-EN | TTS | n/a | ~4.5x real-time | n/a |

Available on the Kotlin, Flutter, and React Native SDKs. Snapdragon (Android arm64) only.

---

## See It In Action

<div align="center">
<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/gifs/text-generation.gif" alt="Text Generation" width="240"/><br/><br/>
      <strong>Text Generation</strong><br/>
      <sub>LLM inference, 100% on-device</sub>
    </td>
    <td width="40"></td>
    <td align="center" width="50%">
      <img src="docs/gifs/voice-ai.gif" alt="Voice AI" width="240"/><br/><br/>
      <strong>Voice AI</strong><br/>
      <sub>STT to LLM to TTS pipeline, fully offline</sub>
    </td>
  </tr>
  <tr><td colspan="3" height="30"></td></tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/gifs/image-generation.gif" alt="Image Generation" width="240"/><br/><br/>
      <strong>Image Generation</strong><br/>
      <sub>On-device diffusion model</sub>
    </td>
    <td width="40"></td>
    <td align="center" width="50%">
      <img src="docs/gifs/visual-language-model.gif" alt="Visual Language Model" width="240"/><br/><br/>
      <strong>Visual Language Model</strong><br/>
      <sub>Vision + language understanding on-device</sub>
    </td>
  </tr>
</table>
</div>

---

## SDKs

| Platform | Status | Installation | Documentation | NPU |
|----------|--------|--------------|---------------|:---:|
| **Swift** (iOS/macOS) | Stable | [Swift Package Manager](#swift-ios--macos) | [docs.runanywhere.ai/swift](https://docs.runanywhere.ai/swift/introduction) | n/a |
| **Kotlin** (Android) | Stable | [Gradle](#kotlin-android) | [docs.runanywhere.ai/kotlin](https://docs.runanywhere.ai/kotlin/introduction) | Yes |
| **Web** (Browser) | Beta | [npm](#web-browser) | [SDK README](sdk/runanywhere-web/) | n/a |
| **React Native** | Beta | [npm](#react-native) | [docs.runanywhere.ai/react-native](https://docs.runanywhere.ai/react-native/introduction) | Yes |
| **Flutter** | Beta | [pub.dev](#flutter) | [docs.runanywhere.ai/flutter](https://docs.runanywhere.ai/flutter/introduction) | Yes |

---

## Quick Start

### Swift (iOS / macOS)

```swift
import RunAnywhere
import LlamaCPPRuntime

// 1. Initialize
LlamaCPP.register()
try RunAnywhere.initialize()

// 2. Load a model
var load = RAModelLoadRequest()
load.modelID = "smollm2-360m"
load.category = .language
load.framework = .llamaCpp
_ = await RunAnywhere.loadModel(load)

// 3. Generate
var req = RALLMGenerateRequest()
req.prompt = "What is the capital of France?"
let result = try await RunAnywhere.generate(req)
print(result.text) // "Paris is the capital of France."
```

**Install via Swift Package Manager:**

```
https://github.com/RunanywhereAI/runanywhere-sdks
```

[Documentation](https://docs.runanywhere.ai/swift/introduction) · [Source code](sdk/runanywhere-swift/)

---

### Kotlin (Android)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*

// 1. Initialize
LlamaCPP.register()
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

// 2. Load a model
RunAnywhere.downloadModel("smollm2-360m").collect { println("${it.progress * 100}%") }
RunAnywhere.loadLLMModel("smollm2-360m")

// 3. Generate
val response = RunAnywhere.chat("What is the capital of France?")
println(response) // "Paris is the capital of France."
```

**Install via Gradle:**

```kotlin
dependencies {
    implementation("com.runanywhere.sdk:runanywhere-kotlin:0.16.1")
    implementation("com.runanywhere.sdk:runanywhere-core-llamacpp:0.16.1")
}
```

[Documentation](https://docs.runanywhere.ai/kotlin/introduction) · [Source code](sdk/runanywhere-kotlin/)

---

### React Native

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';

// 1. Initialize
await RunAnywhere.initialize({ environment: SDKEnvironment.Development });
LlamaCPP.register();

// 2. Load a model
await RunAnywhere.downloadModel('smollm2-360m');
await RunAnywhere.loadModel('smollm2-360m');

// 3. Generate
const response = await RunAnywhere.chat('What is the capital of France?');
console.log(response); // "Paris is the capital of France."
```

**Install via npm:**

```bash
npm install @runanywhere/core @runanywhere/llamacpp
```

[Documentation](https://docs.runanywhere.ai/react-native/introduction) · [Source code](sdk/runanywhere-react-native/)

---

### Flutter

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

// 1. Initialize
await RunAnywhere.initialize();
await LlamaCpp.register();

// 2. Load a model
await RunAnywhere.downloadModel('smollm2-360m');
await RunAnywhere.loadModel('smollm2-360m');

// 3. Generate
final response = await RunAnywhere.chat('What is the capital of France?');
print(response); // "Paris is the capital of France."
```

**Install via pub.dev:**

```yaml
dependencies:
  runanywhere: ^0.16.0
  runanywhere_llamacpp: ^0.16.0  # LLM text generation
  # runanywhere_onnx: ^0.16.0   # Add this if you need STT, TTS, or Voice features
```

[Documentation](https://docs.runanywhere.ai/flutter/introduction) · [Source code](sdk/runanywhere-flutter/)

---

### Web (Browser)

```typescript
import { RunAnywhere } from '@runanywhere/web';

// 1. Initialize
await RunAnywhere.initialize({ environment: 'development' });

// 2. Load a model
await RunAnywhere.loadModel({
  id: 'qwen2.5-0.5b',
  source: '/models/qwen2.5-0.5b-instruct-q4_0.gguf',
});

// 3. Generate
const result = await RunAnywhere.generate({
  prompt: 'What is the capital of France?',
});
console.log(result.text); // "Paris is the capital of France."
```

**Install via npm:**

```bash
npm install @runanywhere/web
```

[Source code](sdk/runanywhere-web/)

---

## Features

| Feature | iOS | Android | Web | React Native | Flutter |
|---------|:-:|:-:|:-:|:-:|:-:|
| LLM Text Generation | Yes | Yes | Yes | Yes | Yes |
| Streaming | Yes | Yes | Yes | Yes | Yes |
| Speech-to-Text | Yes | Yes | Yes | Yes | Yes |
| Text-to-Speech | Yes | Yes | Yes | Yes | Yes |
| Voice Assistant Pipeline | Yes | Yes | Yes | Yes | Yes |
| Vision Language Models | Yes | Yes | Yes | n/a | Yes |
| Hexagon NPU (QHexRT) | n/a | Yes | n/a | Yes | Yes |
| Model Download + Progress | Yes | Yes | Yes | Yes | Yes |
| Structured Output (JSON) | Yes | Yes | Yes | Soon | Soon |
| Tool Calling | Yes | Yes | Yes | n/a | n/a |
| Embeddings | n/a | n/a | Yes | n/a | n/a |
| Apple Foundation Models | Yes | n/a | n/a | n/a | n/a |

---

## Supported Models

### Hexagon NPU (QHexRT)

Prebuilt bundles published on [Hugging Face](https://huggingface.co/runanywhere/models); the SDK downloads the one matching the device.

| Model | Task | Params | Bundle |
|---|---|---|---|
| Llama-3.2-1B | LLM | 1.2 B | [llama3_2_1b_HNPU](https://huggingface.co/runanywhere/llama3_2_1b_HNPU) |
| LFM2.5-230M / 350M | LLM | 0.23 / 0.35 B | [lfm2_5_230m_HNPU](https://huggingface.co/runanywhere/lfm2_5_230m_HNPU) · [lfm2_5_350m_HNPU](https://huggingface.co/runanywhere/lfm2_5_350m_HNPU) |
| Qwen3.5-0.8B / 2B / 4B | LLM | 0.8-4 B | [qwen3_5_0_8b_HNPU](https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU) · [2b](https://huggingface.co/runanywhere/qwen3_5_2b_HNPU) · [4b](https://huggingface.co/runanywhere/qwen3_5_4b_HNPU) |
| Gemma-4-E2B / E4B | LLM + VLM | ~2 / 4 B | [gemma4_e2b_HNPU](https://huggingface.co/runanywhere/gemma4_e2b_HNPU) · [gemma4_e4b_HNPU](https://huggingface.co/runanywhere/gemma4_e4b_HNPU) |
| Phi-tiny-MoE | MoE LLM | 3.8 B | [phi_tiny_moe_HNPU](https://huggingface.co/runanywhere/phi_tiny_moe_HNPU) |
| DeepSeek-R1-Distill-Qwen | LLM | 1.5 / 7 B | [1.5b](https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_1_5b_HNPU) · [7b](https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_7b_HNPU) |
| Qwen3-VL-2B | VLM | 2 B | [qwen3_vl_HNPU](https://huggingface.co/runanywhere/qwen3_vl_HNPU) |
| InternVL3.5-1B | VLM | 1 B | [internvl3_5_1b_HNPU](https://huggingface.co/runanywhere/internvl3_5_1b_HNPU) |
| Whisper base / small | ASR | 74 / 244 M | [whisper_base_HNPU](https://huggingface.co/runanywhere/whisper_base_HNPU) · [whisper_small_HNPU](https://huggingface.co/runanywhere/whisper_small_HNPU) |
| Moonshine tiny / base | ASR | n/a | [moonshine_base_HNPU](https://huggingface.co/runanywhere/moonshine_base_HNPU) |
| MeloTTS-EN | TTS | n/a | [melotts_en_HNPU](https://huggingface.co/runanywhere/melotts_en_HNPU) |
| EmbeddingGemma-300M | Embeddings | 300 M | [embeddinggemma_300m_HNPU](https://huggingface.co/runanywhere/embeddinggemma_300m_HNPU) |

[Browse all models on Hugging Face](https://huggingface.co/runanywhere/models)

### Cross-platform (GGUF / ONNX)

| Type | Models | Runtime |
|---|---|---|
| LLM | SmolLM2, Qwen 2.5, Llama 3.2, Mistral 7B | llama.cpp |
| Speech-to-Text | Whisper Tiny / Base | ONNX |
| Text-to-Speech | Piper (US / UK English) | ONNX |

---

## Sample Apps

| Platform | Source | Download |
|----------|--------|----------|
| iOS | [examples/ios/RunAnywhereAI](examples/ios/RunAnywhereAI/) | [App Store](https://apps.apple.com/us/app/runanywhere/id6756506307) |
| Android | [examples/android/RunAnywhereAI](examples/android/RunAnywhereAI/) | [Google Play](https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai) |
| Web | [examples/web/RunAnywhereAI](examples/web/RunAnywhereAI/) | Build from source |
| React Native | [examples/react-native/RunAnywhereAI](examples/react-native/RunAnywhereAI/) | Build from source |
| Flutter | [examples/flutter/RunAnywhereAI](examples/flutter/RunAnywhereAI/) | Build from source |

The Android, Flutter, and React Native apps include an NPU section that detects the device's Hexagon arch and runs LLM, vision, speech, and text-to-speech on the NPU.

---

## Starter Examples

Minimal projects to get up and running on each platform:

| Platform | Repository |
|----------|------------|
| Kotlin (Android) | [kotlin-starter-example](https://github.com/RunanywhereAI/kotlin-starter-example) |
| Swift (iOS) | [swift-starter-example](https://github.com/RunanywhereAI/swift-starter-example) |
| Flutter | [flutter-starter-example](https://github.com/RunanywhereAI/flutter-starter-example) |
| React Native | [react-native-starter-app](https://github.com/RunanywhereAI/react-native-starter-app) |

---

## Playground

Real-world projects built with RunAnywhere. Each ships as a standalone app you can build and run.

- **[Android Use Agent](Playground/android-use-agent/)**: an on-device autonomous Android agent that reads the screen and controls the phone with an on-device LLM. [Benchmarks](Playground/android-use-agent/ASSESSMENT.md).
- **[On-Device Browser Agent](Playground/on-device-browser-agent/)**: a Chrome extension that automates browser tasks on-device with WebLLM and WebGPU.
- **[Swift Starter App](Playground/swift-starter-app/)**: a SwiftUI app with LLM chat, speech-to-text, text-to-speech, and a full voice pipeline.
- **[Linux Voice Assistant](Playground/linux-voice-assistant/)**: an on-device voice pipeline (wake word, VAD, STT, LLM, TTS) in one C++ binary for Raspberry Pi 5, x86_64, and ARM64.
- **[OpenClaw Hybrid Assistant](Playground/openclaw-hybrid-assistant/)**: on-device wake word, VAD, STT, and TTS with cloud LLM reasoning and barge-in.

---

## Architecture

A single C/C++ core (`runanywhere-commons`) behind a C ABI, with thin platform SDKs on top and a plugin registry that selects the best engine per device (llama.cpp, ONNX/sherpa, Core ML, Metal, and QHexRT on the Hexagon NPU). Business logic lives in the core, so one fix lands on all five SDKs.

```
runanywhere-sdks/
├── sdk/
│   ├── runanywhere-swift/          # iOS/macOS SDK
│   ├── runanywhere-kotlin/         # Android SDK
│   ├── runanywhere-web/            # Web SDK (WebAssembly / WebGPU)
│   ├── runanywhere-react-native/   # React Native SDK
│   ├── runanywhere-flutter/        # Flutter SDK
│   └── runanywhere-commons/        # Shared C/C++ core
│
├── engines/                        # Pluggable inference backends
├── examples/                       # Sample apps
├── Playground/                     # Real-world reference apps
└── docs/                           # Documentation
```

---

## Requirements

| Platform | Minimum | Recommended |
|----------|---------|-------------|
| iOS | 17.0+ | 17.0+ |
| macOS | 14.0+ | 14.0+ |
| Android | API 24 (7.0) | API 28+ |
| Web | Chrome 96+ / Edge 96+ | Chrome 120+ |
| React Native | 0.74+ | 0.76+ |
| Flutter | 3.10+ | 3.24+ |

Hexagon NPU: Snapdragon with Hexagon v79 / v81 (Snapdragon 8 Elite class), Android arm64.
Memory: 2 GB minimum, 4 GB+ recommended for larger models.

---

## Contributing

We welcome contributions. See our [Contributing Guide](CONTRIBUTING.md) for details.

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks

# Build the native XCFrameworks into sdk/runanywhere-swift/Binaries/.
# Required for local Swift development.
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh

# Run the iOS sample app
cd examples/ios/RunAnywhereAI
open RunAnywhereAI.xcodeproj
```

---

## Support

- Docs: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [Join our community](https://discord.gg/N359FBbDVd)
- Issues: [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- Email: founders@runanywhere.ai
- Twitter: [@RunanywhereAI](https://twitter.com/RunanywhereAI)

---

## License

Apache 2.0. See [LICENSE](LICENSE) for details.
