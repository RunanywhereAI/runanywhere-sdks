# @runanywhere/web-onnx

**ONNX/Sherpa WASM backend for the RunAnywhere Web SDK** — embeddings, STT, TTS, and VAD in the browser.

---

## Installation

```bash
npm install @runanywhere/web@0.20.11 @runanywhere/web-onnx@0.20.11
```

See the [Web SDK README](../../README.md) for bundler configuration and cross-origin isolation headers.

---

## Usage

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';
import { ONNX } from '@runanywhere/web-onnx';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
await ONNX.register();
await RunAnywhere.completeServicesInitialization();

const transcript = await RunAnywhere.transcribe(audioSamples, {
  sampleRate: 16_000,
});
```

See the [Web SDK README](../../README.md) for model lifecycle and Vite setup.

---

## Support

- [Web SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
