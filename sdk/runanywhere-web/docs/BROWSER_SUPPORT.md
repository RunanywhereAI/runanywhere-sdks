# Browser support

The Web SDK needs a modern browser with WebAssembly, ES modules, OPFS, and Web
Audio/MediaDevices for the corresponding features. Model availability also
depends on device memory and storage; support for a browser does not guarantee
that every model fits on that device.

## Chrome and Edge

Chrome and Chromium-based Edge are the primary production targets. With
cross-origin isolation enabled, they support `SharedArrayBuffer`, pthread WASM,
and the CPU llama.cpp and ONNX/Sherpa artifacts.

**Acceleration split**

| Backend | Artifact(s) | Acceleration today |
|---------|-------------|--------------------|
| llama.cpp (LLM/VLM) | `racommons-llamacpp` + `racommons-llamacpp-webgpu` | WebGPU-first in BackendWorker when `shader-f16` is available |
| ONNX/Sherpa (STT/TTS/VAD) | `racommons-onnx-sherpa` + `-webgpu` twin | ORT WebGPU when probe succeeds, else CPU (+ threads). See [ONNX_WEBGPU.md](./ONNX_WEBGPU.md). |

`RunAnywhere.runtime.active` / `setAcceleration` are **LLM-scoped**. Speech
diagnostics live on `RunAnywhere.runtime.speech` and the
`sdk.speechAcceleration` event. Do not treat a WebGPU LLM badge as speech GPU.

For the full modality matrix (LLM, VLM, STT, TTS, VAD, embeddings, RAG, voice
agent, rerank, segmentation, diarization, diffusion), use
`RunAnywhere.runtime.modalities`. See [WASM_AND_WEBGPU.md](./WASM_AND_WEBGPU.md)
for why WASM and WebGPU are complementary, not alternatives.

## Firefox

Firefox supports the CPU WebAssembly path and pthreads when the application is
cross-origin isolated. Treat WebGPU as capability-dependent rather than a
baseline requirement. Test the specific Firefox version and deployment headers
before claiming accelerated support.

## Safari and WebKit

Safari requires cross-origin isolation for threaded WASM. It does not support
`Cross-Origin-Embedder-Policy: credentialless`, so deploy
`Cross-Origin-Embedder-Policy: require-corp` and ensure every cross-origin
resource supplies an appropriate CORS or CORP response. The example includes
`coi-serviceworker.js` as a development fallback; production should send the
headers from the origin whenever possible.

## ONNX and actionable isolation failures

The ONNX/Sherpa artifact uses pthreads. Before registering it, applications
must verify `crossOriginIsolated` and surface an actionable error when it is
false, for example: “Speech features require cross-origin isolation. Configure
COOP: same-origin and COEP: credentialless (or require-corp on Safari), then
reload.” Do not leave initialization pending or present speech as ready.

Register speech with a hard worker requirement in production apps:

```ts
await ONNX.register({
  acceleration: 'auto', // WebGPU if browser + ORT EP probe OK, else CPU
  threads: 2,
  requireBackendWorker: true,
});
```

`ONNX.accelerationMode` / `RunAnywhere.runtime.speech.acceleration` are `'webgpu'`
only when the ORT WebGPU EP append probe succeeds — never merely because a
`-webgpu` WASM twin was present.

See [DEPLOYMENT.md](./DEPLOYMENT.md) for server headers, static assets, CSP,
and memory/download guidance. Speech vendor/release: [ONNX_WEBGPU.md](./ONNX_WEBGPU.md).
