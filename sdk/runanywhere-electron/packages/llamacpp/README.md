# `@runanywhere/electron-llamacpp`

LlamaCPP backend package for the Electron SDK (LLM / VLM / GGUF embeddings).

## Usage (main process only)

```ts
import { LlamaCPP } from '@runanywhere/electron-llamacpp';
import { RunAnywhereMain } from '@runanywhere/electron/main';

LlamaCPP.register(); // before forking the utility host
const main = new RunAnywhereMain();
// main.connect(webContents) → env RUNANYWHERE_PLUGIN_PATHS
```

## Dual path

| Mode | Native shape | What `register()` does |
|---|---|---|
| **Fat addon (today)** | Backends linked into `runanywhere_native.node` | Records the canonical plugin path + sets `RUNANYWHERE_PLUGIN_PATHS`. Host does not `dlopen` yet. |
| **Thin addon (Track A)** | `runanywhere_native.node` + `librac_commons` + `prebuilds/*/librunanywhere_llamacpp.*` | Same API; host loads via `rac_registry_load_plugin`. |

Plugin artifacts are staged under `prebuilds/<platform>-<arch>/` after Track A.
Until then this package ships TypeScript only.
