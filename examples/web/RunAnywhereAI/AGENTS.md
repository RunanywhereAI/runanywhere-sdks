# RunAnywhere Web Example — AGENTS.md

## Overview

This is the browser validation app for the Web SDK. It consumes the Swift-aligned public facade from `@runanywhere/web`, backend registration packages from `@runanywhere/web-llamacpp` and `@runanywhere/web-onnx`, and browser helpers from `@runanywhere/web/browser`.

The example may break when the SDK facade changes; update it to the latest API rather than preserving old compatibility imports.

## Architecture and Dependency Rules

The demo consumes exactly three publishable Web packages:

- `@runanywhere/web` for backend-neutral SDK lifecycle and public inference
  facades; `@runanywhere/web/browser` is its browser-helper entrypoint.
- `@runanywhere/web-llamacpp` for LLM/VLM backend registration and CPU/WebGPU
  execution variants.
- `@runanywhere/web-onnx` for ONNX/Sherpa STT, TTS, and VAD registration.

Views may import the public roots and `@runanywhere/web/browser`. They must not
import `@runanywhere/web/internal`, `@runanywhere/web/backend`, deep-import package source, import one
backend from another, or implement SDK model routing/storage/inference rules in
UI code. Put reusable SDK behavior in the lowest applicable SDK package and
keep each view focused on DOM state and user-flow orchestration.

## Types, Inputs, Errors, and Credentials

- Keep strict TypeScript. No `any`, `@ts-ignore`, raw JSON assumptions, or
  hand-written copies of proto DTOs/enums. Use generated
  `@runanywhere/proto-ts` types for models, lifecycle, events, storage,
  modalities, environments, and errors. Use local discriminated unions only
  for browser UI state.
- Treat settings, localStorage, IndexedDB, files, URLs, media, model downloads,
  and network/JSON responses as external input. Validate and narrow before
  calling the SDK; show structured, actionable errors without exposing stack
  traces. Chat history is persistent, origin-scoped IndexedDB data; the current
  Web RAG index is session-only and must not be presented as persistent. Keep
  app-owned chat records in IndexedDB; `RunAnywhere.storage` owns model
  artifacts and storage analysis, not arbitrary application records.
- Never log or persist API keys/tokens. API keys entered in Settings are
  session-only and are sent directly by the browser. Persist only explicitly
  allowlisted non-secret settings, and validate them before use. The configured
  endpoint must explicitly support browser CORS.
- This example is intentionally static and client-only. Do not add `api/`,
  `server/`, serverless functions, proxies, embedded credentials, or secret
  environment variables. A developer who needs secret-bearing control-plane
  calls must build, authenticate, secure, rate-limit, and deploy that backend
  outside this example, then expose an appropriate browser-facing contract.
- UI copy and controls must be truthful. Render distinct typed idle, loading,
  ready, success, unavailable, cancelled, and error states. Never show a fake
  toggle, treat a download as inference success, or silently label a failed
  backend/model as ready.

## Commands

Run from `examples/web/RunAnywhereAI/`.

Vite 8 requires Node `20.19+` or `22.12+`; the example mirrors that constraint
in its `engines` field. Production output is pinned to Chrome 86 syntax
compatibility in `vite.config.ts` so a Vite major upgrade cannot silently raise
the Web SDK's documented browser floor. This build target does not polyfill
missing browser APIs; WebGPU remains optional and falls back to the CPU backend.

```bash
npm run lint
npm run typecheck
npm run build
npm run dev -- --host 127.0.0.1
```

Production Vercel releases use `npm run release:deploy`. No Vercel secrets,
serverless functions, relay, or WAF configuration are required by this static
example. The command builds all four Web SDK WASM variants, verifies `dist`,
builds an isolated static Vercel prebuilt output, rejects unexpected functions,
and deploys that exact output. After deployment, verify COOP/COEP headers,
`crossOriginIsolated`, SPA routing, and all four canonical JS/WASM pairs.

Keep `scripts/` limited to its two distinct workflows: `release.sh` owns static
release verification/staging/deployment, and `sync-solutions.mjs` owns generated
solution configuration. Extend one of those tools or use an npm command rather
than adding another single-use wrapper.

## SDK Surfaces By View

| Tab | View File | Current SDK Surface |
| --- | --- | --- |
| Chat | `views/chat.ts` | `RunAnywhere.generateStream`, `RunAnywhere.generateWithTools` |
| Advanced | `app.ts` (`initAdvancedHub`) | navigation hub for the modality demos; no direct inference logic |
| Vision | `views/vision.ts` | `VideoCapture`, model lifecycle, `RunAnywhere.visionLanguage.processImageStream`, cancellation |
| Voice | `views/voice.ts` | `VoiceAgentMicDriver`, `RunAnywhere.initializeVoiceAgentWithLoadedModels`, `RunAnywhere.streamVoiceAgent` |
| Transcribe | `views/transcribe.ts` | `AudioCapture`, `RunAnywhere.transcribe`, `RunAnywhere.transcribeStream` |
| Speak | `views/speak.ts` | `RunAnywhere.speak`, `RunAnywhere.stopSpeaking` |
| VAD | `views/vad.ts` | `AudioCapture`, `RunAnywhere.streamVAD` |
| Documents | `views/documents.ts` | `RunAnywhere.ragIngest`, `RunAnywhere.ragQuery`, RAG diagnostics |
| Storage | `views/storage.ts` | `RunAnywhere.storage`, `RunAnywhere.modelRegistry`, `RunAnywhere.loadModel` |
| Solutions | `views/solutions.ts` | `RunAnywhere.solutions` |
| Benchmarks | `views/benchmarks.ts` | repeated generation benchmarks across short, medium, and long prompts |
| Settings | `views/settings.ts` | generation preferences plus validated production SDK/backend reinitialization |

## Browser Requirements

The Vite dev server sets COOP/COEP headers for SharedArrayBuffer. Runtime WASM assets are copied from the SDK workspace when present — there are **four independently built execution artifacts** across three packages (CPU and WebGPU are separate llama.cpp builds):

| WASM artifact | Owning package | Loaded by | Used by views |
| --- | --- | --- | --- |
| `racommons.{js,wasm}` | `@runanywhere/web` (core) | `RunAnywhere.initialize()` | All views (commons facade state) |
| `racommons-llamacpp.{js,wasm}` (CPU) | `@runanywhere/web-llamacpp` | `LlamaCPP.register()` | Chat, Vision, Documents (RAG answer generation) |
| `racommons-llamacpp-webgpu.{js,wasm}` (WebGPU) | `@runanywhere/web-llamacpp` | `LlamaCPP.register({ acceleration: 'webgpu' })` — runtime capability check picks one | Chat, Vision (when WebGPU+Asyncify available) |
| `racommons-onnx-sherpa.{js,wasm}` | `@runanywhere/web-onnx` | `ONNX.register()` | Voice, Transcribe, Speak, VAD, ONNX-backed embeddings/RAG |

STT/TTS/VAD run through the proto-byte adapters in `@runanywhere/web` core
against the registered Sherpa vtable inside `racommons-onnx-sherpa.wasm`;
there is no separate standalone speech provider path.

Every canonical `.js` file in the table is required Emscripten runtime glue,
not just build input. Vite may emit a hashed copy for the main-thread import;
pthread-enabled CPU/ONNX modules can also load a canonical self-name (for
example, `racommons.js`). The WebGPU/Asyncify release artifact is intentionally
non-threaded, but its canonical glue is still required. Production output must
therefore contain and serve all four canonical JS/WASM pairs with JavaScript
and `application/wasm` MIME types.

## Validation Standard

A passing build or app launch is only smoke validation. End-to-end modality validation requires browser launch, model download, model load, real inference, and reviewed logs/screenshots. Keep automated release coverage in `../../../sdk/runanywhere-web/tests/browser/`.

Before handoff, run `npm run lint`, `npm run typecheck`, and a production
`npm run build`, plus the SDK's typecheck, lint, unit, build, smoke browser
suite, and opt-in `npm run test:browser:release` real-model journey. Then use
Playwright, Puppeteer, or the in-app browser against the actual built app. A full-demo
release must exercise navigation and honest empty/error states plus real LLM,
VLM, STT batch + streaming, TTS playback, VAD, Voice Agent, RAG/Documents,
Solutions, storage/persistence, model switching, Settings production
reinitialization, CPU fallback, and WebGPU where supported. Review console and
page errors, failed network requests, screenshots, COOP/COEP state, all four
JS/WASM pairs, and repeat production smoke/inference checks on the deployed
Vercel origin. Do not call the release complete from a build-only or
download-only result.
