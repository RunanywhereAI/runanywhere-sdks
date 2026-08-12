/**
 * `@runanywhere/electron-onnx` — ONNX backend for the Electron SDK.
 *
 * Peer-depends on `@runanywhere/electron`. For STT/TTS/VAD also depend on
 * `@runanywhere/electron-sherpa` and call `Sherpa.register()`.
 */

export { ONNX } from './ONNX';
export type { ONNXRegisterOptions } from './ONNX';
