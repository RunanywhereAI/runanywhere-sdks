/**
 * RunAnywhere Web SDK - WASM Bridge Types
 *
 * Core owns the commons-only module loader. Capability-specific bridge
 * implementations live in their backend packages:
 *   - LlamaCppBridge in @runanywhere/web-llamacpp
 *   - SherpaONNXBridge in @runanywhere/web-onnx
 *
 * This file exports the backend-neutral acceleration type shared by the
 * registration contract and public runtime facade.
 */

/** The hardware acceleration mode used by a backend's WASM module. */
export type AccelerationMode = 'webgpu' | 'cpu';
