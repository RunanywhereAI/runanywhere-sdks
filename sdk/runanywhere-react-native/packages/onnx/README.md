# @runanywhere/onnx

ONNX backend registration package for the RunAnywhere React Native SDK.

This package does not own public model catalog, download, lifecycle, STT, TTS,
VAD, or voice-agent APIs. Those surfaces live in `@runanywhere/core` over the
generated proto/Nitro/commons bridge. `@runanywhere/onnx` only installs or
removes the native ONNX backend providers.

## Requirements

- `@runanywhere/core` peer dependency
- React Native 0.74+
- iOS 15.1+ / Android API 24+
- Microphone permission in the host app for live audio capture

## Installation

```bash
npm install @runanywhere/core @runanywhere/onnx
```

For iOS, run CocoaPods from the app:

```bash
cd ios && pod install && cd ..
```

Host apps that capture audio still need the platform microphone permission.

## Usage

```typescript
import { RunAnywhere, InferenceFramework, ModelCategory } from '@runanywhere/core';
import { ONNX } from '@runanywhere/onnx';

await RunAnywhere.initialize();

const registered = await ONNX.register();
if (!registered) {
  throw new Error('ONNX backend is not available');
}

await RunAnywhere.registerModel({
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny English',
  framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
  category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  url: 'https://example.invalid/model.tar.gz',
});

await RunAnywhere.downloadModel('sherpa-onnx-whisper-tiny.en');

// Use @runanywhere/core for model lifecycle and STT/TTS/VAD/voice APIs.
```

## Public API

```typescript
import { ONNX, ONNXProvider } from '@runanywhere/onnx';
```

### `ONNX.register()`

Registers ONNX providers with the native backend registry.

```typescript
ONNX.register(): Promise<boolean>
```

### `ONNX.unregister()`

Unregisters ONNX providers. Core-owned model lifecycle handles remain owned by
core.

```typescript
ONNX.unregister(): Promise<boolean>
```

### `ONNX.isRegistered()`

Checks native backend registration state.

```typescript
ONNX.isRegistered(): Promise<boolean>
```

### Metadata

```typescript
ONNX.moduleId
ONNX.moduleName
ONNX.inferenceFramework
ONNX.capabilities
ONNX.defaultPriority
```

## Native Boundary

The generated Nitro spec exposes only backend registration hooks:

- `registerBackend`
- `unregisterBackend`
- `isBackendRegistered`

Direct ONNX STT, TTS, VAD, and voice-agent bridges were deleted. Use
`@runanywhere/core` for public model lifecycle and inference APIs.

## Package Structure

```text
packages/onnx/
|-- src/
|   |-- index.ts
|   |-- ONNX.ts
|   |-- ONNXProvider.ts
|   |-- native/
|   |   `-- NativeRunAnywhereONNX.ts
|   `-- specs/
|       `-- RunAnywhereONNX.nitro.ts
|-- cpp/
|   |-- HybridRunAnywhereONNX.cpp
|   `-- HybridRunAnywhereONNX.hpp
|-- ios/
|   `-- ONNXBackend.podspec
|-- android/
|   |-- build.gradle
|   `-- CMakeLists.txt
`-- nitrogen/
    `-- generated/
```
