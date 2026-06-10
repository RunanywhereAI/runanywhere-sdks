/**
 * Backends/onnxStatus.ts
 *
 * Public, build-flag-free backend availability surface for the ONNX/Sherpa
 * speech stack (STT, TTS, VAD). Example apps must not embed SDK-internal
 * CMake flag names (`RAC_WASM_ONNX=ON`) in their UI strings — instead they
 * consume the typed status returned here and surface SDK-owned wording.
 *
 * Each per-modality availability check mirrors what
 * `RunAnywhere.{stt,tts,vad}.supportsProto*` does but without raising; the
 * aggregated `reason` text is owned here so a single SDK string update
 * propagates to every consumer view.
 */
import {
  missingExports,
  modalityModuleFor,
  type ModalityProtoModule,
} from '../../../Adapters/ProtoAdapterTypes';

export interface BackendModalitySupport {
  /** Whether the backend WASM exports for this modality are present. */
  readonly supported: boolean;
  /** Names of exports that are still missing, in proto C ABI form. */
  readonly missingExports: readonly string[];
}

export interface OnnxBackendStatus {
  /** True once at least one ONNX-backed modality (STT/TTS/VAD) is callable. */
  readonly registered: boolean;
  readonly stt: BackendModalitySupport;
  readonly tts: BackendModalitySupport;
  readonly vad: BackendModalitySupport;
  /**
   * Human-readable, build-flag-free description of why the ONNX backend
   * is or isn't available. Example apps render this verbatim instead of
   * inventing their own copy.
   */
  readonly reason: string;
}

const ONNX_BACKEND_PACKAGE = '@runanywhere/web-onnx';

const STT_REQUIRED: ReadonlyArray<keyof ModalityProtoModule> = [
  '_rac_stt_component_transcribe_proto',
  '_rac_stt_component_transcribe_stream_proto',
];

const TTS_REQUIRED: ReadonlyArray<keyof ModalityProtoModule> = [
  '_rac_tts_component_list_voices_proto',
  '_rac_tts_component_synthesize_proto',
  '_rac_tts_component_synthesize_stream_proto',
];

const VAD_REQUIRED: ReadonlyArray<keyof ModalityProtoModule> = [
  '_rac_vad_component_configure_proto',
  '_rac_vad_component_process_proto',
  '_rac_vad_component_get_statistics_proto',
  '_rac_vad_component_set_activity_proto_callback',
];

function inspect(
  module: ModalityProtoModule | null,
  required: ReadonlyArray<keyof ModalityProtoModule>,
): BackendModalitySupport {
  if (!module) {
    // No backend has registered for this modality — report the required
    // proto exports so the consumer can show which symbols are missing.
    return { supported: false, missingExports: required.map(String) };
  }
  const missing = missingExports(module, [...required]);
  return { supported: missing.length === 0, missingExports: missing };
}

function reasonFor(
  stt: BackendModalitySupport,
  tts: BackendModalitySupport,
  vad: BackendModalitySupport,
): string {
  const supported: string[] = [];
  if (stt.supported) supported.push('STT');
  if (tts.supported) supported.push('TTS');
  if (vad.supported) supported.push('VAD');
  if (supported.length > 0) {
    return `ONNX backend registered (${supported.join(', ')}).`;
  }

  const anyModuleRegistered = modalityModuleFor('stt') != null
    || modalityModuleFor('tts') != null
    || modalityModuleFor('vad') != null;

  if (!anyModuleRegistered) {
    return `ONNX/Sherpa backend not registered. Install and register \`${ONNX_BACKEND_PACKAGE}\` to enable STT/TTS/VAD.`;
  }
  return `ONNX backend WASM is loaded but the STT/TTS/VAD proto exports are unavailable. Load \`${ONNX_BACKEND_PACKAGE}\` against a Web WASM build that includes the ONNX/Sherpa speech stack.`;
}

/**
 * Inspect whether the ONNX/Sherpa speech backend is wired up. Returns a
 * snapshot — call again after registration to observe progress. The
 * `reason` is the canonical wording for "ONNX missing" UI strings and is
 * the only text consumers should render; the SDK reserves the right to
 * rewrite it as the WASM packaging evolves.
 */
export function onnxStatus(): OnnxBackendStatus {
  const stt = inspect(modalityModuleFor('stt'), STT_REQUIRED);
  const tts = inspect(modalityModuleFor('tts'), TTS_REQUIRED);
  const vad = inspect(modalityModuleFor('vad'), VAD_REQUIRED);
  return {
    registered: stt.supported || tts.supported || vad.supported,
    stt,
    tts,
    vad,
    reason: reasonFor(stt, tts, vad),
  };
}

export const Backends = {
  onnxStatus,
};

export type BackendsNamespace = typeof Backends;
