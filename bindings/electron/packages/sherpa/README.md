# `@runanywhere/electron-sherpa`

Sherpa-ONNX speech backend package for the Electron SDK (STT / TTS / VAD).

## Usage (main process only)

```ts
import { Sherpa } from '@runanywhere/electron-sherpa';
Sherpa.register(); // before RunAnywhereMain.connect()
```

## Dual path

Same as `@runanywhere/electron-llamacpp`: fat addon today (paths recorded only);
thin addon after Track A loads `prebuilds/*/librunanywhere_sherpa.*` via
`rac_registry_load_plugin`.
