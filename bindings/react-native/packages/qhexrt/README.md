# @runanywhere/qhexrt

**Qualcomm Hexagon NPU backend for the RunAnywhere React Native SDK** — on-device LLM, VLM, STT, and TTS on Snapdragon V75/V79/V81 NPUs. Android `arm64-v8a` only.

---

## Installation

```bash
npm install @runanywhere/core@0.20.27 @runanywhere/qhexrt@0.20.19
```

See the [React Native SDK README](../../README.md) for Android setup.

---

## Usage

```typescript
import { RunAnywhere } from '@runanywhere/core';
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import { QHexRT } from '@runanywhere/qhexrt';

await RunAnywhere.initialize();

const npu = await QHexRT.probeNpu(); // safe on any device
if (!npu.supported) {
  console.warn(`Hexagon ${npu.socModel} is outside V75/V79/V81`);
} else if (!(await QHexRT.register())) {
  console.warn('QHexRT backend registration failed');
} else {
  await RunAnywhere.models.register({
    id: 'my-qhexrt-model',
    name: 'My QHexRT Model',
    url: 'https://huggingface.co/organization/dedicated-qhexrt-model/model.json',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
  });
  // Download, load, and infer via @runanywhere/core.
}
```

See the [React Native SDK README](../../README.md) for full examples.

The URL above is a logical bundle reference: Commons selects the device's architecture folder and registers the manifest with its companion files. A direct `/resolve/main/model.json` URL registers only that file. Explicitly pinned bundle references must match the device architecture.

---

## Explicit bundle registration

When registering a bundle URL through the core model-registration API with the QHexRT backend registered, Commons selects the device's architecture folder for logical references such as `https://huggingface.co/organization/model-repository/model.json` and includes the manifest's companion files.

A known architecture pin in the first repository folder, such as `/v79` or `/v79/model.json`, is checked before network resolution or registry changes. A mismatched pin returns `RAC_ERROR_INVALID_ARGUMENT` with a message naming the bundle and device architectures; a matching pin is kept unchanged. Probe failures and unsupported devices return the same errors as logical references.

Direct `/resolve/` or `/blob/` URLs register a single file and do not receive this bundle-folder check.

---

## Requirements

- Android `arm64-v8a`
- Qualcomm Snapdragon device with Hexagon V75, V79, or V81 NPU

---

## Support

- [React Native SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

Proprietary. See [LICENSE](LICENSE).
