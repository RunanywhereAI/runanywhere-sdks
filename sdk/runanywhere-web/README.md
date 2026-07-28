# RunAnywhere Web SDK

Strictly typed, on-device AI for browser applications. The Web SDK exposes a Swift-shaped TypeScript facade over the same RACommons C/C++ infrastructure used by the mobile SDKs, with independently installable native backends and self-contained WebAssembly modules.

The packages target ESM-aware browser bundlers such as Vite and webpack. They are not a server-side Node.js inference runtime.

**Current release:** `0.20.11`

## Packages

| Package | Responsibility | Native artifacts |
| --- | --- | --- |
| `@runanywhere/web` | Backend-neutral initialization, lifecycle, model registry, downloads, OPFS storage, events, routing, and browser helpers | `racommons.{js,wasm}` |
| `@runanywhere/web-llamacpp` | llama.cpp LLM, GGUF embeddings, VLM, LoRA, tools, and structured output | CPU and WebGPU/Asyncify `racommons-llamacpp` variants |
| `@runanywhere/web-onnx` | ONNX Runtime embeddings plus Sherpa-ONNX STT, TTS, and VAD | `racommons-onnx-sherpa.{js,wasm}` |

`@runanywhere/web/browser`, `@runanywhere/web/backend`, and `@runanywhere/web/internal` are export entrypoints of the core package, not additional packages.

Each backend integrates only through the narrow `@runanywhere/web/backend` contract. Every WASM module includes the commons code it needs; there is no cross-WASM symbol sharing.

## Install

Install core plus only the backends your application needs. Pin compatible versions:

```bash
# Full SDK
npm install @runanywhere/web@0.20.11 @runanywhere/web-llamacpp@0.20.11 @runanywhere/web-onnx@0.20.11

# LLM, GGUF embeddings, and VLM only
npm install @runanywhere/web@0.20.11 @runanywhere/web-llamacpp@0.20.11

# Speech and ONNX embeddings only
npm install @runanywhere/web@0.20.11 @runanywhere/web-onnx@0.20.11
```

Keep all three package versions aligned. Backend peer dependencies declare the supported core version range.

## Quick start

```ts
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';
import { ONNX } from '@runanywhere/web-onnx';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});

await LlamaCPP.register({ acceleration: 'auto' });
await ONNX.register();
await RunAnywhere.completeServicesInitialization();
```

After registering backends and loading models through the core lifecycle API, use the flat public facade:

```ts
const generation = await RunAnywhere.generateStream({
  prompt: 'Explain why on-device inference improves privacy.',
  maxTokens: 128,
});

for await (const token of generation.stream) {
  renderToken(token);
}

const transcript = await RunAnywhere.transcribe(audioSamples, {
  sampleRate: 16_000,
});

await RunAnywhere.speak('This audio was synthesized locally.');
```

The same facade provides batch and streaming STT, TTS synthesis/playback, VAD, Voice Agent orchestration, VLM inference, RAG, storage, model switching, structured output, tool calling, and cancellation.

## Public entrypoints

| Import | Use for |
| --- | --- |
| `@runanywhere/web` | SDK operations and generated public types |
| `@runanywhere/web/browser` | Browser-only media and capability helpers |
| `@runanywhere/web/backend` | Backend package integration (not for apps) |
| `@runanywhere/web/internal` | Core diagnostics only — do not depend on this in apps |

Do not deep-import package source files. The package `exports` maps are the supported boundary.

## Browser requirements

On-device inference in the browser needs:

- WebAssembly and modern JavaScript modules
- OPFS for persistent, origin-scoped model storage
- Web Audio and MediaDevices for microphone, playback, and camera flows
- WebGPU plus Asyncify for the accelerated llama.cpp path (CPU fallback when unavailable)
- **Cross-origin isolation** for SharedArrayBuffer and threaded WASM

### Cross-origin isolation (required)

Serve the application and its static assets with:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

Also serve `.wasm` with `Content-Type: application/wasm`.

Safari does not support `credentialless`; use `require-corp` responses or the COI service worker pattern in the example app.

Model hosts must allow browser CORS. Any control-plane relay must be same-origin, fixed to an allowlisted upstream, and must never accept a request-controlled proxy destination.

For the browser support matrix, isolation troubleshooting, deployment CSP, static asset rules, and model memory guidance, see [docs/BROWSER_SUPPORT.md](./docs/BROWSER_SUPPORT.md) and [docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md).

### Vite

```ts
import { defineConfig } from 'vite';

export default defineConfig({
  assetsInclude: ['**/*.wasm'],
  optimizeDeps: {
    exclude: [
      '@runanywhere/web',
      '@runanywhere/web-llamacpp',
      '@runanywhere/web-onnx',
    ],
  },
  server: {
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  },
});
```

### Static WASM assets

Your deployment must serve every canonical `.js`/`.wasm` pair as real static files — never as an SPA HTML fallback. Threaded Emscripten workers require the canonical `.js` glue files at runtime.

## Example application

```bash
cd ../../examples/web/RunAnywhereAI
npm ci
npm run dev
```

The example demonstrates LLM (CPU and WebGPU), VLM, STT, TTS, VAD, Voice Agent, RAG, and model management with the required COOP/COEP headers.

## FAQ

**Why do I need cross-origin isolation?**  
Threaded WebAssembly uses `SharedArrayBuffer`, which browsers only expose in cross-origin isolated contexts.

**Can I run this in Node.js?**  
No. These packages target browser bundlers with WASM and OPFS. Use the Python SDK or CLI for server-side local inference.

**Which package version should I pin?**  
Use `0.20.11` for all three packages unless release notes specify otherwise. Mismatched core/backend versions may fail peer dependency checks.

**Where are models stored?**  
In the browser's Origin Private File System (OPFS), scoped to your origin.

## Support

- Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- Email: [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

## Contributing

Build, test, and release instructions for contributors: [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md).

## License

Copyright (c) 2025 RunAnywhere, Inc. Distributed under the [RunAnywhere License](../../LICENSE).
