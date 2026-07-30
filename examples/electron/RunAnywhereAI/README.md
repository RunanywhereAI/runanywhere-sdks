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

> **Platform note:** Windows and Linux both run today. `run-demo.cmd` and `run-demo.sh` launch the matching prebuild from `sdk/runanywhere-electron/prebuilds/`. macOS is not covered by this demo path.

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

Every tab calls the v3 namespaced API. The app never holds a model handle, never
assembles a prompt, and never runs a bootstrap sequence before a verb works.

| Tab | SDK surface |
|-----|-------------|
| **Chat** | `llm.generateStream(messages, options)`. History goes over as `ChatMessage[]`, tokens arrive tagged `TEXT` or `THOUGHT`, and the metrics come off the `completed` event |
| **Structured** | `llm.generateStructured(prompt, schema, options)` (grammar-constrained JSON) |
| **Tools** | `llm.tools.register`, then `llm.generate(..., { toolChoice: 'REQUIRED' })`. The SDK runs the executor and the tab shows its result |
| **Vision** | `vlm.generateStream(image.file(path), prompt, options)` |
| **Embeddings** | `embeddings.embed([a, b])` with cosine similarity |
| **Knowledge** | `rag.open(embeddingModel, llmModel, config)`, then `ingest` / `queryStream` / `stats` / `clear` |
| **Voice** | `voice.createSession({ stt, llm, tts })`. It loads its own models, keeps a VAD resident, and streams `VoiceEvent`s |
| **VAD** | `vad.detect(audio.float32(...), options)`, which returns debounced speech segments |
| **Models** | `models.list` / `download` / `load` / `unload` / `register` / `state` |
| **Settings** | System prompt, temperature, `maxOutputTokens`, reasoning mode, encrypted API key via `secure.set` |

Default catalog models (`qwen2.5-0.5b`, `smolvlm-256m`, `minilm`, `whisper-tiny`, `piper-lessac`) auto-download on first use. Conversation history and settings persist to Electron `userData`.

### Electron's limits on the renderer surface

Two constraints come from Electron, not from the SDK.

`contextBridge` hands the page a frozen clone of whatever the preload exposes, and
it does not proxy accessors. So the SDK assembles `window.runanywhere` in the main
world and backs `isReady`, `version`, `deviceId`, `environment`, and `events` with
getters that call through the bridge. That needs
`contextBridge.executeInMainWorld`; on an Electron without it those five are
missing in the renderer, the SDK warns about it, and the verbs still work.

Symbol keys do not survive `contextBridge` either, which means `for await...of`
will not iterate a stream that came through it. Drive `next()` instead. See
`each()` in `renderer.js`.

Tool executors are page functions the SDK calls back through the bridge, so they
run in the renderer rather than in the utility host. A tool cannot reach the
native addon directly.

### Gaps this demo does not paper over

There is no control plane. `initialize({ apiKey, baseUrl, environment })` accepts
the key and the URL and then ignores them: the Electron SDK does not authenticate,
register a device, or report telemetry yet. `deviceId` is minted locally and kept
in the secure store.

There is no image generation either. `images.generate` throws, because no
diffusion backend is linked and `rac_diffusion_generate_proto` is not bound in the
addon.

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
| **Web example** | [examples/web/RunAnywhereAI](../../web/RunAnywhereAI/) |
| **Android example** | [examples/android/RunAnywhereAI](../../android/RunAnywhereAI/README.md) |
| **Discord** | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |
| **Issues** | [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues) |
| **Email** | founders@runanywhere.ai |

---

## License

This project is licensed under the RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](../../../LICENSE) for details.
