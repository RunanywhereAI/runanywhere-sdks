# @runanywhere/onnx

**ONNX/Sherpa backend registration for the RunAnywhere React Native SDK** — installs native STT, TTS, and VAD providers; public speech APIs live in `@runanywhere/core`.

---

## Installation

```bash
npm install @runanywhere/core@0.20.27 @runanywhere/onnx@0.20.27
cd ios && pod install && cd ..
```

See the [React Native SDK README](../../README.md) for microphone permissions and platform setup.

---

## Usage

```typescript
import { RunAnywhere } from '@runanywhere/core';
import { ONNX } from '@runanywhere/onnx';

await RunAnywhere.initialize();
await ONNX.register();

// Register, download, load STT models and transcribe via @runanywhere/core
```

See the [React Native SDK README](../../README.md) for full STT/TTS/VAD examples.

---

## Support

- [React Native SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
