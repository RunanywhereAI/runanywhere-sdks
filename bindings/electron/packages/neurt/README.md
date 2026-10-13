# `@runanywhere/electron-neurt`

NeuRT backend package for the Electron SDK — text generation on the **Apple
Neural Engine**, via prebuilt Core ML graphs.

Supported host today: **macOS on Apple Silicon** (`darwin-arm64`). Off-platform
builds still install and register; the engine reports `BACKEND_UNAVAILABLE` and
the router can never select it, so a cross-platform app can depend on this
package unconditionally.

## Usage (main process only)

```ts
import { NeuRT } from '@runanywhere/electron-neurt';
NeuRT.register(); // before RunAnywhereMain.connect()
```

Registration records `prebuilds/<platform>-<arch>/runanywhere_neurt.dylib` in
the main-process queue; `RunAnywhereMain` copies it into
`RUNANYWHERE_PLUGIN_PATHS` at utility-host fork. There is no renderer RPC that
can load a plugin.

## What ships in `prebuilds/darwin-arm64/`

Just the plugin and the shared commons sidecar — Core ML is a system framework,
not a vendored runtime:

| file | from |
|---|---|
| `runanywhere_neurt.dylib` | this repo (`engines/neurt`) |
| `librac_commons.dylib` | this repo — the thin addon's shared commons |

## Catalog rows

NeuRT-served models declare `framework: 'COREML'` (not `'NEURT'`) — NeuRT is the
engine's identity, Core ML is the framework it executes, matching every other
SDK's catalog (iOS registers the same models with `framework: .coreml`). Model
bundles are Hugging Face folder refs to a `.mlpackage`/`.mlmodelc` tree, resolved
and downloaded through the SDK's normal model store, never bundled into this
package.

## Model download

`initialize()` registers the libcurl HTTP transport only when commons was built
with `-DRAC_DESKTOP_ADAPTER=ON`. Without it, register an already-downloaded
bundle directory instead of resolving one from Hugging Face.
