# RunAnywhere AI — Electron Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%20%28preview%29-0078D4?style=flat-square&logo=windows&logoColor=white" alt="Windows preview" />
  <img src="https://img.shields.io/badge/Electron-Desktop-47848F?style=flat-square&logo=electron&logoColor=white" alt="Electron" />
  <img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" />
</p>

**Desktop sample for the [@runanywhere/electron SDK](../../../sdk/runanywhere-electron/).** Chat with streaming and metrics, structured JSON output, tool calling, vision, embeddings, voice (STT → LLM → TTS), and VAD—using an isolated utility-process architecture (main process forks the native addon host; renderer talks over a MessagePort).

> **Platform note:** This example targets **Windows** today. Prebuilt native addons ship under `sdk/runanywhere-electron/prebuilds/`. macOS and Linux support is not covered by this demo path.

---

## Requirements

| Item | Minimum |
|------|---------|
| **OS** | Windows 10/11 (x64) |
| **Node.js** | 22.12+ recommended (for `npx electron`) |
| **Repo checkout** | Full monorepo clone |
| **Optional GPU build** | CUDA prebuild at `prebuilds/win32-x64-cuda/` (see SDK README) |

---

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
```

No separate `npm install` inside the example is required for the default path—the demo launches via `npx electron` from the repo root.

### 2. Run the demo (recommended — Windows)

Double-click or run from a terminal:

```cmd
examples\electron\RunAnywhereAI\run-demo.cmd
```

The script:

- Clears `ELECTRON_RUN_AS_NODE` (required for a visible window)
- Sets `RUNANYWHERE_NATIVE_PATH` to the **CPU prebuild**:

  ```
  sdk\runanywhere-electron\prebuilds\win32-x64\runanywhere_native.node
  ```

- Launches `npx electron examples/electron/RunAnywhereAI` from the repo root

**GPU variant:** If you built the CUDA prebuild, use `run-demo-gpu.cmd` instead (points at `prebuilds/win32-x64-cuda/`).

### 3. Manual launch (PowerShell)

```powershell
cd runanywhere-sdks
$env:ELECTRON_RUN_AS_NODE = $null
$env:RUNANYWHERE_NATIVE_PATH = "$PWD\sdk\runanywhere-electron\prebuilds\win32-x64\runanywhere_native.node"
npx electron examples/electron/RunAnywhereAI
```

Rebuild the SDK native addon only if you changed C++ sources:

```powershell
cd sdk\runanywhere-electron
npm run build
```

Then point `RUNANYWHERE_NATIVE_PATH` at your built `runanywhere_native.node` or use the matching prebuild path above.

---

## Features

| Tab | SDK surface |
|-----|-------------|
| **Chat** | `generateStream` with conversation history, markdown, per-message metrics |
| **Structured** | `generateStructured` (grammar-constrained JSON) |
| **Tools** | `generateToolCall` with demo tool selection |
| **Vision** | `loadVLM` / `generateVlm` on a picked image |
| **Embeddings** | `loadEmbedder` / `embed` with cosine similarity |
| **Voice** | Hold-to-talk: `transcribe` → `generate` → `synthesize` |
| **VAD** | `createVad` / `vadProcess` with threshold slider |
| **Models** | Catalog, download progress, load/unload |
| **Settings** | System prompt, temperature, max tokens, DPAPI-encrypted API key |

Default catalog models (`qwen2.5-0.5b`, `smolvlm-256m`, `minilm`, `whisper-tiny`, `piper-lessac`) auto-download on first use. Conversation history and settings persist to Electron `userData`.

---

## Project structure

```
RunAnywhereAI/
├── main.js           # Main process, native host fork, IPC
├── preload.js        # Renderer bridge (contextIsolation)
├── renderer.js       # UI logic and SDK calls
├── index.html        # Workbench layout
├── run-demo.cmd      # CPU launch script (happy path)
├── run-demo-gpu.cmd  # CUDA prebuild launch script
└── README.md
```

---

## Headless self-test

For CI-style verification without opening a window:

```powershell
$env:RA_SELFTEST = '1'
$env:RUNANYWHERE_NATIVE_PATH = '<repo>\sdk\runanywhere-electron\prebuilds\win32-x64\runanywhere_native.node'
npx electron examples/electron/RunAnywhereAI
# Prints [selftest] ... ALL PASS and exits 0 on success
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Window does not appear | Unset `ELECTRON_RUN_AS_NODE`; use `run-demo.cmd` |
| Native addon not found | Confirm prebuild path; rebuild SDK with `npm run build` in `sdk/runanywhere-electron` |
| GPU script fails | Build CUDA prebuild first, or fall back to `run-demo.cmd` |
| Model download errors | Check network; models fetch on first use |

---

## Related links

| Resource | Link |
|----------|------|
| **Electron SDK** | [sdk/runanywhere-electron/README.md](../../../sdk/runanywhere-electron/README.md) |
| **Web example** | [examples/web/RunAnywhereAI](../../web/RunAnywhereAI/README.md) |
| **Android example** | [examples/android/RunAnywhereAI](../../android/RunAnywhereAI/README.md) |
| **Discord** | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |
| **Issues** | [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues) |
| **Email** | founders@runanywhere.ai |

---

## License

This project is licensed under the RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](../../../LICENSE) for details.
