# @runanywhere/llamacpp

Llama.cpp backend registration package for the RunAnywhere React Native SDK.

This package does not own public model catalog, download, lifecycle,
generation, VLM, LoRA, tool-calling, or structured-output APIs. Those surfaces
live in `@runanywhere/core` over the generated proto/Nitro/commons bridge,
mirroring the Swift architecture source of truth.
`@runanywhere/llamacpp` only installs or removes the native llama.cpp backend
providers and ships the `RABackendLLAMACPP` native binary.

## Requirements

- `@runanywhere/core` peer dependency
- React Native 0.74+
- iOS 17.0+ / Android API 24+

## Installation

```bash
npm install @runanywhere/core @runanywhere/llamacpp
```

For iOS, run CocoaPods from the app:

```bash
cd ios && pod install && cd ..
```

Android native libraries are packaged by the React Native package.

## Usage

```typescript
import { RunAnywhere } from '@runanywhere/core';
import {
  InferenceFramework,
  ModelCategory,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';
import { LlamaCPP } from '@runanywhere/llamacpp';

await RunAnywhere.initialize();

const registered = await LlamaCPP.register();
if (!registered) {
  throw new Error('llama.cpp backend is not available');
}

await RunAnywhere.registerModel({
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  url: 'https://example.invalid/model.gguf',
});

const download = RunAnywhere.downloadModel('smollm2-360m-q8_0')[Symbol.asyncIterator]();
while (!(await download.next()).done) {}
await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId: 'smollm2-360m-q8_0',
  category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
}));

const result = await RunAnywhere.generate('Write one sentence about local AI.');
console.log(result.text);
```

## Public API

```typescript
import { LlamaCPP } from '@runanywhere/llamacpp';
```

`LlamaCppProvider` remains exported for lower-level compatibility, but app code
should use `LlamaCPP`. Neither surface owns model lifecycle or inference APIs.

### `LlamaCPP.register()`

Registers llama.cpp LLM and VLM providers with the native backend registry.

```typescript
LlamaCPP.register(): Promise<boolean>
```

### `LlamaCPP.unregister()`

Unregisters llama.cpp LLM and VLM providers. Core-owned model lifecycle handles
remain owned by core.

```typescript
LlamaCPP.unregister(): Promise<boolean>
```

### `LlamaCPP.isRegistered()`

Checks native backend registration state.

```typescript
LlamaCPP.isRegistered(): Promise<boolean>
```

### Metadata

```typescript
LlamaCPP.moduleId
LlamaCPP.moduleName
LlamaCPP.inferenceFramework
LlamaCPP.capabilities
LlamaCPP.defaultPriority
```

## Native Boundary

The generated Nitro spec exposes only backend registration hooks:

- `registerBackend`
- `unregisterBackend`
- `isBackendRegistered`
- `registerVLMBackend`
- `unregisterVLMBackend`
- `isVLMBackendRegistered`

Direct llama.cpp model loading, generation, structured-output, and VLM process
bridges were deleted. Use `@runanywhere/core` for public model lifecycle and
inference APIs.

## Package Structure

```text
packages/llamacpp/
|-- src/
|   |-- index.ts
|   |-- LlamaCPP.ts
|   |-- LlamaCppProvider.ts
|   |-- native/
|   |   `-- NativeRunAnywhereLlama.ts
|   `-- specs/
|       `-- RunAnywhereLlama.nitro.ts
|-- cpp/
|   |-- HybridRunAnywhereLlama.cpp
|   `-- HybridRunAnywhereLlama.hpp
|-- ios/
|   `-- Binaries/
|       `-- RABackendLLAMACPP.xcframework
|-- RunAnywhereLlama.podspec
|-- android/
|   |-- build.gradle
|   `-- CMakeLists.txt
`-- nitrogen/
    `-- generated/
```
