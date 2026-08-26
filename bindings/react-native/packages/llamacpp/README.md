# @runanywhere/llamacpp

**Llama.cpp backend registration for the RunAnywhere React Native SDK** — installs the native LLM/VLM provider; model lifecycle and inference live in `@runanywhere/core`.

---

## Installation

```bash
npm install @runanywhere/core@0.20.27 @runanywhere/llamacpp@0.20.27
cd ios && pod install && cd ..
```

See the [React Native SDK README](../../README.md) for platform setup.

---

## Usage

```typescript
import { RunAnywhere } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';

await RunAnywhere.initialize();
await LlamaCPP.register();

const result = await RunAnywhere.generate('Write one sentence about local AI.');
console.log(result.text);
```

Register, download, and load models through `@runanywhere/core`. See the [React Native SDK README](../../README.md).

---

## Support

- [React Native SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](LICENSE).
