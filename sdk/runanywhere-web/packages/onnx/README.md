# @runanywhere/web-onnx

The independent ONNX Runtime and Sherpa-ONNX backend for the RunAnywhere Web
SDK. It provides embeddings, Speech-to-Text, Text-to-Speech, and Voice Activity
Detection through the public `RunAnywhere` facade.

This browser package integrates with core only through
`@runanywhere/web/backend`; it does not depend on the llama.cpp backend or
core's private `/internal` entrypoint.

## Install and initialize

```bash
npm install @runanywhere/web @runanywhere/web-onnx
```

```ts
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';
import { ONNX } from '@runanywhere/web-onnx';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
await ONNX.register();

// Register/download/load compatible models through RunAnywhere first.
const transcript = await RunAnywhere.transcribe(audioSamples, {
  sampleRate: 16_000,
});
await RunAnywhere.speak('Speech synthesized locally in the browser.');
```

## Capabilities

- Whisper and other Sherpa-compatible STT models, including batch and streamed
  partial/final results.
- Piper/Sherpa-compatible TTS synthesis and browser playback.
- Silero/Sherpa-compatible VAD.
- ONNX embeddings used by the cross-backend Web RAG provider.

## Artifact

The package ships one self-contained pair:

```text
wasm/racommons-onnx-sherpa.{js,wasm}
```

It includes the required ONNX and Sherpa registration exports and owns its
native module lifetime. It does not reuse the core or llama.cpp WASM module.
Configure your bundler to retain package-relative `import.meta.url` resolution.
Vite users should exclude `@runanywhere/web-onnx` from dependency pre-bundling.

Build and verify from `sdk/runanywhere-web`:

```bash
npm run build:wasm -- --onnx
npm run build -w packages/onnx
npm run verify:package -w packages/onnx
```

This is a browser-bundler package, not a server-side Node.js inference runtime.

## License

Copyright (c) 2025 RunAnywhere, Inc. See the included `LICENSE` file for the
custom RunAnywhere License.
