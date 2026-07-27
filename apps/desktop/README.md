# RunAnywhere AI (Windows desktop)

The shipping desktop app built on `@runanywhere/electron`. Everything runs
**on-device** — chat, reasoning, your own knowledge base (RAG), voice, and vision.
No prompt, document, or audio leaves the machine.

This is the app we package and publish; `examples/electron/RunAnywhereAI` remains
the SDK's example/demo.

## Run it

Double-click the **RunAnywhere AI** desktop shortcut, or:

```
apps\desktop\RunAnywhere AI.cmd          # CPU (default)
apps\desktop\RunAnywhere AI.cmd --gpu    # CUDA prebuild (needs an NVIDIA driver stack)
```

or from a terminal:

```
cd apps/desktop
npm start          # CPU
npm run start:gpu  # CUDA
```

Prerequisites: the SDK must be built (`cd sdk/runanywhere-electron && npm install && npm run build`)
and a native prebuild present under `sdk/runanywhere-electron/prebuilds/`.

> If the window never appears, check that `ELECTRON_RUN_AS_NODE` isn't set — it makes
> `electron.exe` run as plain Node. The `.cmd` launcher clears it.

## Layout

| File | Purpose |
| --- | --- |
| `main.js` | Electron main: forks the utility host (native addon), owns the window + local JSON store |
| `preload.js` | Loads the SDK preload (`window.runanywhere`) and exposes `window.appStore` |
| `renderer.js` / `index.html` | The UI — Chat, Models, Settings, Structured, Tools, Vision, Embeddings, Knowledge, Voice, VAD |
| `assets/make-icon.js` | Regenerates `assets/icon.ico` + `icon.png` (zero deps) — `npm run icon` |

Conversations, settings, and custom models persist as JSON under
`%APPDATA%\RunAnywhere AI\`.

## Compute device

CPU by default. The CUDA prebuild is used only when explicitly requested
(`--gpu` / `RA_GPU=1`) **and** present — loading it without an NVIDIA driver stack
fails, so it is never the silent default. The active device is shown in the header.

## Self-test

Runs the real code paths headlessly and exits 0/1:

```
set RA_SELFTEST=1 && npx electron .
```

## Packaging (not wired yet)

Publishing to the Microsoft Store goes through a Win32 NSIS installer built with
electron-builder. When that lands, the native `.node` and its sidecar DLLs must be
`asarUnpack`ed — native modules cannot be loaded from inside `app.asar`.
