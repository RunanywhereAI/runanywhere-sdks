# @runanywhere/web-llamacpp

The independent llama.cpp backend for the RunAnywhere Web SDK. It provides
LLM, GGUF text embeddings, VLM, LoRA, tool calling, and structured-output
capabilities through the public `RunAnywhere` facade.

`@runanywhere/web-onnx` remains an alternate embeddings provider and owns the
native ONNX RAG WASM/session path. Framework-aware routing lets ONNX and llama.cpp
embedding models coexist without registration-order coupling.

This browser package integrates with core only through
`@runanywhere/web/backend`; it does not depend on the ONNX backend or core's
private `/internal` entrypoint.

## Install and initialize

```bash
npm install @runanywhere/web @runanywhere/web-llamacpp
```

```ts
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
await LlamaCPP.register({ acceleration: 'auto' });

// Register/download/load a compatible GGUF through RunAnywhere first.
const stream = await RunAnywhere.generateStream({
  prompt: 'Write a short haiku about local AI.',
  maxTokens: 96,
});
for await (const token of stream.stream) renderToken(token);
```

## Capabilities

- LLM generation and cancellation.
- GGUF text embeddings through the shared embeddings facade.
- VLM image/video-frame inference through llama.cpp mtmd.
- LoRA adapter registration and application.
- Tool calling and JSON-schema structured output.
- CPU fallback and WebGPU/Asyncify acceleration selected at runtime.

## Artifacts

The package ships two self-contained variants:

```text
wasm/racommons-llamacpp.{js,wasm}
wasm/racommons-llamacpp-webgpu.{js,wasm}
```

No symbols are shared with core or ONNX WASM. Configure your bundler to retain
package-relative `import.meta.url` asset resolution. Vite users should exclude
`@runanywhere/web-llamacpp` from dependency pre-bundling and serve the app with
COOP/COEP headers.

Build and verify from `sdk/runanywhere-web`:

```bash
npm run build:wasm -- --llamacpp
npm run build:wasm -- --webgpu
npm run build -w packages/llamacpp
npm run verify:package -w packages/llamacpp
```

This is a browser-bundler package, not a server-side Node.js inference runtime.

## License

Copyright (c) 2025 RunAnywhere, Inc. See the included `LICENSE` file for the
custom RunAnywhere License.
