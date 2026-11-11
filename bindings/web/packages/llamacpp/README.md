# @runanywhere/web-llamacpp

**Llama.cpp WASM backend for the RunAnywhere Web SDK** — LLM, GGUF embeddings, VLM, LoRA, tools, and structured output in the browser.

---

## Installation

```bash
npm install @runanywhere/web@0.20.27 @runanywhere/web-llamacpp@0.20.27
```

See the [Web SDK README](../../README.md) for bundler configuration and cross-origin isolation headers.

---

## Usage

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
await LlamaCPP.register({ acceleration: 'auto' });
await RunAnywhere.completeServicesInitialization();

const stream = await RunAnywhere.generateStream({
  prompt: 'Write a haiku about local AI.',
  maxTokens: 64,
});
for await (const token of stream.stream) {
  renderToken(token);
}
```

See the [Web SDK README](../../README.md) for model lifecycle and Vite setup.

`LlamaCPP.accelerationMode` reports `'cpu'`, `'webgpu'`, or `null` when the
device is unknown. It can be `null` before registration or after a worker
crash. A healthy device probe after the next successful model load publishes
the recovered worker mode.

This changes the previous non-null return type. Existing TypeScript callers
with a `'cpu' | 'webgpu'` annotation must allow `null`, or use the inferred
type and handle the unknown state.

```typescript
const mode = LlamaCPP.accelerationMode;
console.log(mode ?? 'unknown');
```

---

## Support

- [Web SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
