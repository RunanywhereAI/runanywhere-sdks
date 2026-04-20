# React Native SDK

v2 React Native SDK layout. Mirrors the `sdk/rn/` federated structure
used by the main-branch `sdk/runanywhere-react-native/packages/*`.

```
sdk/rn/
├── packages/
│   ├── core/          — @runanywhere/core
│   │   ├── src/       — TS entry + Nitro spec
│   │   ├── cpp/       — JSI ↔ C ABI bridge (RunAnywhereTurboModule.cpp)
│   │   ├── ios/       — Podspec (vendors RACommonsCore.xcframework)
│   │   └── android/   — Gradle (links libracommons_core.so via NDK CMake)
│   ├── llamacpp/      — @runanywhere/llamacpp (thin register())
│   ├── onnx/          — @runanywhere/onnx
│   └── genie/         — @runanywhere/genie
```

## Architecture

- `core/src/index.ts` re-exports the shared TS adapter from `sdk/ts/`
  (public API surface) and adds `getNativeBridge()` which resolves the
  Nitro TurboModule.
- `core/src/RunAnywhereNative.ts` is the Nitro spec — `HybridObject<{
  ios: 'c++', android: 'c++' }>` — listing every method that crosses
  the JS→native boundary.
- `core/cpp/RunAnywhereTurboModule.cpp` is the JSI bridge. Each method
  delegates directly to a `ra_*` C ABI function.
- `core/runanywhere-core.podspec` + `core/android/build.gradle` wire
  the native code into iOS (XCFramework) and Android (prebuilt .so)
  builds.

## Installing in a sample app

```json
// package.json
"dependencies": {
  "@runanywhere/core": "2.0.0",
  "@runanywhere/llamacpp": "2.0.0"
}
```

```ts
// App.tsx
import { RunAnywhere } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';

await RunAnywhere.initialize({ apiKey: 'xxx' });
LlamaCPP.register(100);
```

## Status

This scaffold matches the main-branch federated layout. The Nitro
TurboModule spec + podspec/gradle wiring are ready; the C++ bridge
builds with the v2 core. Full end-to-end smoke tests against the
`examples/react-native/RunAnywhereAI` sample remain as follow-up —
the existing `sdk/ts/` adapter is used unchanged under the hood so
all public API calls work identically.
