# @runanywhere/qhexrt

On-device NPU acceleration backend for the RunAnywhere React Native SDK. Runs LLM, VLM, STT and TTS entirely on-device on Qualcomm Snapdragon Hexagon NPUs (V75 / V79 / V81). Android `arm64-v8a` only.

## Install
```sh
npm install @runanywhere/qhexrt
```

## Use
Register the backend, then use the standard RunAnywhere APIs — the SDK automatically routes supported models to the NPU.

```ts
import { QHexRT } from '@runanywhere/qhexrt'

QHexRT.register()
const npu = QHexRT.probeNpu() // pre-flight capability probe, safe on any device
```

## Requirements
- Android `arm64-v8a`
- A Qualcomm Snapdragon device with a Hexagon V75 / V79 / V81 NPU

## License
Proprietary. See `LICENSE`.
