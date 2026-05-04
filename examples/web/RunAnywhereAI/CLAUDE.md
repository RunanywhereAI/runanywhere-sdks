# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A vanilla TypeScript single-page application (no React/Vue/Angular) demonstrating the RunAnywhere Web SDK. All DOM manipulation is imperative — views render via `innerHTML` assignment and manual event listener wiring. The app runs on-device AI inference entirely in-browser using WASM (llama.cpp for LLM/VLM/Embeddings, sherpa-onnx for STT/TTS/VAD).

## Development Commands

```bash
npm install          # Install dependencies
npm run dev          # Start Vite dev server (port 5173)
npm run build        # Production build → dist/
npm run preview      # Preview production build locally

# Verification scripts
bash scripts/smoke.sh                  # SDK API call coverage check + build
bash scripts/verify.sh                 # Clean verification: npm ci + build
REFRESH_WASM=1 bash scripts/verify.sh  # Rebuild WASM before verify
REQUIRE_WASM=1 bash scripts/verify.sh  # Fail if WASM artifacts missing
```

There are no automated tests — only a manual test plan at `tests/web-sdk-test-suite.md`. There is no linter configured. TypeScript type-checking happens via the compiler (`noEmit: true`).

## SDK Integration

The app does **not** use npm packages for the SDK. Instead, Vite aliases in `vite.config.ts` resolve SDK imports directly from the monorepo workspace:

- `@runanywhere/web` → `sdk/runanywhere-web/packages/core/src/index.ts`
- `@runanywhere/web-llamacpp` → `sdk/runanywhere-web/packages/llamacpp/src/index.ts`
- `@runanywhere/web-onnx` → `sdk/runanywhere-web/packages/onnx/src/index.ts`
- `@runanywhere/proto-ts` → `sdk/runanywhere-proto-ts/src/`

App code imports those package roots directly. The `server.fs.allow` setting expands Vite's file server to the entire workspace root.

The SDK has two backend packages that register at startup:
- **LlamaCPP** (`packages/llamacpp/`) — LLM text generation, VLM, embeddings, tool calling, diffusion. Uses llama.cpp compiled to WASM.
- **ONNX** (`packages/onnx/`) — STT (Whisper), TTS (Piper), VAD (Silero). Uses sherpa-onnx compiled to WASM.

## Boot Sequence (`src/main.ts`)

1. **Cross-origin isolation**: `SharedArrayBuffer` is required for multi-threaded WASM. Chrome/Firefox get it from server headers (`vite.config.ts:71-78`). Safari uses a service worker fallback (`public/coi-serviceworker.js`) that injects COOP/COEP headers — the page reloads once on first visit.
2. **SDK init**: Dynamic `import()` of core SDK → `RunAnywhere.initialize()` → dynamic import and `.register()` of LlamaCPP and ONNX backends → `RunAnywhere.restoreLocalStorage()`. If WASM isn't built, the error is swallowed and the app runs in UI-only "demo mode".
3. **App shell**: `buildAppShell()` in `app.ts` creates the 9-tab DOM structure and initializes all views.

## Architecture

### Tab System (`src/app.ts`)

Nine tabs, each initialized by an `init*Tab(el)` function that returns a `TabLifecycle` with optional `onActivate`/`onDeactivate` callbacks. `switchTab()` manages activation/deactivation and shows a model-switch banner when navigating between tabs that use different `ModelCategory` values.

| Tab | View File | SDK Surfaces Used | ModelCategory |
|-----|-----------|-------------------|---------------|
| Chat | `views/chat.ts` | `TextGeneration.generateStream()`, `ToolCalling.generateWithTools()` | Language |
| Vision | `views/vision.ts` | `VideoCapture`, `VLMWorkerBridge.shared.process()` | Multimodal |
| Voice | `views/voice.ts` | `AudioCapture`, `VAD`, `ExtensionPoint.requireProvider('stt'/'llm'/'tts')`, `VoiceAgentStreamAdapter` | Language |
| Transcribe | `views/transcribe.ts` | `AudioCapture`, `STT.transcribe()`, `STT.transcribeFile()`, `VAD` | SpeechRecognition |
| Speak | `views/speak.ts` | `TTS.synthesize()`, `AudioPlayback` | SpeechSynthesis |
| Documents | `views/documents.ts` | `Embeddings.embed()`, `TextGeneration.generate()` | Language |
| Storage | `views/storage.ts` | `ModelManager`, `RunAnywhere.importModelFromFile()` | (none) |
| Solutions | `views/solutions.ts` | `RunAnywhere.solutions.run({ yaml })` | (none) |
| Settings | `views/settings.ts` | (none — UI config only) | (none) |

### View Pattern

Every view follows the same imperative pattern:
1. `init*Tab(el)` assigns the panel element to a module-scoped `container`
2. `container.innerHTML = \`...\`` stamps the entire view HTML
3. DOM references cached via `container.querySelector()`
4. Event listeners attached to cached references
5. `ModelManager.onChange(callback)` subscriptions update UI reactively
6. Returns `TabLifecycle` for resource management (stop camera, cancel generation, stop audio)

### State Management

No global state store. State lives in two places:
- **Module-level variables** in each `views/*.ts` file (isolated per ES module)
- **Singleton services**: `ConversationsStore` (localStorage persistence with observer pattern) and `ModelManager` (re-exported from SDK, observable via `.onChange()`)

### Services (`src/services/`)

- **`model-manager.ts`**: Registers the model catalog (10 models across LLM/VLM/STT/TTS/VAD) at module load time via `RunAnywhere.registerModel()`. Injects the VLM Web Worker URL via Vite's `?worker&url` import. Exports `ensureVADLoaded()` which auto-downloads Silero VAD with `{ coexist: true }`.
- **`conversations-store.ts`**: Multi-conversation persistence to localStorage. Observer pattern via `onChange(fn)` returning an unsubscribe function. Auto-titles from first user message. `updateLastAssistantContent()` updates the last assistant message in-place during streaming.

### Components (`src/components/`)

- **`model-selection.ts`**: Modal bottom sheet for model download/load/delete. Handles quota checking via `ModelManager.checkDownloadFit()` and eviction dialogs. Subscribes to `ModelManager.onChange()` for live state updates (download progress, etc.).
- **`dialogs.ts`**: Three imperative dialog primitives appended to `document.body`: `showToast()`, `showConfirmDialog()` (returns `Promise<boolean>`), `showEvictionDialog()` (returns `Promise<string[] | null>`).

### CSS Architecture (`src/styles/`)

No external CSS framework. Three layered files:
- `design-system.css` — CSS custom properties (dark theme default, light theme via `prefers-color-scheme`). Primary accent: `#FF5500`.
- `commons.css` — Utility classes (flex, grid, spacing, typography) and shared semantic patterns (`.status-badge`, `.spinner`, `.btn-ghost`).
- `components.css` — All component and view-specific styles centralized in one file.

## Key Data Flows

### Chat (streaming LLM)
```
user types → sendMessage() → TextGeneration.generateStream(text, opts)
  → for-await token loop → renderMarkdown() into bubble
  → ConversationsStore.updateLastAssistantContent() per token
  → resultPromise → appendMetrics(tok/s, count, latency)
```

### Voice Pipeline (VAD → STT → LLM → TTS)
```
micCapture.start() → VAD.processSamples(chunk)
  → VAD.onSpeechActivity(Ended) → VAD.popSpeechSegment()
  → feedTurn(audio) into composed transport
  → STT.transcribe() → emit userSaid
  → TextGeneration.generateStream() → emit assistantToken per token
  → TTS.synthesize(fullText) → emit audio event
  → AudioPlayback.play() → onended → startListening() (loop)
```

### VLM (off-main-thread)
```
camera.captureFrame(256) → VLMWorkerBridge.shared.process(rgbPixels, w, h, prompt)
  → postMessage to VLM Web Worker → WASM inference
  → worker response → display result text
```

## Build Configuration

**Vite plugin** (`copyWasmPlugin` in `vite.config.ts:28-55`): After production build, copies three WASM binaries into `dist/assets/` from the SDK workspace. Missing WASM files produce warnings, not errors.

**WASM files required at runtime**:
- `racommons-llamacpp.wasm` (from `packages/llamacpp/wasm/`)
- `racommons-llamacpp-webgpu.wasm` (same directory, optional — used when WebGPU available)
- `sherpa-onnx.wasm` (from `packages/onnx/wasm/sherpa/`)

To build these WASM artifacts, use the Web SDK build script from the repo root:
```bash
cd sdk/runanywhere-web/
./scripts/build-web.sh --build-wasm --llamacpp --onnx
```

**Deployment** (`vercel.json`): Configures COOP/COEP headers and SPA fallback rewrite for Vercel hosting.

## Runtime Dependencies

Only two npm runtime dependencies:
- `protobufjs` — proto serialization for `VoiceEvent` messages in the voice pipeline
- `long` — 64-bit integer support required by protobufjs
