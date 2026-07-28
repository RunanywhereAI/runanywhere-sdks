# RunAnywhere AI — Flutter Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App_Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on App Store" />
  </a>
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://img.shields.io/badge/Google_Play-Download-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Get it on Google Play" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2017.5%2B%20%7C%20Android%20API%2024%2B-02569B?style=flat-square&logo=flutter&logoColor=white" alt="iOS 17.5+ | Android API 24+" />
  <img src="https://img.shields.io/badge/Flutter-3.44.6%2B-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.44.6+" />
  <img src="https://img.shields.io/badge/Dart-3.12.2%2B-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart 3.12.2+" />
  <img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" />
</p>

**A cross-platform reference app for the [RunAnywhere Flutter SDK](../../../sdk/runanywhere-flutter/).** LLM chat, speech, vision, voice agents, RAG, tools, and model management via Dart FFI—mirroring the native iOS example's feature set.

---

## Requirements

| Item | Minimum |
|------|---------|
| **Flutter** | 3.44.6+ (Dart 3.12.2+) |
| **Android Studio** | SDK 24+, NDK; `ANDROID_HOME` and `ANDROID_NDK_HOME` set |
| **Xcode** | 26+ and CocoaPods (iOS builds) |
| **JDK** | 17 |
| **Disk space** | Several GB for native artifacts and AI models |
| **Device** | ARM64 physical device recommended (required for Apple MLX) |

---

## Setup

> **Important:** This sample uses local `path:` dependencies on Flutter SDK packages. A clean clone must stage Android JNI libraries and iOS XCFrameworks into those packages before the app will build.

### 1. Clone and resolve packages

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/flutter/RunAnywhereAI

flutter pub get
```

### 2. Build and stage native artifacts (repo root)

```bash
cd ../../..
./scripts/build/build-core-android.sh arm64-v8a
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
cd examples/flutter/RunAnywhereAI
```

- Android `.so` files land in `sdk/runanywhere-flutter/packages/*/android/src/main/jniLibs/`.
- iOS XCFrameworks land in each package's `ios/<package>/Frameworks/` directory.
- Local consumption is enabled by `runanywhere.useLocalNatives=true` in `android/gradle.properties`.

Re-run after any C++ change in `runanywhere-commons`.

### 3. Verify and build

```bash
flutter analyze
flutter build apk --debug
flutter build ios --simulator --debug
```

If iOS Pods are stale after `pub get`:

```bash
cd ios && pod install && cd ..
```

Or run the combined gate:

```bash
./scripts/verify.sh           # APK + analyze; RUN_IOS=1 for iOS build too
```

### 4. Run the app

```bash
flutter run                   # Connected device or emulator
flutter run -d "iPhone 16 Pro"   # Specific iOS simulator
```

Open in VS Code or Android Studio, select a target, and press **Run**.

### After modifying the SDK

| Change | Action |
|--------|--------|
| Dart SDK | Hot reload for most UI changes; restart for native init changes |
| C++ / commons | Re-run both root native build scripts from step 2 |

---

## Features

| Feature | Description |
|---------|-------------|
| **AI Chat** | Streaming and batch LLM with thinking-mode parsing |
| **Apple MLX** | LLM, VLM, embeddings, STT, TTS on physical iOS devices |
| **Speech-to-Text** | Batch and live transcription |
| **Text-to-Speech** | Piper ONNX voices with playback controls |
| **Voice Assistant** | STT → LLM → TTS via `RunAnywhere.voice` event stream |
| **Vision (VLM)** | Camera auto-stream and photo capture |
| **RAG** | PDF ingestion and document Q&A |
| **Tools & Structured Output** | Tool calling and JSON schema generation |
| **Solutions** | YAML pipeline demos |
| **Model Management** | Download, load, storage, deletion |

MLX registers only on physical iOS hardware; the arm64 simulator validates compile/link/startup but does not run MLX inference.

---

## NPU / QHexRT (Android)

The `runanywhere_qhexrt` package accelerates inference on supported Snapdragon/Hexagon devices. QHexRT native libraries are private local artifacts—stage them into `sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/src/main/jniLibs/arm64-v8a/` before building; do not commit them.

To test private HNPU bundles: **Settings → Downloads** → save a Hugging Face token → download/load an HNPU model → **Clear** to revert to public downloads. Token is passed via `RunAnywhere.setHfToken(...)` at runtime.

---

## Project structure

```
RunAnywhereAI/
├── lib/
│   ├── app/                    # runanywhere_ai_app.dart, ContentView tabs
│   ├── features/               # chat, voice, vision, rag, tools, settings, …
│   ├── core/
│   │   ├── design_system/      # AppColors (#FF6900), typography, spacing
│   │   └── services/           # Audio, conversation store, permissions
│   └── helpers/
├── pubspec.yaml                # path: deps → sdk/runanywhere-flutter/packages/*
├── android/                    # minSdk 24, packagingOptions for duplicate .so
├── ios/                        # Podfile, deployment target 17.5
├── scripts/
│   ├── verify.sh
│   └── smoke.sh
└── README.md
```

AI calls go through `RunAnywhere.*` facades over Dart FFI—no platform-channel hop for inference.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Missing native library errors | Re-run root native build scripts; confirm `runanywhere.useLocalNatives=true` |
| iOS Pod / arch errors | `cd ios && pod install`; xcframeworks are arm64-only (x86_64 simulator excluded) |
| Gradle OOM | `-Xmx6g` is set in `gradle.properties`; close other Gradle daemons |
| MLX unavailable | Use a physical iOS device |
| Analysis failures | `flutter analyze` — strict mode treats unused imports as errors |

Quick static check:

```bash
./scripts/smoke.sh
flutter test
```

---

## Related links

| Resource | Link |
|----------|------|
| **Flutter SDK** | [sdk/runanywhere-flutter/README.md](../../../sdk/runanywhere-flutter/README.md) |
| **iOS example** | [examples/ios/RunAnywhereAI](../../ios/RunAnywhereAI/README.md) |
| **Android example** | [examples/android/RunAnywhereAI](../../android/RunAnywhereAI/README.md) |
| **React Native example** | [examples/react-native/RunAnywhereAI](../../react-native/RunAnywhereAI/README.md) |
| **App Store / Play Store** | [iOS](https://apps.apple.com/us/app/runanywhere/id6756506307) · [Android](https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai) |
| **Discord** | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |
| **Issues** | [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues) |
| **Email** | founders@runanywhere.ai |

---

## License

This project is licensed under the RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](../../../LICENSE) for details.
