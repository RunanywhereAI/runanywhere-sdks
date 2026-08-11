/**
 * `@runanywhere/electron-qhexrt` — QHexRT (Qualcomm Hexagon NPU) backend for the
 * Electron SDK.
 *
 * Peer-depends on `@runanywhere/electron`. Registers the NPU engine; it does not
 * replace a CPU backend, so an app that also wants GGUF inference declares
 * `@runanywhere/electron-llamacpp` alongside it.
 */

export { QHexRT } from './QHexRT';
export type { QHexRTRegisterOptions } from './QHexRT';
