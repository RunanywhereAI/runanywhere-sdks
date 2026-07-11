import type { EmscriptenRunanywhereModule } from './EmscriptenModule.js';

export interface SpeechBackendModule extends EmscriptenRunanywhereModule {
  _rac_backend_onnx_register?: () => number;
  _rac_backend_onnx_unregister?: () => number;
  _rac_backend_sherpa_register?: () => number;
  _rac_backend_sherpa_unregister?: () => number;
}

export const REQUIRED_SPEECH_BACKEND_EXPORTS = [
  '_rac_backend_onnx_register',
  '_rac_backend_sherpa_register',
] as const;

export function missingSpeechBackendExports(
  module: EmscriptenRunanywhereModule | null | undefined,
): string[] {
  if (!module) return [...REQUIRED_SPEECH_BACKEND_EXPORTS];
  const record = module as unknown as Record<string, unknown>;
  return REQUIRED_SPEECH_BACKEND_EXPORTS.filter((name) => typeof record[name] !== 'function');
}

export function hasSpeechBackendExports(
  module: EmscriptenRunanywhereModule | null | undefined,
): boolean {
  return missingSpeechBackendExports(module).length === 0;
}

export function speechBackendRequirementMessage(missing: string[]): string {
  const missingList = missing.length > 0 ? missing.join(', ') : 'none';
  return (
    `Loaded RACommons WASM is missing speech backend exports: ${missingList}. ` +
    'Build or vendor ONNX Runtime WASM and Sherpa-ONNX WASM static archives, ' +
    'then rebuild the Web WASM with ONNX/Sherpa enabled before using STT, TTS, or model-backed VAD.'
  );
}
