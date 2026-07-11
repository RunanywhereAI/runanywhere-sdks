# @runanywhere/qhexrt

Android arm64 QHexRT backend for Qualcomm Hexagon V75, V79, and V81 NPUs.

```ts
import { QHexRT, HexagonArch } from '@runanywhere/qhexrt';
import {
  InferenceFramework,
  RegisterModelFromUrlRequest,
} from '@runanywhere/proto-ts/model_types';

const capability = await QHexRT.probeNpu();
if (capability.qhexrtSupported) await QHexRT.register();

const model = await QHexRT.registerModelForDevice(
  RegisterModelFromUrlRequest.fromPartial({
    id: 'my-hnpu-model',
    name: 'My HNPU Model',
    url: 'https://huggingface.co/your-org/your-model_HNPU/model.json',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
  }),
  [HexagonArch.HEXAGON_ARCH_V79, HexagonArch.HEXAGON_ARCH_V81]
);
```

The app remains the source of URLs and presentation metadata. QHexRT owns
architecture probing and model/device selection, then composes the shared C++
registry, Hugging Face resolver, download, extraction, validation, and
local-path workflow. `null` is the normal result when a definition does not
match the current device.

QHexRT host and stub libraries are staged under
`android/src/main/jniLibs/arm64-v8a`. FastRPC DSP `Skel.so` payloads are staged
under `android/src/main/assets/runanywhere/qhexrt/skels/arm64-v8a`, then the
Android package extracts them to a versioned app-private directory and passes
that directory to the native QHexRT engine before registration.
