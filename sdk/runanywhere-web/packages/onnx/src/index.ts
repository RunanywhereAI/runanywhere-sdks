/**
 * @runanywhere/web-onnx
 *
 * V2 ONNX backend for the RunAnywhere Web SDK. Ships the standalone
 * Sherpa-ONNX WASM module (proven `main`-branch path) wired into the
 * V2 `SpeechProvider` interface so `RunAnywhere.transcribe`,
 * `RunAnywhere.synthesize`, and `RunAnywhere.detectVoiceActivity` work
 * end-to-end. Also attempts to install the proto-byte ONNX/Sherpa
 * plugins on the unified RACommons WASM module for RAG / embeddings.
 *
 * Calling `ONNX.register()`:
 *   1. Installs the standalone Sherpa speech provider (lazy WASM load).
 *   2. Best-effort proto-byte plugin registration on the unified
 *      RACommons module — failures are logged and ignored, speech
 *      remains available via the standalone provider.
 *
 * # Public surface
 *
 * The package root intentionally exposes ONLY the registration facade
 * (`ONNX`, `autoRegister`) and its option types. The standalone Sherpa
 * loader, MEMFS-oriented wrapper classes (`StandaloneSherpaVad`,
 * `StandaloneSherpaTts`, `StandaloneSherpaStt`), provider installer,
 * and upstream-helper accessors are deliberately NOT exported here:
 * they exist as a temporary workaround for the proto-byte plugin path,
 * and exposing them publicly would lock the workaround into the
 * package's SemVer contract. Public speech usage stays on
 * `RunAnywhere.{transcribe,synthesize,detectVoiceActivity}`.
 *
 * Internal callers that genuinely need those modules import them
 * relatively from `./Foundation/*` inside this package; nothing
 * outside `@runanywhere/web-onnx` is expected to depend on them.
 *
 * @packageDocumentation
 */

export { ONNX, autoRegister } from './ONNX';
export type { ONNXRegisterOptions } from './ONNX';
