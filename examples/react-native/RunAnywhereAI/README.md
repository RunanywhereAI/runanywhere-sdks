# RunAnywhere AI — React Native Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App%20Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store" />
  </a>
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://img.shields.io/badge/Google%20Play-Download-414141?style=for-the-badge&logo=google-play&logoColor=white" alt="Get it on Google Play" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2017.5%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17.5+" />
  <img src="https://img.shields.io/badge/Platform-Android%20API%2024%2B-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android API 24+" />
  <img src="https://img.shields.io/badge/React%20Native-0.85.3-61DAFB?style=flat-square&logo=react&logoColor=white" alt="React Native 0.85.3" />
  <img src="https://img.shields.io/badge/Node.js-22.12%2B-339933?style=flat-square&logo=nodedotjs&logoColor=white" alt="Node.js 22.12+" />
  <img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" />
</p>

**A cross-platform reference app for the [RunAnywhere React Native SDK](../../../sdk/runanywhere-react-native/).** One TypeScript codebase demonstrating on-device LLM chat, speech, vision, RAG, voice agents, and model management on iOS and Android.

---

## Requirements

| Item | Minimum |
|------|---------|
| **Node.js** | 22.12+ |
| **Yarn** | 3.x via Corepack (`corepack enable`) |
| **Xcode** | 26+ with Swift 6.2 and iOS 17.5+ runtimes (iOS builds) |
| **CocoaPods** | For iOS native dependencies |
| **Android Studio** | SDK 24+, build tools, NDK; `ANDROID_HOME` and `ANDROID_NDK_HOME` set |
| **JDK** | 17 |
| **Disk space** | Several GB for native artifacts and AI models |

This project uses `nodeLinker: node-modules` (not Plug'n'Play).

---

## Setup

> **Important:** This sample consumes local `file:` workspace packages. A clean clone needs JavaScript dependencies, staged native binaries (Android JNI + iOS XCFrameworks), and CocoaPods codegen before either platform will build.

### 1. Clone and install JavaScript dependencies

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/react-native/RunAnywhereAI

corepack enable
yarn install --ignore-scripts
```

Use `--ignore-scripts` on first install so postinstall hooks do not mask missing natives. Run `yarn postinstall` manually only after reviewing local patches.

### 2. Build and stage native artifacts (repo root)

```bash
cd ../../..
./scripts/build/build-core-android.sh arm64-v8a
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
cd examples/react-native/RunAnywhereAI
```

One run stages every Apple artifact the app can link: `RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendSherpa`, `onnxruntime`, `onnx`, `RABackendNeuRT`, and the three MLX frameworks (`RABackendMLX`, `RunAnywhereMLXRuntime`, `RunAnywhereMLXMetal`). Any of them missing means this step was skipped.

### 3. Install iOS pods and verify builds

```bash
yarn pod-install

cd android && ./gradlew :app:assembleDebug && cd ..

xcodebuild \
  -project ios/RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Or run the combined gate:

```bash
./scripts/verify.sh        # Android by default; RUN_IOS=1 for iOS too
```

### 4. Run the app

```bash
yarn start          # Metro bundler
yarn ios            # iOS simulator or device
yarn android        # Android emulator or device
```

### After modifying the SDK

| Change | Action |
|--------|--------|
| TypeScript SDK | Metro hot-reloads automatically |
| C++ / commons | Re-run root native build scripts, then re-stage into RN packages via `sdk/runanywhere-react-native/scripts/package-sdk.sh --natives-from <path>` |
| Stale iOS codegen | Remove `ios/build/generated` and rerun `yarn pod-install` |

---

## Features

| Feature | Description |
|---------|-------------|
| **AI Chat** | Streaming LLM with tool calling and thinking mode |
| **Speech-to-Text** | Batch and streaming transcription |
| **Text-to-Speech** | ONNX Piper voices and platform TTS fallback |
| **Voice Assistant** | STT → LLM → TTS pipeline |
| **Vision (VLM)** | Camera-based image understanding |
| **RAG** | Document Q&A with PDF ingestion |
| **Solutions** | YAML pipeline demo runner |
| **Model Management** | Download, load, storage, deletion |
| **Cross-Platform** | Shared UI via React Native + NitroModules (JSI) |

On Android, QHexRT NPU acceleration is available on supported Snapdragon devices when the native backend is staged. See **NPU / QHexRT** below.

---

## NPU / QHexRT (Android)

The `@runanywhere/qhexrt` package registers on supported Hexagon hardware. Its Gradle project is included only when the native library is present at `node_modules/@runanywhere/qhexrt/android/src/main/jniLibs/arm64-v8a/librac_backend_qhexrt.so`.

To test private HNPU model bundles:

1. Open **Settings → Downloads**.
2. Save a Hugging Face token.
3. Download and load an HNPU model from the model UI.
4. Tap **Clear** to return to public downloads.

The token is passed via `RunAnywhere.setHfToken(...)` at runtime—not stored in source or logs.

---

## Project structure

```
RunAnywhereAI/
├── App.tsx                     # SDK init, backend registration, navigation
├── src/
│   ├── screens/                # Chat, STT, TTS, Voice, RAG, Vision, …
│   ├── components/             # Chat bubbles, model picker, banners
│   ├── stores/                 # Zustand conversation persistence
│   └── theme/system/           # Material-3-style design tokens (#FF6900)
├── ios/                        # Xcode project, Podfile, native audio module
├── android/                    # Gradle project, manual SDK module wiring
├── scripts/
│   ├── verify.sh
│   └── smoke.sh
└── package.json                # Workspace deps → sdk/runanywhere-react-native/packages/*
```

SDK packages use **NitroModules** for JSI bridging. Hermes does not support `for await...of` on Nitro async iterables—use manual `iterator.next()` loops (see chat and download flows in the app).

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Missing XCFramework / `.so` errors | Re-run root native build scripts from step 2 |
| Pod / codegen stale | `yarn pod-install`; delete `ios/build/generated` if needed |
| Metro cache issues | `yarn start --reset-cache` |
| Android duplicate `.so` conflicts | Expected—resolved via `packagingOptions.pickFirsts` in Gradle |
| Type errors after dep refresh | `yarn typecheck`; run `yarn format:fix` if formatters disagree |
| Verify failures | `./scripts/verify.sh` with `RUN_IOS=1` / `RUN_ANDROID=1` as needed |

Quick static check:

```bash
./scripts/smoke.sh
yarn typecheck
```

---

## Related links

| Resource | Link |
|----------|------|
| **React Native SDK** | [sdk/runanywhere-react-native/README.md](../../../sdk/runanywhere-react-native/README.md) |
| **iOS example** | [examples/ios/RunAnywhereAI](../../ios/RunAnywhereAI/README.md) |
| **Android example** | [examples/android/RunAnywhereAI](../../android/RunAnywhereAI/README.md) |
| **Flutter example** | [examples/flutter/RunAnywhereAI](../../flutter/RunAnywhereAI/README.md) |
| **App Store / Play Store** | [iOS](https://apps.apple.com/us/app/runanywhere/id6756506307) · [Android](https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai) |
| **Discord** | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |
| **Issues** | [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues) |
| **Email** | founders@runanywhere.ai |

---

## License

This project is licensed under the RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](../../../LICENSE) for details.
