# Sample Functional Smoke Matrix

This matrix tracks the minimum clean-clone and real SDK flow coverage expected for each sample app.

Legend:

- **Automated**: covered by `scripts/verify.sh`, `scripts/smoke.sh`, or a build gate.
- **Manual**: requires an interactive runtime, model download, device permission, or browser capability.
- **Static**: smoke script verifies real SDK calls are present; the full behavior still needs manual runtime validation.

## Per-Sample Flow Coverage

| Sample | Flow | Coverage | Required environment |
| --- | --- | --- | --- |
| React Native | Init | Automated: `yarn typecheck`; Static: `RunAnywhere.initialize` coverage | Node 18+, Yarn via Corepack |
| React Native | Registry refresh | Static: `getAvailableModels` and model setup coverage | Node 18+ |
| React Native | Model list | Static; Manual: open model picker | iOS simulator/device or Android device/emulator |
| React Native | Download | Static: `downloadModel`; Manual: download a small LLM/STT/TTS model | Network, device storage |
| React Native | Load | Static: `loadModel`, `loadSTTModel`, `loadTTSModel`; Manual runtime load | Local native artifacts, downloaded model |
| React Native | Generate | Static: `generate`/chat flow coverage | Loaded LLM |
| React Native | Stream | Static: `generateStream`; Manual token streaming check | Loaded LLM |
| React Native | Cancel | Static: voice/stream adapter cancellation coverage; Manual tab/stop action | Loaded model, active generation |
| React Native | Voice | Static: voice agent adapter coverage; Manual STT -> LLM -> TTS | Microphone permission, STT/LLM/TTS models |
| React Native | RAG | Static/manual: only if RAG UI is wired in current branch | Document import permission if enabled |
| React Native | Delete | Static: `deleteModel`; Manual delete from settings | Downloaded model |
| React Native | Clear cache | Static: `clearCache`/storage APIs; Manual clear in settings | Downloaded/cache data |
| Flutter | Init | Automated: `flutter analyze`; Static SDK import coverage | Flutter 3.10+, Dart 3+ |
| Flutter | Registry refresh | Static: `ModelManager`/model catalog coverage | Flutter toolchain |
| Flutter | Model list | Static; Manual: open model browser | Android/iOS runtime |
| Flutter | Download | Static: `downloadModel`; Manual model download | Network, device storage |
| Flutter | Load | Static: `loadLLMModel`, `loadSTTModel`, `loadTTSVoice`; Manual runtime load | Local native artifacts, downloaded model |
| Flutter | Generate | Static: `generate`; Manual chat prompt | Loaded LLM |
| Flutter | Stream | Static: `generateStream`; Manual token streaming check | Loaded LLM |
| Flutter | Cancel | Static: voice/generation state coverage; Manual stop/tab interruption | Active generation |
| Flutter | Voice | Static: voice event stream coverage; Manual STT -> LLM -> TTS | Microphone permission, STT/LLM/TTS models |
| Flutter | RAG | Static: `file_picker` and PDF dependency coverage; Manual document import/query | File picker access, RAG-capable UI |
| Flutter | Delete | Static: `deleteStoredModel`; Manual storage delete | Downloaded model |
| Flutter | Clear cache | Static: storage manager coverage; Manual clear action | Downloaded/cache data |
| iOS Native | Init | Automated: Swift package resolve and xcodebuild in `scripts/verify.sh` | Xcode 15+, Swift 5.9+ |
| iOS Native | Registry refresh | Static: `registerModel` coverage | Xcode toolchain |
| iOS Native | Model list | Static; Manual: open model selection UI | iOS simulator/device |
| iOS Native | Download | Static: `downloadModel`; Manual model download | Network, simulator/device storage |
| iOS Native | Load | Static: `loadModel`, `loadSTTModel`, `loadTTSModel`; Manual runtime load | Local XCFrameworks, downloaded model |
| iOS Native | Generate | Static: `generate`; Manual chat prompt | Loaded LLM |
| iOS Native | Stream | Static: `generateStream`; Manual token streaming check | Loaded LLM |
| iOS Native | Cancel | Static: `cancelGeneration`; Manual stop during generation | Active generation |
| iOS Native | Voice | Static: voice pipeline coverage; Manual STT -> LLM -> TTS | Microphone permission, STT/LLM/TTS models |
| iOS Native | RAG | Static/manual: only if RAG UI is wired in current branch | Document picker access if enabled |
| iOS Native | Delete | Static: `deleteModel`; Manual storage delete | Downloaded model |
| iOS Native | Clear cache | Static: `clearCache`/storage APIs; Manual clear action | Downloaded/cache data |
| Android Native | Init | Automated: Gradle assemble in `scripts/verify.sh`; Static `RunAnywhere.initialize` coverage | Android SDK/NDK, JDK 17 |
| Android Native | Registry refresh | Static: `registerModel` coverage | Android build environment |
| Android Native | Model list | Static; Manual: open model picker | Android device/emulator |
| Android Native | Download | Static: `downloadModel`; Manual model download | Network, device storage |
| Android Native | Load | Static: `loadLLMModel`, `loadSTTModel`, `loadTTSVoice`; Manual runtime load | Local JNI artifacts, downloaded model |
| Android Native | Generate | Static: `generate`; Manual chat prompt | Loaded LLM |
| Android Native | Stream | Static: `generateStream`; Manual token streaming check | Loaded LLM |
| Android Native | Cancel | Static: `cancelGeneration`/stop APIs; Manual stop during generation | Active generation |
| Android Native | Voice | Static: `startVoiceSession`/`processVoice`; Manual STT -> LLM -> TTS | Microphone permission, STT/LLM/TTS models |
| Android Native | RAG | Static/manual: only if RAG UI is wired in current branch | File/document access if enabled |
| Android Native | Delete | Static: `deleteModel`; Manual storage delete | Downloaded model |
| Android Native | Clear cache | Static: `clearCache`; Manual clear action | Downloaded/cache data |
| Web | Init | Automated: `npm run build`; Static `RunAnywhere.initialize` coverage | Node 18+, npm |
| Web | Registry refresh | Automated/static: `RunAnywhere.registerModels` coverage | Node 18+ |
| Web | Model list | Static; Manual: open model picker | Browser runtime |
| Web | Download | Static: `ModelManager.downloadModel`; Manual model download | Network, OPFS/local folder storage |
| Web | Load | Static: `ModelManager.loadModel`; Manual runtime load | WASM artifact, browser storage |
| Web | Generate | Static: `ToolCalling.generateWithTools`; Manual chat prompt | Loaded LLM |
| Web | Stream | Static: `TextGeneration.generateStream`; Manual token streaming check | Loaded LLM, WASM |
| Web | Cancel | Static: stream cancel callback coverage; Manual tab switch/stop | Active generation |
| Web | Voice | Static: voice/transcribe/synthesize surface coverage; Manual browser support check | Microphone permission, ONNX artifacts when enabled |
| Web | RAG | Static/manual: document import paths if UI is enabled | Browser file picker/local storage |
| Web | Delete | Static: `ModelManager.deleteModel`; Manual storage delete | Downloaded model |
| Web | Clear cache | Static: `ModelManager.clearAll`; Manual clear all models | Downloaded/cache data |

## Build Gates

| Sample | Default verify gate | Optional gates |
| --- | --- | --- |
| React Native | `yarn typecheck`, Android `:app:assembleDebug` | `RUN_IOS=1`, `REFRESH_ANDROID_NATIVE=1`, `REFRESH_IOS_NATIVE=1` |
| Flutter | `flutter pub get`, `flutter analyze`, debug APK | `RUN_IOS=1`, `REFRESH_ANDROID_NATIVE=1`, `REFRESH_IOS_NATIVE=1` |
| iOS Native | XCFramework check, Swift package resolve, simulator xcodebuild | `REFRESH_NATIVE=1`, custom `IOS_DESTINATION` |
| Android Native | Android `:app:assembleDebug` | `REFRESH_NATIVE=1`, custom `ANDROID_ABI` |
| Web | npm install/ci, Vite build | `REFRESH_WASM=1`, `REQUIRE_WASM=1` |
