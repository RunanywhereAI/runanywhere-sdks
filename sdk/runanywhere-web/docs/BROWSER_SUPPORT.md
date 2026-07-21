# Browser support

The Web SDK needs a modern browser with WebAssembly, ES modules, OPFS, and Web
Audio/MediaDevices for the corresponding features. Model availability also
depends on device memory and storage; support for a browser does not guarantee
that every model fits on that device.

## Chrome and Edge

Chrome and Chromium-based Edge are the primary production targets. With
cross-origin isolation enabled, they support `SharedArrayBuffer`, pthread WASM,
and the CPU llama.cpp and ONNX/Sherpa artifacts. WebGPU is an optional
llama.cpp acceleration path; the SDK must retain the CPU fallback when WebGPU
is unavailable or the device is unsuitable.

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

See [DEPLOYMENT.md](./DEPLOYMENT.md) for server headers, static assets, CSP,
and memory/download guidance.
