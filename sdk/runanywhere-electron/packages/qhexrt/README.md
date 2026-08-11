# `@runanywhere/electron-qhexrt`

QHexRT backend package for the Electron SDK — text generation on the **Qualcomm
Hexagon NPU**.

Supported host today: **Windows on ARM64** (Snapdragon X / X2 Elite, Hexagon
`v81`). Off-platform builds still install and register; the engine reports
`BACKEND_UNAVAILABLE` and the router can never select it, so a cross-platform app
can depend on this package unconditionally.

## Usage (main process only)

```ts
import { QHexRT } from '@runanywhere/electron-qhexrt';
QHexRT.register(); // before RunAnywhereMain.connect()
```

Registration records `prebuilds/<platform>-<arch>/runanywhere_qhexrt.dll` in the
main-process queue; `RunAnywhereMain` copies it into `RUNANYWHERE_PLUGIN_PATHS`
at utility-host fork. There is no renderer RPC that can load a plugin.

## What ships in `prebuilds/win32-arm64/`

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
