/**
 * `@runanywhere/electron-neurt` — NeuRT (Apple Neural Engine via Core ML) backend
 * for the Electron SDK.
 *
 * Peer-depends on `@runanywhere/electron`. Registers the ANE engine; it does not
 * replace a CPU backend, so an app that also wants GGUF inference declares
 * `@runanywhere/electron-llamacpp` alongside it.
 */

export { NeuRT } from './NeuRT';
export type { NeuRTRegisterOptions } from './NeuRT';
