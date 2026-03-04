# @runanywhere/web-llamacpp

LLM, VLM, tool calling, structured output, embeddings, and diffusion backend for the [RunAnywhere Web SDK](https://www.npmjs.com/package/@runanywhere/web) — powered by [llama.cpp](https://github.com/ggerganov/llama.cpp) compiled to WebAssembly.

> **Peer dependency:** Requires [`@runanywhere/web`](https://www.npmjs.com/package/@runanywhere/web) `>=0.1.0-beta.0`

## Installation

```bash
npm install @runanywhere/web @runanywhere/web-llamacpp
```

## Quick Start

```typescript
import { RunAnywhere } from '@runanywhere/web';
import { LlamaCPP, TextGeneration } from '@runanywhere/web-llamacpp';

// 1. Initialize core SDK
await RunAnywhere.initialize({ environment: 'development' });

// 2. Register the llama.cpp backend
await LlamaCPP.register();

// 3. Load a GGUF model and generate
await TextGeneration.loadModel('/models/qwen2.5-0.5b-instruct-q4_0.gguf', 'qwen2.5-0.5b');
const result = await TextGeneration.generate('Explain quantum computing briefly.');
console.log(result.text);

// Stream tokens
for await (const token of TextGeneration.generateStream('Write a haiku.')) {
  process.stdout.write(token);
}
```

## Capabilities

| Feature | Class | Description |
|---------|-------|-------------|
| **Text Generation** | `TextGeneration` | LLM inference with streaming, system prompts, temperature, top-k/top-p |
| **Vision Language Models** | `VLM` | Multimodal inference (image + text) via llama.cpp mtmd — runs in a Web Worker |
| **Tool Calling** | `ToolCalling` | Function calling with typed definitions (Hermes-style and generic) |
| **Structured Output** | `StructuredOutput` | JSON schema-guided generation |
| **Embeddings** | `Embeddings` | Vector embedding generation with configurable normalization/pooling |
| **Diffusion** | `Diffusion` | Image generation (WebGPU, scaffold) |

## WASM Files

This package includes pre-built WASM binaries:

| File | Description |
|------|-------------|
| `wasm/racommons-llamacpp.wasm` | CPU variant (~3.7 MB) |
| `wasm/racommons-llamacpp-webgpu.wasm` | WebGPU-accelerated variant (~3.9 MB) |

The SDK automatically selects the WebGPU variant when available, falling back to CPU.

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
