# RunAnywhere Electron demo

A tabbed desktop app exercising the `@runanywhere/electron` SDK end-to-end over
the isolated utility-process architecture (main forks the native addon host; the
renderer talks to it over a MessagePort).

## Features

| Tab | What it shows | SDK surface |
| --- | --- | --- |
| **Chat** | Multi-turn streaming conversation | `generate` |
| **Structured** | Typed JSON extraction (grammar-constrained) | `generateObject` |
| **Tools** | Tool selection with filled arguments | `generateToolCall` |
| **Vision** | Caption a picked image | `loadVLM` / `generateVlm` |
| **Embeddings** | Cosine similarity of two sentences | `loadEmbedder` / `embed` |
| **Voice** | Hold-to-talk: mic → STT → LLM → TTS → speaker | `transcribe` / `generate` / `synthesize` + Web Audio |

Models are catalog ids, auto-downloaded on first use (`qwen2.5-0.5b`,
`smolvlm-256m`, `minilm`, `whisper-tiny`, `piper-lessac`).

## Run

```powershell
# from sdk/runanywhere-electron
$env:RUNANYWHERE_NATIVE_PATH = '<repo>\build\windows-release\sdk\runanywhere-electron\native\Release\runanywhere_native.node'
npx electron examples/demo-app
# (unset ELECTRON_RUN_AS_NODE first if your shell sets it)
```

## Headless self-test

`RA_SELFTEST=1` runs Chat → Structured → Tools → Embeddings through the app's
real code paths (no window, no mic) and exits `0` on pass / `1` on failure — used
to verify the SDK integration in CI-style checks:

```powershell
$env:RA_SELFTEST = '1'
$env:RUNANYWHERE_NATIVE_PATH = '<...>\runanywhere_native.node'
npx electron examples/demo-app   # prints [selftest] ... ALL PASS, exit 0
```
