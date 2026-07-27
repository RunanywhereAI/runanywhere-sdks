# @runanywhere/qhexrt

**Qualcomm Hexagon NPU backend for the RunAnywhere React Native SDK** — on-device LLM, VLM, STT, and TTS on Snapdragon V75/V79/V81 NPUs. Android `arm64-v8a` only.

---

## Installation

```bash
npm install @runanywhere/core@0.20.11 @runanywhere/qhexrt@0.20.11
```

See the [React Native SDK README](../../README.md) for Android setup.

---

## Usage

```typescript
import { QHexRT } from '@runanywhere/qhexrt';

const npu = await QHexRT.probeNpu(); // safe on any device
if (npu.qhexrtSupported) {
  await QHexRT.register();
}
// Register, download, load, and infer via @runanywhere/core
```

See the [React Native SDK README](../../README.md) for full examples.

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
