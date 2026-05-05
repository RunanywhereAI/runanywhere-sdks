/**
 * @runanywhere/web-onnx
 *
 * V2-canonical ONNX backend for the RunAnywhere Web SDK.
 *
 * This package is a thin shell — all STT/TTS/VAD inference flows through
 * the RACommons proto-byte C ABI (`rac_stt_component_*_proto`,
 * `rac_tts_component_*_proto`, `rac_vad_component_*_proto`) exposed by the
 * commons WASM module. Calling `ONNX.register()` simply registers the
 * sherpa-onnx vtable with the C++ plugin registry; the typed adapters in
 * `@runanywhere/web` (STTProtoAdapter, TTSProtoAdapter, VADProtoAdapter)
 * dispatch through it from then on.
 *
 * @packageDocumentation
 */

export { ONNX, autoRegister } from './ONNX';
export type { ONNXRegisterOptions } from './ONNX';
export { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';
export type { SherpaONNXBridgeLoadOptions } from './Foundation/SherpaONNXBridge';
