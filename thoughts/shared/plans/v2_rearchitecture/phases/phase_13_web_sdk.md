# Phase 13 — Web SDK migration + Web example app

> Goal: rewire `sdk/runanywhere-web/` to use the new commons C core
> compiled to WebAssembly, with proto3 on the wire. Ship the whole
> stack as a single `racommons.wasm` + a small TS glue layer. Retire
> v1 TypeScript abstractions. Rewrite the web example app.

---

## Prerequisites

- Phase 7 delivered the static-plugin build path that WASM consumes.
- Phase 5's protobuf schemas are stable.

---

## What this phase delivers

1. **Single WASM artifact** — `racommons.wasm` built via Emscripten
   from the commons source with `RA_STATIC_PLUGINS=ON`, statically
   linking the subset of backends that make sense in the browser
   (llama.cpp WASM build, sherpa-onnx WASM STT/VAD). MetalRT +
   WhisperKit excluded.

2. **Optional WebGPU variant** — second WASM artifact
   `racommons-webgpu.wasm` built against a WebGPU-enabled
   llama.cpp variant. Feature-detected at runtime; browsers without
   WebGPU fall back to the CPU variant.

3. **Sherpa-ONNX WASM** — reused from the existing build path
   (`sdk/runanywhere-web/wasm/sherpa/sherpa-onnx.wasm`). No change to
   how it loads.

4. **TypeScript proto3 codegen** — same `@bufbuild/protoc-gen-es`
   output shared with React Native (Phase 12).

5. **Public TS API** identical in *shape* to the React Native
   public API — the difference is under-the-hood transport (WASM
   module calls vs TurboModule).

6. **Web example app** at `examples/web/` rewritten against the new
   SDK. Vite-based build.

---

## Exact file-level deliverables

### Package structure

```text
sdk/runanywhere-web/
├── package.json                             UPDATED
├── packages/
│   ├── core/
│   │   ├── package.json
│   │   ├── src/
│   │   │   ├── index.ts                     public re-exports
│   │   │   ├── runAnywhere.ts               bootstrap() — fetches + instantiates wasm
│   │   │   ├── wasm/
│   │   │   │   ├── loader.ts                WASM instantiation + feature-detect
│   │   │   │   ├── bindings.ts              generated C→JS shims via embind
│   │   │   │   ├── memory.ts                heap helper (allocate/free, copy in/out)
│   │   │   │   └── jsi.ts                   streaming pump
│   │   │   ├── proto/                       @bufbuild/protoc-gen-es output
│   │   │   ├── llm/, stt/, tts/, vad/, vlm/, rag/, voiceAgent/
│   │   │   └── errors/
│   │   ├── wasm/
│   │   │   ├── racommons.js                 emitted by emscripten
│   │   │   ├── racommons.wasm
│   │   │   ├── racommons-webgpu.js          (optional)
│   │   │   ├── racommons-webgpu.wasm
│   │   │   └── sherpa/
│   │   │       ├── sherpa-onnx.js
│   │   │       └── sherpa-onnx.wasm
│   │   ├── dist/                            tsc output
│   │   └── tsconfig.json
│   └── node-compat/                         optional Node.js consumer (server-side)
│       └── package.json
├── wasm/                                    commons build output landing zone
├── scripts/
│   ├── build-web.sh                         UPDATED — new flags, single invocation path
│   ├── codegen-proto.sh
│   └── release.sh
└── README.md                                UPDATED
```

### Build script shape

```bash
#!/usr/bin/env bash
# scripts/build-web.sh
# Usage: ./build-web.sh [--webgpu] [--debug] [--clean]

set -euo pipefail
WEBGPU=0; DEBUG=0
for arg in "$@"; do
  case "$arg" in
    --webgpu)  WEBGPU=1 ;;
    --debug)   DEBUG=1 ;;
    --clean)   rm -rf build-wasm packages/core/wasm/*.wasm ;;
  esac
done

emcmake cmake -S ../runanywhere-commons -B build-wasm \
    -DCMAKE_BUILD_TYPE=$([[ $DEBUG == 1 ]] && echo Debug || echo Release) \
    -DRA_STATIC_PLUGINS=ON \
    -DRA_WASM=ON \
    -DRA_WASM_WEBGPU=$([[ $WEBGPU == 1 ]] && echo ON || echo OFF) \
    -DRA_BUILD_TESTS=OFF

cmake --build build-wasm -j
cp build-wasm/racommons.{js,wasm} packages/core/wasm/

# TypeScript
cd packages/core && npm run build:ts
```

### WASM module shape

Emscripten build exposes `ra_*` C functions via `EXPORTED_FUNCTIONS`
and `ccall`/`cwrap`. The TS wrapper reaches them through
`Module.cwrap('ra_llm_create', 'number', ['number', 'number', 'number'])`
etc.

For the streaming side we avoid `cwrap` per call and use a
preallocated heap region:

```ts
export class LLMSession {
  private handle: number;
  private buf: number;
  private bufCap = 2048;

  private constructor(handle: number) {
    this.handle = handle;
    this.buf = Module._malloc(this.bufCap);
  }

  static async create(config: LLMConfig): Promise<LLMSession> {
    const bytes = config.toBinary();
    const cfgPtr = copyToHeap(bytes);
    const outPtrPtr = Module._malloc(4);
    const status = Module._ra_llm_create(cfgPtr, bytes.length, outPtrPtr);
    const handle = Module.HEAPU32[outPtrPtr >> 2];
    Module._free(cfgPtr);
    Module._free(outPtrPtr);
    if (status !== RA_STATUS_OK) throw new RAError(status);
    return new LLMSession(handle);
  }

  async* generate(prompt: Prompt): AsyncGenerator<LLMEvent, void, void> {
    const promptBytes = prompt.toBinary();
    const promptPtr = copyToHeap(promptBytes);
    const startSt = Module._ra_llm_start(this.handle, promptPtr, promptBytes.length);
    Module._free(promptPtr);
    if (startSt !== RA_STATUS_OK) throw new RAError(startSt);

    const outLenPtr = Module._malloc(4);
    try {
      while (true) {
        Module.HEAPU32[outLenPtr >> 2] = this.bufCap;
        let status = Module._ra_llm_next(this.handle, this.buf, this.bufCap, outLenPtr);
        if (status === RA_STATUS_BUFFER_TOO_SMALL) {
          this.bufCap = Module.HEAPU32[outLenPtr >> 2];
          Module._free(this.buf);
          this.buf = Module._malloc(this.bufCap);
          Module.HEAPU32[outLenPtr >> 2] = this.bufCap;
          status = Module._ra_llm_next(this.handle, this.buf, this.bufCap, outLenPtr);
        }
        if (status !== RA_STATUS_OK) throw new RAError(status);
        const len = Module.HEAPU32[outLenPtr >> 2];
        const bytes = Module.HEAPU8.subarray(this.buf, this.buf + len);
        const proto = Ra_Idl_LlmEvent.fromBinary(bytes);
        const ev = LLMEvent.fromProto(proto);
        if (!ev) continue;
        yield ev;
        if (ev.type === 'end') break;
        await microtaskYield();   // let UI breathe
      }
    } finally {
      Module._free(outLenPtr);
    }
  }

  close(): void {
    Module._ra_llm_destroy(this.handle);
    Module._free(this.buf);
  }
}
```

### Pthread / atomics

If `-sUSE_PTHREADS=1` is set (for multi-threaded models), the
Emscripten build requires:
- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`
- Served over HTTPS or `localhost`.

We document this in the README; the example app's Vite config sets
the headers in dev; the production consumer needs to set them on
their own server.

### Web example app (examples/web/)

```text
examples/web/runanywhere_ai/
├── package.json                       depends on sdk/runanywhere-web workspaces
├── vite.config.ts                     sets COOP/COEP headers; copies wasm to public/
├── index.html
├── src/
│   ├── main.tsx                       React 19
│   ├── App.tsx
│   ├── pages/
│   │   ├── ChatPage.tsx
│   │   ├── VoiceAgentPage.tsx
│   │   └── SettingsPage.tsx
│   ├── components/
│   ├── hooks/
│   │   ├── useLLMSession.ts
│   │   └── useVoiceAgent.ts
│   └── styles/
└── public/
    └── (wasm assets copied by vite plugin)
```

### Deletions

```text
sdk/runanywhere-web/packages/*/src/legacy/                  DELETE
sdk/runanywhere-web/packages/*/src/adapters/callbacks*      DELETE
sdk/runanywhere-web/wasm/old/                               DELETE
examples/web/**/old_*                                       DELETE
```

### Tests

```text
packages/core/src/__tests__/
  ├── llmSession.spec.ts               — jest; uses a Node-side WASM loader
  ├── voiceAgent.spec.ts
  ├── codec.spec.ts                    — proto round-trip
  └── bootstrap.spec.ts

examples/web/runanywhere_ai/e2e/
  └── app.spec.ts                      — Playwright
```

---

## Implementation order

1. **Build the commons WASM** with a single backend first (llama.cpp
   CPU). Confirm `racommons.wasm` loads in a browser, exports all
   `ra_*` symbols, and a trivial `ra_status_string(0)` call works.

2. **Add sherpa-onnx WASM** — reuse the existing script path; merge
   outputs into the same bundle.

3. **Add WebGPU variant** behind a flag. Feature-detect at runtime.

4. **Codegen protobuf** with `@bufbuild/protoc-gen-es` — shared
   output with RN (same command).

5. **Write `loader.ts`** that picks the right WASM bundle at
   bootstrap.

6. **Write `memory.ts`** helpers for heap copy in/out.

7. **Write public classes** one primitive at a time. Re-use
   streaming pattern.

8. **Write the example app** in Vite + React 19.

9. **Add Playwright e2e** on top of the example app.

10. **CI** update `.github/workflows/web-sdk-release.yml`.

---

## API changes

### New public TS API

Identical shape to React Native's:

```ts
import { RunAnywhere } from '@runanywhere/web';

await RunAnywhere.bootstrap();
const session = await RunAnywhere.createLLMSession({ modelId: 'qwen3-4b-q4_k_m' });
for await (const ev of session.generate({ messages: [...] })) { … }
```

### Removed

- Old `fetch`-based RPC shims (if any).
- Callback-register APIs for streaming events.
- Pre-Phase-7 multi-module dynamic loading (there's one WASM module,
  period).

---

## Acceptance criteria

- [ ] `./scripts/build-web.sh --setup` produces `racommons.wasm`
      under ≤10 MB gzipped (CPU-only variant; WebGPU variant ≤12 MB).
- [ ] `npm test` in `packages/core` green under Node with WASM
      loaded.
- [ ] Example app loads, runs LLM chat in Chrome, Safari, and
      Firefox latest.
- [ ] Voice agent first-audio in browser ≤ 200 ms (looser than
      native; limited by Web Audio buffering).
- [ ] Playwright e2e green on Chromium + Firefox + WebKit.
- [ ] `.github/workflows/web-sdk-release.yml` + `web-app.yml` (new)
      green.
- [ ] No `MessageChannel`/`postMessage` for primitive streaming;
      everything is direct WASM calls.
- [ ] WebGPU variant is opt-in; bundle size of the default variant
      does not include WebGPU code paths (verified by size diff
      between the two `.wasm`s).

## Validation checkpoint — frontend major

See `testing_strategy.md`. Phase 13 runs:

- **Compilation.**
  ```bash
  cd sdk/runanywhere-web
  ./scripts/build-web.sh --setup                                # wasm + sherpa + ts
  ./scripts/build-web.sh --webgpu                               # optional variant
  npm run typecheck                                             # strict TS
  npm run lint                                                  # ESLint
  npm test                                                      # jest
  (cd ../../examples/web/runanywhere_ai && npm run build)
  ```
  All exit 0 with **zero ESLint errors, zero TS errors, zero
  emscripten warnings**.
- **WASM feature coverage.** `wasm-nm` (or `emcc --help`) shows
  every `ra_*` symbol exported; no missing entry points.
- **Example app runs in Chrome + Firefox + Safari.** Chat + voice
  agent smoke in each browser via Playwright.
- **Playwright e2e green** on chromium + firefox + webkit.
- **COOP/COEP headers set in example's Vite config.** Confirmed
  by a curl to the dev server.
- **Feature parity.** Every Web SDK feature pre-Phase-13 works
  post-Phase-13.
- **Bundle size.** Default `racommons.wasm` ≤ 10 MB gzipped;
  webgpu variant ≤ 12 MB. Reported in CI.
- **Node-compat package smoke.** `require('@runanywhere/web')` in
  a Node script at least loads and exposes the proto types; used
  for server-side tests.
- **CI.** `.github/workflows/web-sdk.yml` + `web-app.yml` green.

**Fix-as-you-go**: any emscripten deprecation warning surfaced
during the wasm build gets resolved in this phase's PRs (fixing
the cmake flag or vendoring a small patch) — not deferred.

---

## What this phase does NOT do

- No Node.js SDK other than a minimal `node-compat` package used
  for Jest tests. Full Node support (for server-side agents) is a
  follow-up.
- No service worker / background worker variant. Main thread +
  pthreads only.
- No React Native Web shared build. The web SDK is its own package.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| WASM bundle size balloons when multiple backends are linked | High | Default build links only `llamacpp` + `sherpa_onnx` (chosen in Phase 7). Others behind `--` flags. Document size budget in README |
| WebGPU availability is inconsistent across browsers | High | Feature-detect; CPU variant is the safe default. WebGPU is strictly additive |
| `-sUSE_PTHREADS=1` requires COOP/COEP headers on the embedding site | High | Documented extensively in README; example Vite config sets the headers in dev. Production embedders have to configure their host |
| `Module._malloc`/`_free` churn per streaming call adds GC-like jitter | Medium | Pre-allocate the stream buffer in the session constructor; reuse. Same pattern as other frontends |
| Safari lags on a specific Emscripten feature (e.g., SIMD) | Medium | Build a non-SIMD fallback variant; select at runtime. Size cost acceptable |
| Browser memory limits cap the model size loadable on-device | High | Document model-size guidance; a 4B-param GGUF Q4 is ~2.4 GB, barely fits in a browser tab. Smaller quantisations or tiny models recommended for web |
| Proto3 TS codegen output differs slightly between `@bufbuild/protoc-gen-es` and `protoc-gen-ts`, confusing devs looking at RN vs Web | Low | Pin `@bufbuild` for both frontends; document the choice |
| Playwright tests flake on model download (network) | Medium | Pre-fetch and cache the model in a fixture step; gate e2e tests on the cached path existing |
