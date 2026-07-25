# RunAnywhere Web SDK

Strictly typed, on-device AI infrastructure for browser applications. The Web
SDK exposes the same generated-proto and Swift-shaped concepts as the mobile
SDKs while keeping each native inference backend in an independent npm package
and self-contained WebAssembly module.

This is a browser SDK intended for Vite, webpack, and equivalent ESM-aware
bundlers. Its generated modules are not a server-side Node.js runtime.

## Packages

There are exactly three publishable Web packages:

| Package | Responsibility | Native artifacts |
| --- | --- | --- |
| `@runanywhere/web` | Backend-neutral lifecycle, generated types, model registry, downloads, storage, events, cross-backend orchestration, and browser helpers | `racommons.{js,wasm}` (commons only) |
| `@runanywhere/web-llamacpp` | llama.cpp LLM, GGUF embeddings, VLM, LoRA, tools, and structured output | CPU and WebGPU/Asyncify `racommons-llamacpp` variants |
| `@runanywhere/web-onnx` | ONNX Runtime embeddings plus Sherpa-ONNX STT, TTS, and VAD | `racommons-onnx-sherpa.{js,wasm}` |

`@runanywhere/web/browser`, `@runanywhere/web/backend`, and
`@runanywhere/web/internal` are entrypoints of the core package, not additional
packages. Applications use the package root and `/browser`. Backend packages
integrate through the narrow `/backend` contract. `/internal` is core-private.

Each WASM is self-contained; backends do not share symbols or import one
another. Applications install only the backends they need.

## Install

```bash
# Core plus every browser backend
npm install @runanywhere/web @runanywhere/web-llamacpp @runanywhere/web-onnx

# LLM/GGUF embeddings/VLM only
npm install @runanywhere/web @runanywhere/web-llamacpp

# Speech/ONNX only
npm install @runanywhere/web @runanywhere/web-onnx
```

Keep the three package versions compatible. Backend peer dependencies declare
the supported core version range.

## Initialize

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

Production initialization also accepts the client API key and HTTPS base URL
issued for browser/mobile distribution. Browser-bundled credentials are public
client configuration, not server secrets.

After registering and loading a compatible model through the lifecycle API,
use the flat Swift-shaped operations:

```ts
const stream = await RunAnywhere.generateStream({
  prompt: 'Explain why on-device inference improves privacy.',
  maxTokens: 128,
});

for await (const token of stream.stream) {
  renderToken(token);
}

const transcript = await RunAnywhere.transcribe(audioSamples, {
  sampleRate: 16_000,
});

await RunAnywhere.speak('This audio was synthesized on device.');
```

## Public surfaces

- Lifecycle and models: `initialize`, `shutdown`, `registerModel`,
  `downloadModel`, `loadModel`, `unloadModel`, `currentModel`, and registry
  queries.
- LLM and tools: `generate`, `generateStream`, cancellation, structured output,
  and tool calling.
- Speech and voice: batch/streaming STT, TTS synthesis/playback, VAD, and the
  cross-backend Voice Agent.
- Vision: image/video-frame processing and cancellation through the llama.cpp
  VLM provider.
- RAG: ONNX-backed embeddings, local document indexing/retrieval, and
  llama.cpp answer generation.
- Storage: OPFS model persistence plus optional File System Access helpers.
- Browser helpers from `@runanywhere/web/browser`: `AudioCapture`,
  `AudioPlayback`, `AudioFileLoader`, `VideoCapture`, and capability detection.

All model, lifecycle, modality, event, environment, and error contracts come
from generated `@runanywhere/proto-ts` types. External input should begin as
`unknown` and be validated before it crosses into WASM.

## Browser and server requirements

- WebAssembly and modern JavaScript modules.
- OPFS for persistent, origin-scoped model storage.
- Web Audio/MediaDevices for microphone, playback, and camera flows.
- WebGPU plus Asyncify for the accelerated llama.cpp artifact; the SDK selects the
  CPU artifact when those capabilities are unavailable.
- Cross-origin isolation for `SharedArrayBuffer` and threaded artifacts.

Serve the application with:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

Safari does not support `credentialless`; use `require-corp` responses or the
COI service-worker pattern from the Web example application.

### Vite

```ts
import { defineConfig } from 'vite';

export default defineConfig({
  assetsInclude: ['**/*.wasm'],
  optimizeDeps: {
    exclude: ['@runanywhere/web', '@runanywhere/web-llamacpp', '@runanywhere/web-onnx'],
  },
  server: {
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  },
});
```

The backend exclusions preserve package-relative `import.meta.url` resolution
for their JS/WASM assets.

## Build artifacts

The publish gate requires these non-empty pairs:

```text
packages/core/wasm/racommons.{js,wasm}
packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}
packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}
packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}
```

Build from the Web SDK workspace root:

```bash
npm run build:wasm -- --core
npm run build:wasm -- --llamacpp
npm run build:wasm -- --webgpu
npm run build:wasm -- --onnx
# or all four:
npm run build:wasm:all

npm run typecheck
npm run lint
npm run test
npm run build
```

The maintained browser smoke suite verifies independent module registration.
The opt-in release journey additionally downloads real models and exercises
LLM CPU/WebGPU, VLM, STT batch/streaming, TTS playback, VAD, Voice Agent, RAG,
storage persistence, settings reinitialization, model switching, cancellation,
and retry behavior:

```bash
npm run test:browser
npm run test:browser:release
```

## Security and runtime state

- Never log or persist API keys, authorization headers, tokens, or
  credential-bearing URLs.
- `VITE_*` values are embedded into the public browser bundle; use only client
  credentials intended for distribution.
- A downloaded model is not a successful inference. UI and release checks must
  separately prove registered backend, loaded model, real output, and supported
  cancellation/retry states.
- Missing backends, unavailable WebGPU, and failed models remain explicit typed
  errors or unavailable states; they are not silent successes.

## License

Copyright (c) 2025 RunAnywhere, Inc. This package is distributed under the
custom RunAnywhere License included in the package's `LICENSE` file.
