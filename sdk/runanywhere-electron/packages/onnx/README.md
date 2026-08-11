# `@runanywhere/electron-onnx`

ONNX backend package for the Electron SDK (embeddings / segmentation).

Speech (STT / TTS / VAD) is **`@runanywhere/electron-sherpa`** — declare both
when the app needs them (unlike Web, where one `@runanywhere/web-onnx` package
registers both vtables).

## Usage (main process only)

```ts
import { ONNX } from '@runanywhere/electron-onnx';
ONNX.register(); // before RunAnywhereMain.connect()
```

## Dual path

Same as `@runanywhere/electron-llamacpp`: fat addon today (paths recorded only);
thin addon after Track A loads `prebuilds/*/librunanywhere_onnx.*` via
`rac_registry_load_plugin`.
