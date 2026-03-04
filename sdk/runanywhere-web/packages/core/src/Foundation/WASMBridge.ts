/**
 * RunAnywhere Web SDK - WASM Bridge Types
 *
 * Core is now pure TypeScript. The actual WASM bridge implementations
 * live in each backend package:
 *   - LlamaCppBridge in @runanywhere/web-llamacpp
 *   - SherpaONNXBridge in @runanywhere/web-onnx
 *
 * This file only exports shared types used by the public API.
 */

/** The hardware acceleration mode used by a backend's WASM module. */
export type AccelerationMode = 'webgpu' | 'cpu';
