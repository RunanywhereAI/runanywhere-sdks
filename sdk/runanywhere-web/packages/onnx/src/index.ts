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
 * @packageDocumentation
 */

export { ONNX, autoRegister } from './ONNX';
export type { ONNXRegisterOptions } from './ONNX';

export { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';
export type { SherpaONNXBridgeLoadOptions } from './Foundation/SherpaONNXBridge';

export {
  getStandaloneSherpaModule,
  isStandaloneSherpaLoaded,
  setStandaloneSherpaWasmLocation,
  tryStandaloneSherpaModule,
} from './Foundation/StandaloneSherpaModule';
export type {
  StandaloneSherpaLoadOptions,
  StandaloneSherpaModule,
} from './Foundation/StandaloneSherpaModule';

export { StandaloneSherpaVad } from './Foundation/StandaloneSherpaVad';
export type {
  StandaloneSherpaVadConfig,
} from './Foundation/StandaloneSherpaVad';

export { StandaloneSherpaTts } from './Foundation/StandaloneSherpaTts';
export type {
  StandaloneSherpaTtsConfig,
  StandaloneSherpaTtsResult,
  StandaloneSherpaTtsVitsConfig,
} from './Foundation/StandaloneSherpaTts';

export { StandaloneSherpaStt } from './Foundation/StandaloneSherpaStt';
export type {
  StandaloneSherpaSttConfig,
  StandaloneSherpaSttResult,
  StandaloneSherpaSttWhisperConfig,
} from './Foundation/StandaloneSherpaStt';

export {
  getInstalledStandaloneSherpaSpeechProvider,
  installStandaloneSherpaSpeechProvider,
  uninstallStandaloneSherpaSpeechProvider,
} from './Foundation/StandaloneSherpaSpeechProvider';

export { setSherpaUpstreamHelperBase } from './Foundation/SherpaUpstreamHelpers';
export type {
  SherpaASRHelpers,
  SherpaConfigHandle,
} from './Foundation/SherpaUpstreamHelpers';
