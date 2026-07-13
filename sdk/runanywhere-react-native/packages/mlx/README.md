# @runanywhere/mlx

Apple MLX backend registration for the RunAnywhere React Native SDK.

The package owns only backend registration and its iOS runtime binaries. Model
catalog, download, lifecycle, LLM, VLM, speech, and embedding APIs remain in
`@runanywhere/core`, which is the shared public surface across backends.

## Requirements

- `@runanywhere/core` 0.20.9+
- React Native 0.83.1+
- Xcode 26+ with the Swift 6.2 toolchain
- A physical Apple device running iOS 17.5+

MLX is an Apple-only backend. Android autolinking is intentionally disabled.
The arm64 iOS Simulator artifact supports package, compile, link, and startup
validation only; `MLX.register()` and `MLX.isAvailable()` return `false` there.

## Installation

```bash
npm install @runanywhere/core @runanywhere/mlx @runanywhere/proto-ts
cd ios && pod install && cd ..
```

The published package must contain `RABackendMLX.xcframework`,
`RunAnywhereMLXRuntime.xcframework`, and `RunAnywhereMLXMetal.xcframework`.
Packaging and CocoaPods fail when any runtime artifact is missing; the
TypeScript facade is not published as a standalone substitute for native MLX
support.

## Usage

```typescript
import { RunAnywhere } from '@runanywhere/core';
import { MLX } from '@runanywhere/mlx';
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';

const registered = await MLX.register();
if (!registered) {
  throw new Error('MLX is unavailable on this target');
}

await RunAnywhere.initialize();
await RunAnywhere.registerModel({
  id: 'mlx-qwen3-0.6b-4bit',
  name: 'MLX Qwen3 0.6B 4bit',
  url: 'https://huggingface.co/mlx-community/Qwen3-0.6B-4bit',
  framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
  memoryRequirement: 650_000_000,
  supportsThinking: true,
});
```

The native MLX engine uses its fixed router priority. The facade also exposes
`MLX.unregister()`, `MLX.isRegistered()`, and `MLX.isAvailable()`.
