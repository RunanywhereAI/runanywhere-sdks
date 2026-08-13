# `@runanywhere/electron-qhexrt`

QHexRT backend package for the Electron SDK — text generation on the **Qualcomm
Hexagon NPU**.

> [!WARNING]
> **No release of this package ships a native plugin yet, on any platform.** It
> installs and `register()` succeeds, but the recorded path has no binary behind
> it, so the engine never loads and the router can never select it. Published
> 0.20.16 and 0.20.17 are deprecated on npm for this reason. Depend on it only if
> an inert no-op is acceptable; do not expect NPU acceleration.

The only platform where this package can ever do work is **Windows on ARM64**
(Snapdragon X / X2 Elite, Hexagon `v81`). Everywhere else (macOS, Linux,
Windows x64) has no Hexagon NPU and no QAIRT HTP stack, so an inert package is
the permanent, correct end state there; the engine reports
`BACKEND_UNAVAILABLE` and a cross-platform app can depend on it unconditionally.

What is missing for win-arm64 is the build itself: no CMake preset enables
`RAC_BACKEND_QHEXRT`, and the `qhexrt_core.lib` / `qhexrt_host.lib` that the
engine links on that target have never been produced (every staged payload in
`engines/qhexrt/prebuilt/` is Android `arm64-v8a` only). See
`bindings/electron/AGENTS.md` for the full gap list.

## Usage (main process only)

```ts
import { QHexRT } from '@runanywhere/electron-qhexrt';
QHexRT.register(); // before RunAnywhereMain.connect()
```

Registration records `prebuilds/<platform>-<arch>/runanywhere_qhexrt.dll` in the
main-process queue; `RunAnywhereMain` copies it into `RUNANYWHERE_PLUGIN_PATHS`
at utility-host fork. There is no renderer RPC that can load a plugin.

## What a `prebuilds/win32-arm64/` payload must contain

This is the contract a real build has to satisfy. **No published version contains
it yet** (see the warning above); it is recorded here so the eventual build is
staged correctly rather than rediscovered.

The plugin **and** the flat QAIRT runtime it opens at load time:

| file | from |
|---|---|
| `runanywhere_qhexrt.dll` | this repo (`engines/qhexrt`) |
| `rac_commons.dll` | this repo — the thin addon's shared commons |
| `QnnHtp.dll`, `QnnSystem.dll`, `QnnHtpPrepare.dll`, `QnnHtpV81Stub.dll` | `<QAIRT>/lib/aarch64-windows-msvc/` |
| `libQnnHtpV81Skel.so`, `libqnnhtpv81.cat` | `<QAIRT>/lib/hexagon-v81/unsigned/` |

All in **one directory**. There is no `ADSP_LIBRARY_PATH` on Windows — the loader
resolves the stub's dependencies through the DLL's own directory, and the SDK
prepends every registered plugin directory to `PATH` because the engine opens
`QnnHtp.dll` by bare name at runtime.

**The `.cat` is not optional.** Without it the DSP skel fails signature
verification and the failure never names the catalog — it looks like a corrupt
model bundle.

## Bundles

QHexRT runs prebuilt QNN context bundles (`runanywhere/*_HNPU` on Hugging Face),
not GGUF. Two compatibility axes, both load-time and both silent until they
aren't:

- **Arch pinning.** `dsp_arch` + `soc_model` are baked into the context binary. A
  `v79` bundle does not *load* on a `v81` device.
- **QAIRT floor.** The deployed runtime must be **>=** the QAIRT that compiled the
  bundle. Measured: a v81 bundle compiled on 2.47 fails `contextCreateFromBinary`
  with `err=0x1388` on 2.41 and loads on 2.48. The actionable message
  (`Using newer context binary on old SDK`) appears only in the backend's stderr.

## Model download

`initialize()` registers the libcurl HTTP transport only when commons was built
with `-DRAC_DESKTOP_ADAPTER=ON`. Without it, register an already-downloaded
bundle directory instead of resolving one from Hugging Face.
