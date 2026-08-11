# RunAnywhere AI (Windows desktop)

The shipping desktop app built on `@runanywhere/electron`. Everything runs
**on-device** — chat, reasoning, your own knowledge base (RAG), voice, and vision.
No prompt, document, or audio leaves the machine.

This is the app we package and publish; `examples/electron/RunAnywhereAI` remains
the SDK's example/demo.

## Run it

Double-click the **RunAnywhere AI** desktop shortcut, or:

```bat
"examples\electron\RunAnywhereAI\RunAnywhere AI.cmd"
"examples\electron\RunAnywhereAI\RunAnywhere AI (GPU).cmd"
```

or from a terminal:

```bat
cd examples/electron/RunAnywhereAI
npm start          :: CPU
npm run start:gpu  :: CUDA
```

Prerequisites: the SDK must be built (`cd sdk/runanywhere-electron && npm install && npm run build`)
and a native prebuild present under `sdk/runanywhere-electron/prebuilds/`.

> If the window never appears, check that `ELECTRON_RUN_AS_NODE` isn't set — it makes
> `electron.exe` run as plain Node. The `.cmd` launcher clears it.

## Layout

TypeScript-only. Source under `src/`; build emits CommonJS main/preload and an ESM
renderer bundle under `out/`. `"main"` is `out/main/index.cjs`.

| Path | Purpose |
| --- | --- |
| `src/main/` | Electron main: forks the utility host (native addon), owns the window + local JSON store |
| `src/preload/` | Loads the SDK preload (`window.runanywhere`) and exposes `window.appStore` |
| `src/shared/model-catalog.ts` | The app's model table. Staged into the SDK by preload and by the utility host (`catalogPath`), which is what makes a catalog id resolvable in both processes |
| `src/renderer/` | The UI — Vite entry (`index.html` / `settings.html`) + feature views |
| `assets/make-icon.ts` | Regenerates `assets/icon.ico` + `icon.png` — `npm run icon` |

Conversations, settings, and custom models persist as JSON under
`%APPDATA%\RunAnywhere AI\` (or `~/Library/Application Support/RunAnywhere AI/` on macOS).

## Compute device

CPU by default. The CUDA prebuild is used only when explicitly requested
(`--gpu` / `RA_GPU=1`) **and** present — loading it without an NVIDIA driver stack
fails, so it is never the silent default. The active device is shown in the header.

## Self-test

Runs the real code paths headlessly and exits 0/1:

```bat
set RA_SELFTEST=1 && npx electron .
```

## Packaging

electron-builder config lives in `electron-builder.yml`:

| Platform | Targets |
| --- | --- |
| macOS | `dmg` + `zip`, arm64 |
| Windows | NSIS, x64 + arm64 |

```bash
npm run package        # host platform
npm run package:mac    # dmg + zip (arm64)
npm run package:win    # nsis (x64 + arm64)
```

Native artifacts under `@runanywhere/electron/prebuilds/` (and any future
`.node` / `.dylib` / `.dll` / `.so` / `plugins/`) are `asarUnpack`ed — they
cannot load from inside `app.asar`. Stage a prebuild first
(`cd sdk/runanywhere-electron && npm run bundle:native`).

Publishing / code signing is not wired yet; local packages are unsigned.
