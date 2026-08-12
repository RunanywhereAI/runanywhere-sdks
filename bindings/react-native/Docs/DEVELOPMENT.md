# React Native SDK — Development Guide

This guide covers building the SDK from source, contributor workflows, and platform-specific notes for maintainers. For integration instructions, see the [consumer README](../README.md).

---

## Prerequisites

| Tool | Version |
|------|---------|
| **Node.js** | 22.12+ (CI pins 24 LTS) |
| **React Native** | 0.83.1+ |
| **Xcode** | 26+ with Swift 6.2 (iOS) |
| **Android Studio** | Hedgehog+ with NDK 27.3.13750724 |
| **CMake** | 3.24+ |

---

## First-Time Setup (Build from Source)

The SDK depends on native C++ libraries from `runanywhere-commons`. Native artifacts are built in the owning layer and staged into each RN package by `scripts/package-sdk.sh`.

```bash
# 1. Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks

# 2. Build native artifacts from runanywhere-commons (from repo root)
./bindings/swift/scripts/build-core-xcframework.sh   # iOS XCFrameworks → build/ios/
./scripts/build/build-core-android.sh                         # Android .so files → build/android/

# 3. Stage natives into the React Native packages
cd bindings/react-native
./scripts/package-sdk.sh --natives-from ../../build/native-artifacts

# 4. Install JavaScript dependencies (yarn workspaces)
yarn install
```

`package-sdk.sh --natives-from PATH` copies each binary into the package that owns it, type-checks each package, and produces `dist/sdk-rn/*.tgz` + `.sha256`.

**Per-package download alternative:** if you do not need to rebuild commons from source, each package exposes a download helper that pulls pre-built natives from a GitHub release:

```bash
# From bindings/react-native/
yarn core:download-ios          # or yarn core:download-android
yarn llamacpp:download-ios      # or yarn llamacpp:download-android
yarn onnx:download-ios          # or yarn onnx:download-android
```

---

## Native Binary Consumption

| Mode | Description |
|------|-------------|
| **Local** | Uses frameworks/JNI libs staged into package directories for development |
| **Packaged** | Published npm packages include package-owned natives; CocoaPods and Gradle consume them from the package directories |

After staging local natives, iOS consumes the package-owned `ios/Binaries/*.xcframework` files directly. On Android, set `runanywhere.useLocalNatives=true` in the consuming app's `gradle.properties` to skip release downloads and use staged local libraries.

---

## Testing with the Sample App

```bash
# 1. Ensure SDK is set up (from previous step)

# 2. Navigate to the sample app
cd ../../bindings/react-native/example

# 3. Install sample app dependencies (Yarn Berry workspace, not npm)
corepack enable
yarn install --ignore-scripts

# 4. iOS: Install pods and run
yarn pod-install
yarn ios

# 5. Android: Run directly
yarn android
```

The sample app is a Yarn Berry 3.6.1 workspace member (`nodeLinker: node-modules`) whose `package.json` references the local SDK packages by workspace. Running `npm install` inside it will fight the workspace symlink layout. Use `--ignore-scripts` on the first install so postinstall hooks cannot mask missing native artifacts.

---

## Development Workflow

**After modifying TypeScript SDK code:**

```bash
yarn typecheck
yarn lint
yarn build
```

**After modifying runanywhere-commons (C++ code):**

```bash
# From repo root
./bindings/swift/scripts/build-core-xcframework.sh
./scripts/build/build-core-android.sh

# Re-stage into RN packages
cd bindings/react-native
./scripts/package-sdk.sh --natives-from ../../build/native-artifacts
```

---

## Packaging Reference

| Command | Description |
|---------|-------------|
| `./scripts/package-sdk.sh --natives-from PATH` | Stage iOS XCFrameworks + Android `.so` files, type-check, produce `dist/sdk-rn/*.tgz` |
| `./scripts/package-sdk.sh --mode local\|ci` | Override packaging mode (default: auto-detect from `$CI`) |
| `yarn <core\|llamacpp\|onnx>:download-ios` | Download pre-built iOS natives for that package |
| `yarn <core\|llamacpp\|onnx>:download-android` | Download pre-built Android `.so` files for that package |

---

## Hermes Streaming

React Native's default JS engine (Hermes) does not support `for await...of` with NitroModules-backed async iterables. Any SDK API that returns an `AsyncIterable` must be consumed with a manual `Symbol.asyncIterator` loop:

```typescript
const streamResult = await RunAnywhere.generateStream(prompt, { maxTokens: 150 });
const iterator = streamResult.stream[Symbol.asyncIterator]();
while (true) {
  const { value, done } = await iterator.next();
  if (done) break;
  process.stdout.write(value);
}
```

**Affected surfaces** (every public API that yields an `AsyncIterable`):

| Surface | Yields |
|---------|--------|
| `RunAnywhere.generateStream(prompt, options)` | `LLMStreamEvent` |
| `RunAnywhere.transcribeStream(audio, options)` | `STTPartialResult` |
| `RunAnywhere.synthesizeStream(text, options)` | `TTSStreamEvent` |
| `RunAnywhere.processImageStream(request)` | `VLMStreamEvent` |
| `RunAnywhere.downloadModelStream(model)` | `DownloadProgress` |
| `RunAnywhere.streamVoiceAgent()` | `VoiceEvent` |

The batch twins (`transcribe`, `synthesize`, `processImage`, `generate`, `downloadModel`) return a single `Promise` and need no iteration.

`for await` only works on JavaScriptCore when Hermes is disabled. Breaking from the loop with `break` or `return` automatically cancels the native subscription.

---

## Architecture Overview

The RunAnywhere SDK follows a modular, provider-based architecture with a shared C++ core. The iOS packaging source of truth is [`bindings/swift/ARCHITECTURE.md`](../../swift/ARCHITECTURE.md).

```
┌─────────────────────────────────────────────────────────────────┐
│                     Your React Native App                        │
├─────────────────────────────────────────────────────────────────┤
│              @runanywhere/core (TypeScript API)                  │
├────────────┬─────────────────────────────────────┬──────────────┤
│  @runanywhere/llamacpp  │  @runanywhere/onnx     │ @runanywhere/mlx │
├────────────┼─────────────────────────────────────┼──────────────┤
│            │          Nitrogen/Nitro JSI         │              │
├────────────┼─────────────────────────────────────┼──────────────┤
│              runanywhere-commons (C++)                           │
└─────────────────────────────────────────────────────────────────┘
```

See also [Docs/Documentation.md](../Docs/Documentation.md) and [Docs/ARCHITECTURE.md](../Docs/ARCHITECTURE.md).

---

## Code Style

```bash
yarn lint
yarn lint:fix
```

---

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes with tests
4. Ensure type checking passes: `yarn typecheck`
5. Run linter: `yarn lint`
6. Commit with a descriptive message
7. Push and open a Pull Request

---

## Reporting Issues

Open an issue on GitHub with:

- SDK version: `RunAnywhere.version`
- Platform (iOS/Android) and OS version
- Device model
- React Native version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (with sensitive info redacted)
