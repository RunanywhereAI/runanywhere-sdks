# Electron SDK — Development

Contributor guide for building and testing `@runanywhere/electron` from source.

## Prerequisites

- Node.js ≥ 20 (dev headers arrive via `npm install`)
- A RunAnywhere commons + engines build with the Electron addon enabled
  (`-DRAC_BUILD_ELECTRON_ADDON=ON`) and, for downloads/auth/telemetry,
  **`-DRAC_DESKTOP_ADAPTER=ON`** (libcurl HTTP transport). Required for
  model downloads — see **HTTP transport (D4)** below.
- Package `os` field is `darwin` / `linux` / `win32` (not Windows-only). Local
  prebuilds are staged under `prebuilds/<platform>-<arch>/` (and
  `…-cuda` when building the NVIDIA variant)
- Windows CUDA builds additionally need MSVC + CUDA toolkit ≥ 12.4

## Build steps

From `sdk/runanywhere-electron`:

```bash
npm install
npm run build          # src/ -> dist/
npm run typecheck      # every project: src/, test/, scripts/, native/
npm run bundle:native  # copy the built .node (+ sidecars) into prebuilds/
npm test               # unit tests (hermetic, no native addon needed)
```

Everything in this package is TypeScript — the tests and the build scripts
included — so each lives in its own tsc project with its own out-dir:

| Project | Sources | Output |
|---|---|---|
| `tsconfig.json` | `src/` | `dist/` (the published package) |
| `tsconfig.test.json` | `test/` | `dist-test/` |
| `tsconfig.scripts.json` | `scripts/` | `dist-scripts/` |
| `tsconfig.native.json` | `native/test_*.ts` | `dist-native/` |

`npm test` runs `node --test` over `dist-test/unit`, and its `pretest` builds both
`dist/` and `dist-test/` first. `tsconfig.test.json` sets `rootDir: "test"` so a
compiled `dist-test/unit/x.test.js` still resolves `../../dist` — do not change it
to `"."`.

Feature tests need the addon, and most of them a downloaded model. Without either
they skip rather than fail:

```powershell
$env:RUNANYWHERE_NATIVE_PATH = '<path>/runanywhere_native.node'
npm run test:feature
```

The manual scripts are compiled the same way:

```bash
npm run build:scripts       # then: node dist-scripts/manual-resolve.js
npm run build:native-smoke  # then: node dist-native/test_addon.js <.node> <model.gguf>
```

See `native/CMakeLists.txt` and the commons build docs for compiling the native addon against `runanywhere-commons`.

### macOS (typical local addon)

**Fat** (default shipping shape today — backends linked into the `.node`):

```bash
# From the repo root. Desktop adapter is required for HTTP downloads.
cmake --preset macos-release -B build/electron-macos \
      -DRAC_BUILD_ELECTRON_ADDON=ON -DRAC_DESKTOP_ADAPTER=ON
cmake --build build/electron-macos --target runanywhere_native -j "$(sysctl -n hw.logicalcpu)"
# Stage into core prebuilds/ (and packages/*/prebuilds/ when shared plugins exist):
cd sdk/runanywhere-electron && npm run bundle:native
```

**Thin / Option A** (shared commons + dynamic plugins — Track A):

```bash
cmake --preset electron-macos
cmake --build --preset electron-macos -j "$(sysctl -n hw.logicalcpu)" \
  --target rac_commons runanywhere_llamacpp runanywhere_onnx runanywhere_sherpa runanywhere_native
cd sdk/runanywhere-electron && RA_NATIVE_DIR=../../build/electron-macos npm run bundle:native
```

`bundle:native` has a macOS branch (D3 folded into Track B7): fat builds stage
only `runanywhere_native.node` into `prebuilds/darwin-<arch>/`; thin/shared builds
also stage `librac_commons.dylib` into core and `librunanywhere_{llamacpp,onnx,sherpa}.dylib`
into each backend package. Missing plugins fall back to core-only without failing.

### Windows (MSVC — CI recipe; not cross-compilable from macOS)

CI (`electron-sdk-ci.yml`) is a **single matrix job** (`windows-2022` + `macos-14`)
that builds the **thin / Option A** presets and runs `loadPlugin` smoke. Fat-addon
lanes are no longer in CI; local fat builds still work via `windows-release` +
`RAC_STATIC_PLUGINS=ON` if you need them.

**Thin / Option A** (`electron-windows` preset — what CI runs):

```powershell
npx --yes node-gyp install
$ver = node -p "process.versions.node"
$dir = "$env:LOCALAPPDATA/node-gyp/Cache/$ver"

# Install native/ node deps first (node-addon-api).
Push-Location sdk/runanywhere-electron/native; npm install; Pop-Location

# libcurl for RAC_DESKTOP_ADAPTER (same as CI — static MSVC triplet).
& "$env:VCPKG_INSTALLATION_ROOT\vcpkg.exe" install curl:x64-windows-static

cmake --preset electron-windows `
  "-DCMAKE_TOOLCHAIN_FILE=$env:VCPKG_INSTALLATION_ROOT/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static `
  "-DRAC_NODE_DEV_DIR=$dir"
# Optional: -DRAC_BACKEND_SHERPA=OFF if the Windows Sherpa-ONNX archive is missing.
cmake --build --preset electron-windows `
  --target rac_commons runanywhere_llamacpp runanywhere_onnx runanywhere_sherpa runanywhere_native

# Artifacts (Release/ under multi-config VS):
#   build/electron-windows/sdk/runanywhere-commons/Release/rac_commons.dll
#   build/electron-windows/engines/*/Release/runanywhere_*.dll
#   build/electron-windows/sdk/runanywhere-electron/native/Release/runanywhere_native.node
# Stage rac_commons.dll beside the .node before LoadLibrary / require().
```

#### DELAYLOAD (`/DELAYLOAD:node.exe`) — do not extend casually

The thin `.node` still delay-loads **only** `node.exe` (N-API symbols from the
host). `win_delay_load_hook.cc` rewrites that name to the running process /
`node.dll`. Risks when combining with shared commons:

| Risk | Mitigation |
|---|---|
| Delay-loading `rac_commons.dll` | **Forbidden.** Commons is an eager IAT import; stage the DLL beside the `.node`. |
| Hook only handles `node.exe` | Never `/DELAYLOAD` plugin or onnx/sherpa sidecars through this hook. |
| Plugin `LoadLibrary` path | Plugins resolve `rac_commons.dll` via PATH / same-dir search — stage sidecars together. |
| Electron vs Node host | Hook already falls back to `GetModuleHandle(NULL)` — keep that; do not hard-code `electron.exe`. |

### Windows on ARM64 (Snapdragon X / X2 Elite) — the QHexRT NPU lane

A different build from the x64 Windows recipe above, because a different set of
engines can compile. **llama.cpp, ONNX and Sherpa do not build for win-arm64**
(ggml hard-errors "MSVC is not supported for ARM"; `FetchONNXRuntime.cmake` picks
its download by `CMAKE_SIZEOF_VOID_P==8` and would fetch the x64 runtime, failing
at link with LNK1112). The `windows-arm64-release` preset therefore turns them
off, and **QHexRT is the only engine on this host** — there is no CPU fallback,
which is exactly why a load that reports `actualBackend != QHEXRT` is a bug.

QHexRT needs a receipt-validated prebuilt tree before configure — the engine
decides routable-vs-shell at configure time, so staging it afterwards silently
gives you the not-routable shell. `stage_prebuilt_for_sdk.sh` is POSIX-only
(symlinked `current`, `ps -o lstart=`, `llvm-nm`, ELF `.a` names), so on Windows
the payload is published as a plain `versions/<64-hex-receipt>/` directory and
named explicitly:

```powershell
# node.lib must match the Node that will load the addon, so derive the version
# rather than pinning one.
npx --yes node-gyp install
$ver = node -p "process.versions.node"

cmake -S . -B build/electron-win-arm64 -G "Visual Studio 18 2026" -A ARM64 `
  -DRAC_BUILD_SHARED=ON -DRAC_STATIC_PLUGINS=OFF `
  -DRAC_BACKEND_QHEXRT=ON "-DQHEXRT_ROOT=<...>/engines/qhexrt/prebuilt/versions/<receipt>" `
  -DRAC_BACKEND_LLAMACPP=OFF -DRAC_BACKEND_ONNX=OFF -DRAC_RUNTIME_ONNXRT=OFF `
  -DRAC_BACKEND_SHERPA=OFF -DRAC_BUILD_PLATFORM=OFF `
  -DRAC_BUILD_ELECTRON_ADDON=ON -DRAC_ELECTRON_THIN_ADDON=ON `
  "-DRAC_NODE_DEV_DIR=$env:LOCALAPPDATA/node-gyp/Cache/$ver"

# rac_backend_qhexrt is the TARGET; runanywhere_qhexrt.dll is what it emits
# (OUTPUT_NAME). There is no runanywhere_qhexrt target to build.
cmake --build build/electron-win-arm64 --config Release `
  --target rac_commons rac_backend_qhexrt runanywhere_native
```

Configure prints `QHexRT engine discovered` + `Engine available: 1` when the
receipt validated; `Engine available: 0` means you are building the shell.

Stage the addon, the plugin, and the QAIRT runtime:

```powershell
$env:RA_NATIVE_DIR = "<repo>/build/electron-win-arm64/sdk/runanywhere-electron/native/Release"
$env:RA_QNN_RUNTIME_DIR = "<neurun>/build/qairt-runtime-248"   # the flat 6-file set
npm run bundle:native
```

`RA_QNN_RUNTIME_DIR` stages into **`packages/qhexrt/prebuilds/<plat>-<arch>/`**,
beside the plugin, because there is no `ADSP_LIBRARY_PATH` on Windows: the loader
resolves the HTP stub's dependencies through the DLL's own directory, and
`bridge.ts` prepends every registered plugin directory to `PATH` because QHexRT
opens `QnnHtp.dll` by bare name (a bare-name load searches the EXECUTABLE's
directory, never the addon's). All six files — the four DLLs, the
`libQnnHtpV81Skel.so`, and **`libqnnhtpv81.cat`** — go in that one directory. The
`.cat` is mandatory; without it the skel fails signature verification with no
error that names the catalog.

Two load-time compatibility axes, both silent until they fire: bundles are
arch-pinned (a `v79` binary does not *load* on `v81`), and the deployed QAIRT must
be **>=** the QAIRT that compiled the bundle (2.47-compiled bundle vs 2.41 runtime
= `err=0x1388`, message only in the backend's stderr).

Cross-repo preflight for all of the above:
`pwsh neurun/QHexRT/device_suites/run_windows_e2e.ps1 --preflight-only --qhexrt-prebuilt <dir>`.

### HTTP transport (D4)

Desktop Electron adapters (`posix_platform_adapter` / `win32_platform_adapter`)
leave `platform_adapter.http_download` / `http_download_cancel` **NULL on
purpose**. That async adapter slot is the Web/Emscripten download driver; filling
it incorrectly on desktop would bypass the shared libcurl path.

The correct desktop path is the process-wide HTTP **transport** vtable:

1. Build commons with **`-DRAC_DESKTOP_ADAPTER=ON`** (defines
   `RAC_ELECTRON_HAVE_DESKTOP` on the addon).
2. `initialize()` in `native/addon.cpp` calls
   `rac_desktop_http_transport_register()` after `rac_init()` — before backends
   load and before any control-plane handshake — so the download orchestrator can
   fetch models with no API key.

Do **not** implement WinHTTP/undici into the adapter `http_download` slot.

`macos-release` leaves `RAC_STATIC_PLUGINS` at its default (**OFF**) and
`RAC_BUILD_SHARED=OFF`. That is fine for the **current** fat addon: backends are
still linked into `runanywhere_native.node` via the CMake
`foreach` / `RAC_HAVE_BACKEND_*` loop in `native/CMakeLists.txt`, so flipping
`RAC_STATIC_PLUGINS` does not change the Electron link model today. When the
shared-commons spike uses `RAC_STATIC_PLUGINS=OFF` + `RAC_BUILD_SHARED=ON`, the
addon builds **thin** automatically (see Track A).

> **TODO (packaging Track A):** replace the compile-time `RAC_HAVE_BACKEND_*`
> fat-addon branch with runtime plugin loading (`rac_registry_load_plugin` +
> shared commons). Do not rewrite consumer docs to praise selective linking, or
> claim a multi-package Electron split is *shipping*, until that loop is gone and
> the spike in `thoughts/shared/plans/electron_sdk_packaging_split.md` §10 has
> passed. Until then, keep documenting the fat `.node` as the shipping shape.
>
> **Track B3–B6 (landed in TypeScript):**
> - Main-only ordered registration queue (`recordBackendPlugin` /
>   `RUNANYWHERE_PLUGIN_PATHS`). Host applies existing paths before RPC when
>   `thinAddon` is true; re-fork replays from main. **No**
>   `v3.registerBackendPlugin` / `loadPlugin` RPC.
> - Example app depends on `@runanywhere/electron-{llamacpp,onnx,sherpa}` and
>   calls `LlamaCPP.register(); ONNX.register(); Sherpa.register()` before fork.
> - `capabilities()` is runtime-derived from `listPlugins()` + `isThinAddon()`.
>   Fat addon still reports the three compile-linked engines; thin core-alone
>   reports `backends: []` and `ensure()` throws typed
>   `SDKException.noBackendEngines`.
> - `bridge.ts` resolves the addon lazily, searches macOS/Linux/Windows build
>   trees, and prepares `librac_commons` + plugin sidecar dirs for thin mode.

## GPU build (CUDA / NVIDIA)

The default build is CPU-only. To offload inference to an NVIDIA GPU, build commons with `-DRAC_GPU_CUDA=ON` (CUDA toolkit **≥ 12.4** and MSVC). At load time, llama.cpp auto-offloads layers that fit VRAM.

```powershell
# From the repo root. Set CMAKE_CUDA_ARCHITECTURES to your GPU (86 = RTX 30-series).
$env:NVCC_PREPEND_FLAGS = '-allow-unsupported-compiler'   # only if MSVC is newer than the CUDA toolkit officially supports
cmake -S . -B build/windows-cuda -G "Visual Studio 17 2022" -A x64 `
  -T cuda="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.6" `
  -DRAC_GPU_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 `
  -DRAC_BUILD_ELECTRON_ADDON=ON -DRAC_BUILD_BACKENDS=ON `
  -DRAC_DESKTOP_ADAPTER=ON -DRAC_BUILD_SHARED=OFF
cmake --build build/windows-cuda --config Release --target runanywhere_native --parallel
```

Do **not** require `-DRAC_STATIC_PLUGINS=ON` for Electron CUDA builds. The flag is
orthogonal to the current fat-addon link (see TODO above); presets that leave it
OFF still produce a working addon when backends are linked via
`RAC_HAVE_BACKEND_*`.

Place the built `runanywhere_native.node` in `prebuilds/win32-x64-cuda/` beside its DLLs: `cudart64_12.dll`, `cublas64_12.dll`, `cublasLt64_12.dll` (from the CUDA `bin/`) plus `onnxruntime.dll`, `onnxruntime_providers_shared.dll`, `sherpa-onnx-c-api.dll`.

Then run `npm run bundle:native` or copy manually. The demo's
`examples/electron/RunAnywhereAI/RunAnywhere AI (GPU).cmd` (or `npm run start:gpu`)
launches against that prebuild when `RA_GPU=1` / `--gpu` is set.

## Example demo

The example app is TypeScript (`src/main`, `src/preload`, `src/renderer`). From
`examples/electron/RunAnywhereAI`:

```bash
npm install
npm run build
npm start              # CPU
npm run start:gpu      # CUDA (Windows; requires the cuda prebuild)
npm run typecheck
npm run test:e2e       # Playwright shell tests
```

Windows shortcuts / launchers (clear `ELECTRON_RUN_AS_NODE`):

```cmd
"examples\electron\RunAnywhereAI\RunAnywhere AI.cmd"
"examples\electron\RunAnywhereAI\RunAnywhere AI (GPU).cmd"
```

Or point Electron at a staged native addon:

```cmd
set RUNANYWHERE_NATIVE_PATH=sdk\runanywhere-electron\prebuilds\win32-x64\runanywhere_native.node
npx electron examples/electron/RunAnywhereAI
```

When bundling into an Electron app, unpack native artifacts from the asar:

```jsonc
// electron-builder config
"asarUnpack": ["**/node_modules/@runanywhere/electron/prebuilds/**"]
```
