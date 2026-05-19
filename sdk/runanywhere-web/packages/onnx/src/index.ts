/**
 * @runanywhere/web-onnx
 *
 * ONNX/Sherpa speech backend for the RunAnywhere Web SDK. Loads the
 * dedicated `racommons-onnx-sherpa.{js,wasm}` artifact and registers the
 * ONNX runtime + Sherpa speech vtables with the C++ plugin registry so
 * STT/TTS/VAD inference flows through `RunAnywhere.transcribe`,
 * `RunAnywhere.synthesize`, and `RunAnywhere.detectVoiceActivity`
 * end-to-end.
 *
 * Calling `ONNX.register()`:
 *   1. Loads the `racommons-onnx-sherpa.wasm` Emscripten module from
 *      `packages/onnx/wasm/`.
 *   2. Calls `_rac_backend_onnx_register()` and
 *      `_rac_backend_sherpa_register()` so STT/TTS/VAD operations route
 *      through the proto-byte adapters in `@runanywhere/web` core.
 *
 * # Public surface
 *
 * The package root intentionally exposes ONLY the registration facade
 * (`ONNX`, `autoRegister`) and its option types. The `SherpaONNXBridge`
 * singleton is an internal implementation detail.
 *
 * @packageDocumentation
 */

export { ONNX, autoRegister } from './ONNX';
export type { ONNXRegisterOptions } from './ONNX';
