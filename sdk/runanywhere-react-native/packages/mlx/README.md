# @runanywhere/mlx

**Apple MLX backend registration for the RunAnywhere React Native SDK** — iOS-only; model lifecycle and inference live in `@runanywhere/core`.

---

## Installation

```bash
npm install @runanywhere/core@0.20.14 @runanywhere/mlx@0.20.11
cd ios && pod install && cd ..
```

Requires Xcode 26+ and a physical iOS 17.5+ device. `MLX.register()` returns `false` on simulator. See the [React Native SDK README](../../README.md).

---

## Usage

```typescript
import { RunAnywhere } from '@runanywhere/core';
import { MLX } from '@runanywhere/mlx';

const registered = await MLX.register();
if (registered) {
  await RunAnywhere.initialize();
  // Register, download, load, and infer via @runanywhere/core
}
```

See the [React Native SDK README](../../README.md) for full examples.

---

## Support

- [React Native SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
