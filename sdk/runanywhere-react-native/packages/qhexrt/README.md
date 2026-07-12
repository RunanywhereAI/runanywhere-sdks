# @runanywhere/qhexrt

Android arm64 QHexRT backend for Qualcomm Hexagon V75, V79, and V81 NPUs.

```ts
import { QHexRT } from '@runanywhere/qhexrt';
import {
  InferenceFramework,
  RegisterModelFromUrlRequest,
} from '@runanywhere/proto-ts/model_types';

const capability = await QHexRT.probeNpu();
if (capability.qhexrtSupported) await QHexRT.register();

const model = await QHexRT.registerModelForDevice(
  RegisterModelFromUrlRequest.fromPartial({
    id: 'qwen3_5_0_8b',
    name: 'Qwen3.5 0.8B (HNPU)',
    url: 'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
  })
);
```

The app remains the source of URLs and presentation metadata. QHexRT owns
stable product IDs, architecture/auth policy, and model/device selection, then composes the shared C++
registry, Hugging Face resolver, download, extraction, validation, and
local-path workflow. `null` is the normal result when a definition does not
match the current device.

QHexRT host and stub libraries are staged under
`android/src/main/jniLibs/arm64-v8a`. FastRPC DSP `Skel.so` payloads are staged
under `android/src/main/assets/runanywhere/qhexrt/skels/arm64-v8a`, then the
Android package extracts them to a versioned app-private directory and passes
that directory to the native QHexRT engine before registration.
