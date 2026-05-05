# @runanywhere/llamacpp

Llama.cpp backend registration package for the RunAnywhere React Native SDK.

This package does not own public model catalog, download, lifecycle,
generation, VLM, LoRA, tool-calling, or structured-output APIs. Those surfaces
live in `@runanywhere/core` over the generated proto/Nitro/commons bridge.
`@runanywhere/llamacpp` only installs or removes the native llama.cpp backend
providers.

## Requirements

- `@runanywhere/core` peer dependency
- React Native 0.74+
- iOS 15.1+ / Android API 24+

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
import { RunAnywhere, InferenceFramework } from '@runanywhere/core';
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

await RunAnywhere.downloadModel('smollm2-360m-q8_0');
await RunAnywhere.loadModel('smollm2-360m-q8_0');

const result = await RunAnywhere.generate('Write one sentence about local AI.');
console.log(result.text);
```

## Public API

```typescript
import { LlamaCPP, LlamaCppProvider } from '@runanywhere/llamacpp';
```

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
|   `-- LlamaCPPBackend.podspec
|-- android/
|   |-- build.gradle
|   `-- CMakeLists.txt
`-- nitrogen/
    `-- generated/
```
