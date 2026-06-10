# @runanywhere/web-llamacpp

LLM, VLM, tool calling, and structured output backend for the [RunAnywhere Web SDK](https://www.npmjs.com/package/@runanywhere/web) — powered by [llama.cpp](https://github.com/ggerganov/llama.cpp) compiled to WebAssembly.

> **Peer dependency:** Requires [`@runanywhere/web`](https://www.npmjs.com/package/@runanywhere/web) `>=0.19.13 <1`

## Installation

```bash
npm install @runanywhere/web @runanywhere/web-llamacpp
```

## Quick Start

```typescript
import { RunAnywhere } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';

// 1. Initialize core SDK
await RunAnywhere.initialize({ environment: 'development' });

// 2. Register the llama.cpp backend
await LlamaCPP.register();

// 3. Load a GGUF model and generate through the core facade
RunAnywhere.importModel({
  id: 'qwen2.5-0.5b',
  name: 'Qwen 2.5 0.5B',
  localPath: '/models/qwen2.5-0.5b-instruct-q4_0.gguf',
});
await RunAnywhere.loadModel({ modelId: 'qwen2.5-0.5b' });
const result = await RunAnywhere.generate({
  prompt: 'Explain quantum computing briefly.',
});
console.log(result.text);

// Stream tokens
const stream = await RunAnywhere.generateStream({
  prompt: 'Write a haiku.',
});
for await (const token of stream.stream) {
  process.stdout.write(token);
}
```

## Capabilities

| Feature | Entry point | Description |
|---------|-------------|-------------|
| **Text Generation** | `RunAnywhere.generate` / `RunAnywhere.generateStream` | LLM inference with streaming, system prompts, temperature, top-k/top-p |
| **Vision Language Models** | `RunAnywhere.processImage` / `RunAnywhere.processImageStream` | Multimodal inference through llama.cpp mtmd and the shared C++ lifecycle |
| **Tool Calling** | `RunAnywhere.generateWithTools` | Function calling with typed definitions (Hermes-style and generic) |
| **Structured Output** | `RunAnywhere.generateStructured` / `RunAnywhere.generateStructuredStream` | JSON schema-guided generation |

## WASM Files

This package includes pre-built WASM binaries:

| File | Description |
|------|-------------|
| `wasm/racommons-llamacpp.wasm` | CPU variant (~5.8 MB in the current VLM-enabled build) |
| `wasm/racommons-llamacpp-webgpu.wasm` | WebGPU/JSPI variant (~6.7 MB in the current VLM-enabled build) |

The SDK automatically selects the WebGPU variant when `navigator.gpu`, `WebAssembly.promising`, and `WebAssembly.Suspending` are available, falling back to CPU.

Configure your bundler to serve these as static assets — see the [main SDK README](https://www.npmjs.com/package/@runanywhere/web) for Vite/Webpack examples.

> **Warning (Vite):** You must add `@runanywhere/web-llamacpp` to [`optimizeDeps.exclude`](https://vite.dev/config/dep-optimization-options#optimizedeps-exclude) in your `vite.config.ts`. Vite's pre-bundling breaks the `import.meta.url` paths the SDK uses to locate WASM files. See the [main SDK README](https://www.npmjs.com/package/@runanywhere/web#serve-wasm-files--cross-origin-isolation) for the full Vite config.

## Cross-Origin Isolation

Multi-threaded WASM requires `SharedArrayBuffer`, which needs Cross-Origin Isolation headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

See the [main SDK docs](https://www.npmjs.com/package/@runanywhere/web#cross-origin-isolation-headers) for platform-specific configuration.

## License

Apache 2.0
