# RunAnywhere AI — iOS Example

<p align="center">
  <img src="https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
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

**A production-ready reference app for the [RunAnywhere Swift SDK](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/sdk/runanywhere-swift/).** LLM chat, speech, vision, voice agents, RAG, benchmarks, and model management—privacy-first and offline-capable on iPhone, iPad, and Mac.

---

## Requirements

| Item | Minimum |
|------|---------|
| **Xcode** | 26+ with Swift 6.2 and iOS 17.5+ simulator runtimes |
| **Command Line Tools** | Selected in Xcode → Settings → Locations |
| **Disk space** | Several GB for the downloaded SDK artifacts and AI models |
| **Device** | Apple Silicon recommended (physical device for MLX and best LLM performance) |

---

## Setup

> **This sample consumes the RunAnywhere Swift SDK entirely from its published GitHub release.** There is no monorepo checkout to build and no XCFramework to stage — SwiftPM downloads the checksum-verified native archives during resolve.

### 1. Get the example

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/ios/RunAnywhereAI
```

### 2. Resolve packages and build

```bash
swift package resolve

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

### 3. Run the app

**Option A — Xcode:** Open `RunAnywhereAI.xcodeproj`, select a simulator or device, press **Run** (⌘R).

**Option B — Script:**

```bash
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro"
# Physical device:
./scripts/build_and_run_ios_sample.sh device
# macOS:
./scripts/build_and_run_ios_sample.sh mac
```

**Option C — Verify gate:**

```bash
./scripts/verify.sh
```

### Moving to a newer SDK release

The SDK dependency is pinned in `Package.swift` (and mirrored in the Xcode
project) to the exact commit behind a published tag. To take a newer release,
update the revision in both places and resolve again.

| Change | Action |
|--------|--------|
| New SDK release | Update the pinned revision in `Package.swift` + `RunAnywhereAI.xcodeproj`, then resolve |
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
| Missing XCFramework errors | The native archives ship with the SDK release — reset package caches and rerun `swift package resolve` so SwiftPM re-downloads them |
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
| **Swift SDK** | [sdk/runanywhere-swift/README.md](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/sdk/runanywhere-swift/README.md) |
| **Android example** | [examples/android/RunAnywhereAI](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/examples/android/RunAnywhereAI/README.md) |
| **React Native example** | [examples/react-native/RunAnywhereAI](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/examples/react-native/RunAnywhereAI/README.md) |
| **Flutter example** | [examples/flutter/RunAnywhereAI](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/examples/flutter/RunAnywhereAI/README.md) |
| **App Store** | [RunAnywhere on the App Store](https://apps.apple.com/us/app/runanywhere/id6756506307) |
| **Discord** | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |
| **Issues** | [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues) |
| **Email** | founders@runanywhere.ai |

---

## License

This project is licensed under the RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE) for details.
