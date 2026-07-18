# RunAnywhere Electron demo

A product-grade desktop sample for the `@runanywhere/electron` SDK, over the
isolated utility-process architecture (main forks the native addon host; the
renderer talks to it over a MessagePort). Conversation history + settings persist
to `userData`.

## Product features

- **Chat** with a conversation-history sidebar (new / select / delete, persisted),
  **markdown rendering**, streaming, and **per-message metrics** (tokens, tok/s,
  time-to-first-token) via `generateStream`.
- **Models** panel: the built-in catalog with downloaded/size status, **download
  with a progress bar**, and per-model **load / unload** (fires the events bus).
- **Settings** panel: system prompt, temperature, max-tokens, and an **API key
  stored encrypted** via the DPAPI secure store.

## Workbench tabs

| Tab | What it shows | SDK surface |
| --- | --- | --- |
| **Structured** | Typed JSON extraction (grammar-constrained) | `generateStructured` |
| **Tools** | Tool selection with filled arguments | `generateToolCall` |
| **Vision** | Caption a picked image | `loadVLM` / `generateVlm` |
| **Embeddings** | Cosine similarity of two sentences | `loadEmbedder` / `embed` |
| **Voice** | Hold-to-talk: mic → STT → LLM → TTS → speaker | `transcribe` / `generate` / `synthesize` |
| **VAD** | Hold-to-speak live voice-activity detection with a threshold slider | `createVad` / `vadProcess` |

Models are catalog ids, auto-downloaded on first use (`qwen2.5-0.5b`,
`smolvlm-256m`, `minilm`, `whisper-tiny`, `piper-lessac`).

## Run

```powershell
# from the repo root (build the SDK first: cd sdk/runanywhere-electron && npm run build)
$env:RUNANYWHERE_NATIVE_PATH = '<repo>\build\windows-release\sdk\runanywhere-electron\native\Release\runanywhere_native.node'
npx electron examples/electron/RunAnywhereAI
# (unset ELECTRON_RUN_AS_NODE first if your shell sets it)
```

## Headless self-test

`RA_SELFTEST=1` runs Chat (generateStream) → Structured → Tools → Embeddings →
Models (catalog/status) → Vision → secure store → VAD through the app's real code
paths (no window, no mic) and exits `0` on pass / `1` on failure — used to verify
the SDK integration in CI-style checks:

```powershell
$env:RA_SELFTEST = '1'
$env:RUNANYWHERE_NATIVE_PATH = '<...>\runanywhere_native.node'
npx electron examples/electron/RunAnywhereAI   # prints [selftest] ... ALL PASS, exit 0
```
