# Web Example App (RunAnywhereAI, web-next)

## Info

Svelte 5 + Vite + TypeScript demo app for the web-next SDK. Screens in `src/lib/screens/`: Chat, Vision, Stt, Tts, Voice, Rag, More, Settings; shared UI in `src/lib/components/`, stores in `src/lib/stores/`, model catalog/prompts/tools in `src/lib/{catalog,prompts,tools}.ts`.

Example apps are UI-only: thin `RunAnywhere.*` SDK calls, no business logic, no SDK-internal knowledge. Global rules: see repo-root AGENTS.md.

- SDK deps are NOT npm packages here — `vite.config.ts` aliases `@runanywhere/web`, `@runanywhere/web/internal`, `@runanywhere/web-llamacpp`, `@runanywhere/web-onnx` to `sdk/runanywhere-web-next/packages/*/dist/*.js`, and `@runanywhere/proto-ts` to `sdk/shared/proto-ts/src`. The SDK must be built (`./run sdk web build`) before this app runs.
- Dev server sets COOP/COEP headers (`Cross-Origin-Embedder-Policy: credentialless`) — required for `SharedArrayBuffer`; workers use ES module format.
- `/api` is proxied to the dev backend (Railway) so backend calls are same-origin; set `VITE_RUNANYWHERE_BASE_URL` to the dev origin to route through it.

## Build Info

```bash
# PREREQUISITES (repo root): SDK TS built + WASM staged into sdk packages
./run sdk web build            # npm install + typecheck + build → packages/*/dist
./run sdk web build-wasm       # scripts/build/wasm/bundle.sh → packages/*/wasm (needs EMSDK)

# From examples/web-next/RunAnywhereAI/
npm install
npm run dev          # Vite dev server at http://localhost:5173
npm run build        # production build
npm run preview
npm run check        # svelte-check --tsconfig ./tsconfig.json

# From repo root (dev entry point)
./run example web dev
./run example web build
./run example web clean        # removes dist/ and .vite/
```

Requires WASM prebuilt in the SDK packages (`sdk/runanywhere-web-next/packages/*/wasm/`) and cross-origin isolation; Safari needs a `coi-serviceworker.js` polyfill when served without COOP/COEP.

## Work Ground

Short dated notes for other agents. Add gotchas here; prune stale ones.

- 2026-07-05: SDK edits are not hot-picked-up — aliases point at `dist/`, so re-run `npm run build` (or `./run sdk web build`) in `sdk/runanywhere-web-next` after any core/backend TS change.
- 2026-07-05: Chrome 86+ baseline; WebGPU LLM variant is separate from the CPU WASM build — Qwen2-VL is forced onto CPU WASM (NaN logits on WebGPU f16 M-RoPE).
