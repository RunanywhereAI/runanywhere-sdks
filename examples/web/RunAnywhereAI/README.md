# RunAnywhere AI - Web Example

Browser reference app for the RunAnywhere Web SDK. It demonstrates on-device chat, model storage, multimodal/voice UI surfaces, and a Vite build that consumes local SDK source packages.

## Clean-Clone Bring-Up

Prerequisites:

- Node.js 18+ and npm.
- Emscripten SDK (`emcc` on `PATH` or `EMSDK` exported) when rebuilding WASM artifacts.
- CMake and Ninja for `scripts/build-core-wasm.sh`.
- A Chromium-based browser for optional WebGPU and local-folder storage checks. Safari/Firefox can run CPU paths where supported.

From a fresh checkout:

```bash
cd examples/web/RunAnywhereAI
npm install

# Build or refresh the local llama.cpp WASM bundle when this checkout has no staged artifact.
cd ../../..
./scripts/build-core-wasm.sh
cd examples/web/RunAnywhereAI

npm run build
npm run preview
```

For reproducible CI-style verification, prefer `npm ci` when `package-lock.json` is present:

```bash
cd examples/web/RunAnywhereAI
npm ci
npm run build
```

## Local Artifacts

- `scripts/build-core-wasm.sh` writes `sdk/runanywhere-web/packages/llamacpp/wasm/racommons-llamacpp.js` and `.wasm`.
- WebGPU acceleration is optional and browser-dependent. The app falls back to CPU WASM when WebGPU is unavailable or disabled.
- ONNX-backed STT/TTS surfaces are present in the UI, but browser runtime support depends on the local Web SDK ONNX artifacts and browser capabilities.
- Cross-origin isolation is required for `SharedArrayBuffer`; the app registers `coi-serviceworker.js` for local preview flows.

## Verification

```bash
# Build gate and artifact checks.
bash scripts/verify.sh

# Functional smoke preflight.
bash scripts/smoke.sh
```

Use `REFRESH_WASM=1 bash scripts/verify.sh` to rebuild the root WASM artifact before the Vite build.

## Runtime Smoke

After `npm run preview`, open the printed local URL and exercise:

- Initialization: app shell renders and the acceleration badge appears when the SDK initializes.
- Registry/model list: model picker shows registered LLM, VLM, STT, TTS, and VAD models.
- Download/load/generate/stream/cancel: download a small LLM, load it, send a chat prompt, then switch tabs during generation to cancel.
- Storage: inspect downloaded models, delete one, and clear all models.
- Voice/RAG/manual flows: verify browser permissions and model requirements before marking these complete in the smoke matrix.
