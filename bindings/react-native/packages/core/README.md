# @runanywhere/core

**Core React Native SDK for RunAnywhere** — public API, model lifecycle, events, and native bridge to runanywhere-commons.

---

## Installation

```bash
npm install @runanywhere/core@0.20.11 react-native-nitro-modules
```

```bash
cd ios && pod install && cd ..
```

For iOS microphone capture, add `NSMicrophoneUsageDescription` to your app's `Info.plist`. See the [React Native SDK README](../../README.md) for full setup.

---

## Usage

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});

console.log('Ready:', RunAnywhere.isInitialized);
```

Install backend packages (`@runanywhere/llamacpp`, `@runanywhere/onnx`, etc.) and use core APIs for models and inference. See the [React Native SDK README](../../README.md).

> **Hermes:** consume SDK `AsyncIterable` streams with manual `[Symbol.asyncIterator]()` loops, not `for await...of`.

---

## Support

- [React Native SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
