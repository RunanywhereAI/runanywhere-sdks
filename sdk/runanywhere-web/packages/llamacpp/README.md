# @runanywhere/web-llamacpp

**Llama.cpp WASM backend for the RunAnywhere Web SDK** — LLM, GGUF embeddings, VLM, LoRA, tools, and structured output in the browser.

---

## Installation

```bash
npm install @runanywhere/web@0.20.11 @runanywhere/web-llamacpp@0.20.11
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

---

## Support

- [Web SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
