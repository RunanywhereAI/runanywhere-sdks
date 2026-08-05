# RunAnywhere AI — iOS Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App%20Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2017.5%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17.5+" />
  <img src="https://img.shields.io/badge/Platform-macOS%2014.5%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14.5+" />
  <img src="https://img.shields.io/badge/Swift-6.2%2B-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.2+" />
  <img src="https://img.shields.io/badge/Xcode-26%2B-147EFB?style=flat-square&logo=xcode&logoColor=white" alt="Xcode 26+" />
  <img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" />
</p>

**A production-ready reference app for the [RunAnywhere Swift SDK](../../../sdk/runanywhere-swift/).** LLM chat, speech, vision, voice agents, RAG, benchmarks, and model management—privacy-first and offline-capable on iPhone, iPad, and Mac.

---

## Requirements

| Item | Minimum |
|------|---------|
| **Xcode** | 26+ with Swift 6.2 and iOS 17.5+ simulator runtimes |
| **Command Line Tools** | Selected in Xcode → Settings → Locations |
| **CMake & Ninja** | For root native XCFramework generation |
| **Disk space** | Several GB for XCFramework output and AI models |
| **Device** | Apple Silicon recommended (physical device for MLX and best LLM performance) |

---

## Setup

> **Important:** This sample links the local Swift SDK through `Package.swift`. A clean clone must build iOS XCFrameworks before Xcode can link the native backends.

### 1. Clone and enter the example

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/ios/RunAnywhereAI
```

### 2. Build native XCFrameworks (repo root)

```bash
cd ../../..
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
cd examples/ios/RunAnywhereAI
```

Expected artifacts under `sdk/runanywhere-swift/Binaries/`:

| Artifact | Needed for |
|----------|-----------|
| `RACommons.xcframework` | Core (required) |
| `RABackendLLAMACPP.xcframework` | LLM and VLM |
| `RABackendONNX.xcframework` · `RABackendSherpa.xcframework` | STT, TTS, VAD |
| `onnxruntime.xcframework` · `onnx.xcframework` | ONNX Runtime for the two above |
| `RABackendMLX.xcframework` · `RunAnywhereMLXRuntime.xcframework` · `RunAnywhereMLXMetal.xcframework` | Apple MLX (this app links `RunAnywhereMLX`) |
| `RABackendNeuRT.xcframework` | NeuRT — ANE text generation + Core ML image generation |

All ten are produced by one run of the script. A short list is the usual cause of link errors on the MLX path, since this app's `Package.swift` depends on the `RunAnywhereMLX` product.

Re-run this step after any C++ change in `runanywhere-commons`.

### 3. Resolve packages and build

```bash
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift package resolve

xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -resolvePackageDependencies

xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build
```

### 4. Run the app

**Option A — Xcode:** Open `RunAnywhereAI.xcodeproj`, select a simulator or device, press **Run** (⌘R).

**Option B — Script:**

```bash
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro" --build-sdk
# Physical device:
./scripts/build_and_run_ios_sample.sh device
# macOS:
./scripts/build_and_run_ios_sample.sh mac
```

**Option C — Verify gate:**

```bash
./scripts/verify.sh
```

### After modifying the SDK

| Change | Action |
|--------|--------|
| Swift SDK source | Xcode picks up changes on rebuild |
| C++ / commons | Re-run `build-core-xcframework.sh` |
| Stale package errors | **File → Packages → Reset Package Caches**, then resolve again |

---

## Features

| Feature | Description |
|---------|-------------|
| **AI Chat** | Streaming LLM with thinking mode, tool calling, and LoRA adapters |
| **Speech-to-Text** | Batch and live transcription (Sherpa-ONNX / Whisper) |
| **Text-to-Speech** | Neural Piper voices |
| **Voice Assistant** | Full STT → LLM → TTS pipeline with particle UI |
| **Vision (VLM)** | Camera and photo-library image understanding |
| **RAG** | PDF/document ingestion and on-device Q&A |
| **Benchmarks** | Deterministic LLM, STT, TTS, and VLM performance tests |
| **Voice Keyboard** | iOS keyboard extension with dictation flow |
| **Model Management** | Download, load, storage, and deletion |
| **Cross-Platform** | Universal iOS, iPadOS, and macOS app |

MLX-backed models run on physical iOS devices and native macOS; the arm64 simulator build validates package and startup paths but does not execute MLX inference.

---

## Project structure

```
RunAnywhereAI/
├── RunAnywhereAI/
│   ├── App/                    # Entry point, SDK init, tab shell
│   ├── Features/               # Chat, Voice, Vision, RAG, Benchmarks, …
│   ├── Core/                   # Design system, services, models
│   └── Helpers/                # Markdown rendering, adaptive layout
├── RunAnywhereKeyboard/        # Keyboard extension target
├── RunAnywhereActivityExtension/  # Live Activity widget
├── Package.swift               # Local Swift SDK dependency
├── scripts/
│   ├── build_and_run_ios_sample.sh
│   ├── verify.sh
│   └── smoke.sh
└── README.md
```

Architecture: **MVVM** with Swift Observation (`@Observable` view models), a single `RunAnywhere.*` SDK entry point, and centralized design tokens (`AppColors`, `AppTypography`, brand orange `#FF6900`).

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Missing XCFramework errors | Run `./sdk/runanywhere-swift/scripts/build-core-xcframework.sh` from repo root |
| Package resolution failures | Reset package caches in Xcode; rerun `swift package resolve` |
| Sandbox / derived-data issues | Clean build folder (⇧⌘K); delete DerivedData if needed |
| MLX models unavailable | Use a physical device; MLX returns unavailable on simulator |
| Verify script fails | Run `./scripts/verify.sh` and follow its output for the exact gate |

Quick static check without full compile:

```bash
./scripts/smoke.sh
```

Filter runtime logs in Console.app: `subsystem:com.runanywhere.RunAnywhereAI`.

---

## Related links

| Resource | Link |
|----------|------|
| **Swift SDK** | [sdk/runanywhere-swift/README.md](../../../sdk/runanywhere-swift/README.md) |
| **Android example** | [examples/android/RunAnywhereAI](../../android/RunAnywhereAI/README.md) |
| **React Native example** | [examples/react-native/RunAnywhereAI](../../react-native/RunAnywhereAI/README.md) |
| **Flutter example** | [examples/flutter/RunAnywhereAI](../../flutter/RunAnywhereAI/README.md) |
| **App Store** | [RunAnywhere on the App Store](https://apps.apple.com/us/app/runanywhere/id6756506307) |
| **Discord** | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |
| **Issues** | [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues) |
| **Email** | founders@runanywhere.ai |

---

## License

This project is licensed under the RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](../../../LICENSE) for details.
