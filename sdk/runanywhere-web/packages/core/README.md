# @runanywhere/web

**Core Web SDK for RunAnywhere** — backend-neutral lifecycle, model registry, downloads, and browser helpers for on-device AI in WASM.

---

## Installation

```bash
npm install @runanywhere/web@0.20.11
```

Add `@runanywhere/web-llamacpp` and/or `@runanywhere/web-onnx` for inference backends. See the [Web SDK README](../../README.md) for COOP/COEP headers, Vite config, and bundler setup.

---

## Usage

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
```

Register backends, then call `RunAnywhere.completeServicesInitialization()`. See the [Web SDK README](../../README.md) for full initialization and inference examples.

---

## Support

- [Web SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
