# Web SDK — Development

Contributor guide for building, testing, and releasing `@runanywhere/web` and its backend packages.

## Build from source

Run from `bindings/web`:

```bash
npm ci

# TypeScript packages
npm run build

# One native artifact at a time
npm run build:wasm -- --core
npm run build:wasm -- --llamacpp
npm run build:wasm -- --webgpu
npm run build:wasm -- --onnx
npm run build:wasm -- --onnx-webgpu

# Or all five native artifacts (core + llama CPU/WebGPU + onnx CPU/WebGPU)
npm run build:wasm:all

# Speech ORT archives (CPU + WebGPU) + Sherpa — required before onnx builds
npm run vendor:wasm:speech
```

The WASM build scripts fail if required vendored static archives or canonical outputs are missing. Use the version-pinned vendor scripts under `wasm/scripts/` (`vendor-onnxruntime-wasm.sh` and `vendor-onnxruntime-wasm-webgpu.sh`); do not replace release inputs with silent stubs. Speech WebGPU release checklist: [ONNX_WEBGPU.md](./ONNX_WEBGPU.md).

## Runtime artifacts

Publishing expects these JavaScript/WebAssembly pairs, one per `build:wasm` flag:

```text
packages/core/wasm/racommons.{js,wasm}                        # --core
packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}           # --llamacpp  (CPU)
packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}    # --webgpu
packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}            # --onnx      (CPU/pthread)
packages/onnx/wasm/racommons-onnx-sherpa-webgpu.{js,wasm}     # --onnx-webgpu (ORT WebGPU EP)
```

The first four are mandatory; the ONNX WebGPU twin ships when speech acceleration is enabled (see [ONNX_WEBGPU.md](./ONNX_WEBGPU.md)).

CPU and WebGPU are separate llama.cpp builds owned by one npm package. ONNX Runtime and Sherpa-ONNX share one backend artifact because Sherpa uses ONNX Runtime.

`packages/onnx` must not publish `wasm/sherpa/**`. That standalone artifact no longer exists; the proto-byte path through `racommons-onnx-sherpa.wasm` is the only Sherpa surface.

The canonical `.js` files are required at runtime by threaded Emscripten workers. A deployment must serve every pair as a real static asset, never as an SPA HTML fallback.

## Quality and release gates

TypeScript is strict and builds must fail on type errors. External data begins as `unknown`, is validated, and is narrowed before it reaches SDK or WASM boundaries. Do not add `any`, `@ts-ignore`, unchecked JSON casts, or duplicate hand-written proto DTOs.

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

Each package's `prepack` rebuilds its declarations and rejects missing, empty, syntactically invalid, or malformed canonical assets. Inspect the final npm file list before publishing:

```bash
npm pack --dry-run -w packages/core
npm pack --dry-run -w packages/llamacpp
npm pack --dry-run -w packages/onnx
```

A successful build is only smoke validation. Browser release validation must launch the built example with COOP/COEP enabled, then prove model download, model load, real inference, visible output, and recovery/cancellation for every claimed modality:

```bash
npm run test:browser
npm run test:browser:release
```

The full release journey covers LLM CPU and WebGPU, VLM, STT batch and streaming, TTS playback, VAD, Voice Agent, RAG/Documents, storage persistence, model switching, Settings reinitialization, and error/retry states. Repeat the header, static-asset, registration, and representative inference checks on the deployed production origin.

## Security notes for contributors

- Never log or persist API keys, authorization headers, tokens, credential request bodies, or secret-bearing URLs.
- `VITE_*` values are embedded in public browser bundles. Use only client configuration deliberately issued for distribution.
- Keep `.env*.local`, traces, screenshots, recordings, and generated deployment state out of source control when they may contain credentials or user data.
- Validate URLs, model metadata, downloaded bytes, browser media, JSON, and persisted state before use.
- A downloaded model is not a successful inference. Readiness and UI state must distinguish unavailable, loading, ready, success, cancelled, and error states and provide a recovery path.
- Do not add trackers or third-party scripts without deliberate privacy and security review.

## Example application (validation)

```bash
cd example
npm ci
npm run typecheck
npm run build
npm run dev
```

`bindings/web/example` is the in-repo harness: it covers LLM streaming
only, and it is what the browser gates boot by default. Validating every
modality needs the full demo app, which lives in
[RunanywhereAI/runanywhere-web](https://github.com/RunanywhereAI/runanywhere-web);
point `RA_E2E_APP_DIR` at a checkout of it to run the release journey.
