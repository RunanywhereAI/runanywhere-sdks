/** Typed ONNX/Sherpa availability owned by the ONNX backend package. */
import {
  missingExports,
  modalityModuleFor,
  type ModalityProtoModule,
} from '@runanywhere/web/backend';

export interface BackendModalitySupport {
  readonly supported: boolean;
  readonly missingExports: readonly string[];
}

export interface ONNXBackendStatus {
  readonly registered: boolean;
  readonly stt: BackendModalitySupport;
  readonly tts: BackendModalitySupport;
  readonly vad: BackendModalitySupport;
  readonly reason: string;
}

const STT_REQUIRED: ReadonlyArray<keyof ModalityProtoModule> = [
  '_rac_stt_component_transcribe_proto',
  '_rac_stt_component_transcribe_stream_proto',
  '_rac_stt_transcribe_lifecycle_proto',
  '_rac_stt_transcribe_stream_lifecycle_proto',
];

const TTS_REQUIRED: ReadonlyArray<keyof ModalityProtoModule> = [
  '_rac_tts_component_list_voices_proto',
  '_rac_tts_component_synthesize_proto',
  '_rac_tts_component_synthesize_stream_proto',
  '_rac_tts_synthesize_lifecycle_proto',
  '_rac_tts_synthesize_stream_lifecycle_proto',
  '_rac_tts_stop_lifecycle_proto',
  '_rac_tts_list_voices_lifecycle_proto',
];

const VAD_REQUIRED: ReadonlyArray<keyof ModalityProtoModule> = [
  '_rac_vad_component_configure_proto',
  '_rac_vad_component_process_proto',
  '_rac_vad_component_get_statistics_proto',
  '_rac_vad_component_set_activity_proto_callback',
  '_rac_vad_process_lifecycle_proto',
  '_rac_vad_configure_lifecycle_proto',
  '_rac_vad_start_lifecycle_proto',
  '_rac_vad_stop_lifecycle_proto',
  '_rac_vad_reset_lifecycle_proto',
];

function inspect(
  module: ModalityProtoModule | null,
  required: ReadonlyArray<keyof ModalityProtoModule>,
): BackendModalitySupport {
  if (!module) {
    return { supported: false, missingExports: required.map(String) };
  }
  const missing = missingExports(module, [...required]);
  return { supported: missing.length === 0, missingExports: missing };
}

function statusReason(
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
    return 'ONNX/Sherpa backend not registered. Call ONNX.register() to enable STT/TTS/VAD.';
  }
  return 'ONNX backend WASM is loaded, but its STT/TTS/VAD proto exports are unavailable.';
}

/** Return a fresh snapshot of this package's registered speech capabilities. */
export function onnxStatus(): ONNXBackendStatus {
  const stt = inspect(modalityModuleFor('stt'), STT_REQUIRED);
  const tts = inspect(modalityModuleFor('tts'), TTS_REQUIRED);
  const vad = inspect(modalityModuleFor('vad'), VAD_REQUIRED);
  return {
    registered: stt.supported || tts.supported || vad.supported,
    stt,
    tts,
    vad,
    reason: statusReason(stt, tts, vad),
  };
}
