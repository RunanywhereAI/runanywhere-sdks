# @runanywhere/onnx

ONNX backend registration package for the RunAnywhere React Native SDK.

This package does not own public model catalog, download, lifecycle, STT, TTS,
VAD, or voice-agent APIs. Those surfaces live in `@runanywhere/core` over the
generated proto/Nitro/commons bridge, mirroring the Swift architecture source
of truth. `@runanywhere/onnx` only installs or removes native backend providers
and ships the `RABackendONNX` plus `RABackendSherpa` native binaries.

## Requirements

- `@runanywhere/core` peer dependency
- React Native 0.83.1+
- iOS 17.5+ / Android API 24+
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
import { RunAnywhere } from '@runanywhere/core';
import {
  InferenceFramework,
  ModelCategory,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';
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
  modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  url: 'https://example.invalid/model.tar.gz',
});

const download = RunAnywhere.downloadModel('sherpa-onnx-whisper-tiny.en')[Symbol.asyncIterator]();
while (!(await download.next()).done) {}
await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId: 'sherpa-onnx-whisper-tiny.en',
  category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
}));

// Use @runanywhere/core for model lifecycle and STT/TTS/VAD/voice APIs.
```

## Public API

```typescript
import { ONNX } from '@runanywhere/onnx';
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
|   `-- Binaries/
|       |-- RABackendONNX.xcframework
|       `-- RABackendSherpa.xcframework
|-- RunAnywhereONNX.podspec
|-- android/
|   |-- build.gradle
|   `-- CMakeLists.txt
`-- nitrogen/
    `-- generated/
```
