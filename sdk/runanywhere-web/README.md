# RunAnywhere Web SDK

Strictly typed, on-device AI for browser applications. The Web SDK exposes a
Swift-shaped TypeScript facade over the same RACommons C/C++ infrastructure
used by the mobile SDKs, with independently installable native backends and
self-contained WebAssembly modules.

The packages target ESM-aware browser bundlers such as Vite and webpack. They
are not a server-side Node.js inference runtime.

## Packages

There are exactly three publishable Web SDK packages:

| Package | Responsibility | Native artifacts |
| --- | --- | --- |
| `@runanywhere/web` | Backend-neutral initialization, lifecycle, generated types, model registry, downloads, OPFS storage, events, routing, and browser helpers | `racommons.{js,wasm}` |
| `@runanywhere/web-llamacpp` | llama.cpp LLM, GGUF embeddings, VLM, LoRA, tools, and structured output | CPU and WebGPU/Asyncify `racommons-llamacpp` variants |
| `@runanywhere/web-onnx` | ONNX Runtime embeddings plus Sherpa-ONNX STT, TTS, and VAD | `racommons-onnx-sherpa.{js,wasm}` |

`@runanywhere/web/browser`, `@runanywhere/web/backend`, and
`@runanywhere/web/internal` are export entrypoints of the core package, not
additional packages. The shared `@runanywhere/proto-ts` module supplies
generated wire contracts and is a dependency, not a fourth Web SDK capability
package.

Each backend integrates only through the narrow `@runanywhere/web/backend`
contract. It does not import another backend or the broad core-private
`@runanywhere/web/internal` entrypoint. Every WASM module includes the commons
code it needs; there is no cross-WASM symbol sharing.

## Install

Install core plus only the backends the application needs:

```bash
# Full SDK
npm install @runanywhere/web @runanywhere/web-llamacpp @runanywhere/web-onnx

# LLM, GGUF embeddings, and VLM only
npm install @runanywhere/web @runanywhere/web-llamacpp

# Speech and ONNX embeddings only
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

After registering, downloading, and loading compatible models through the
core lifecycle API, use the flat public facade:

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

The same facade provides batch and streaming STT, TTS synthesis/playback, VAD,
Voice Agent orchestration, VLM inference, RAG, storage, model switching,
structured output, tool calling, and cancellation.

## Public entrypoints

- Application code imports SDK operations and generated public types from
  `@runanywhere/web`.
- Browser-only media and capability helpers come from
  `@runanywhere/web/browser`.
- Backend packages use `@runanywhere/web/backend`.
- `@runanywhere/web/internal` is reserved for core diagnostics and legacy
  harnesses; applications and backend packages must not depend on it.

Do not deep-import package source files. The package `exports` maps are the
supported boundary.

## Runtime artifacts

The publish gate requires these four canonical JavaScript/WebAssembly pairs:

```text
packages/core/wasm/racommons.{js,wasm}
packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}
packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}
packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}
```

CPU and WebGPU are separate llama.cpp builds owned by one npm package. ONNX
Runtime and Sherpa-ONNX share one backend artifact because Sherpa uses ONNX
Runtime. The previous standalone `wasm/sherpa/` bundle is not part of the
package surface.

The canonical `.js` files are required at runtime by threaded Emscripten
workers. A deployment must serve every pair as a real static asset, never as an
SPA HTML fallback.

## Browser and server requirements

- WebAssembly and modern JavaScript modules.
- OPFS for persistent, origin-scoped model storage.
- Web Audio and MediaDevices for microphone, playback, and camera flows.
- WebGPU plus Asyncify for the accelerated llama.cpp path; the SDK can select its
  CPU artifact when the accelerated path is unavailable.
- Cross-origin isolation for SharedArrayBuffer and threaded WASM.

Serve the application and its static assets with:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

Also serve `.wasm` with `Content-Type: application/wasm`. Safari does not
support `credentialless`; use `require-corp` responses or the COI service
worker pattern in `examples/web/RunAnywhereAI`.

For the browser support matrix, actionable isolation failures, deployment CSP,
canonical static asset rules, and model memory/download guidance, see
[docs/BROWSER_SUPPORT.md](./docs/BROWSER_SUPPORT.md) and
[docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md).

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

Model hosts must allow browser CORS. Control-plane relays must be same-origin,
fixed to an allowlisted upstream, and must never accept a request-controlled
proxy destination.

## Build from source

Run from `sdk/runanywhere-web`:

```bash
npm ci

# TypeScript packages
npm run build

# One native artifact at a time
npm run build:wasm -- --core
npm run build:wasm -- --llamacpp
npm run build:wasm -- --webgpu
npm run build:wasm -- --onnx

# Or all four native artifacts
npm run build:wasm:all
```

The WASM build scripts fail if required vendored static archives or canonical
outputs are missing. Use the version-pinned vendor scripts under
`wasm/scripts/`; do not replace release inputs with silent stubs.

## Quality and release gates

TypeScript is strict and builds must fail on type errors. External data begins
as `unknown`, is validated, and is narrowed before it reaches SDK or WASM
boundaries. Do not add `any`, `@ts-ignore`, unchecked JSON casts, or duplicate
hand-written proto DTOs.

Run the static and package gates:

```bash
npm run typecheck
npm run lint
npm run test
npm run build

npm run verify:package -w packages/core
npm run verify:package -w packages/llamacpp
npm run verify:package -w packages/onnx
```

Each package's `prepack` rebuilds its declarations and rejects missing, empty,
syntactically invalid, or malformed canonical assets. Inspect the final npm
file list before publishing:

```bash
npm pack --dry-run -w packages/core
npm pack --dry-run -w packages/llamacpp
npm pack --dry-run -w packages/onnx
```

A successful build is only smoke validation. Browser release validation must
launch the built example with COOP/COEP enabled, then prove model download,
model load, real inference, visible output, and recovery/cancellation for every
claimed modality:

```bash
npm run test:browser
npm run test:browser:release
```

The full release journey covers LLM CPU and WebGPU, VLM, STT batch and
streaming, TTS playback, VAD, Voice Agent, RAG/Documents, storage persistence,
model switching, Settings reinitialization, and error/retry states. Repeat the
header, static-asset, registration, and representative inference checks on the
deployed production origin.

## Security and runtime state

- Never log or persist API keys, authorization headers, tokens, credential
  request bodies, or secret-bearing URLs.
- `VITE_*` values are embedded in public browser bundles. Use only client
  configuration deliberately issued for distribution.
- Keep `.env*.local`, traces, screenshots, recordings, and generated deployment
  state out of source control when they may contain credentials or user data.
- Validate URLs, model metadata, downloaded bytes, browser media, JSON, and
  persisted state before use.
- A downloaded model is not a successful inference. Readiness and UI state must
  distinguish unavailable, loading, ready, success, cancelled, and error
  states and provide a recovery path.
- Do not add trackers or third-party scripts without deliberate privacy and
  security review.

## Example application

```bash
cd ../../examples/web/RunAnywhereAI
npm ci
npm run lint
npm run typecheck
npm run build
npm run dev -- --host 127.0.0.1
```

The example is the browser validation application for all supported modalities.
See its `AGENTS.md` for view ownership, credential rules, and the complete E2E
definition of done.

## License

Copyright (c) 2025 RunAnywhere, Inc. This SDK is distributed under the custom
[RunAnywhere License](../../LICENSE), including its permitted-user thresholds,
commercial-license requirement, attribution conditions, and incorporated
Apache License 2.0 terms.
