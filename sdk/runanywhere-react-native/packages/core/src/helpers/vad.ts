/**
 * helpers/vad — ergonomic helpers for proto-encoded VAD types.
 */

import { VADConfiguration, VADOptions } from '@runanywhere/proto-ts/vad_options';

export {
  VADConfiguration,
  VADOptions,
  type VADResult,
  type SpeechActivityEvent,
  SpeechActivityKind,
} from '@runanywhere/proto-ts/vad_options';

/** Default `VADConfiguration` matching the Swift / Kotlin defaults. */
export function defaultVADConfig(): VADConfiguration {
  return VADConfiguration.create({
    modelId: '',
    sampleRate: 16000,
    frameLengthMs: 100,
    threshold: 0.015,
    enableAutoCalibration: false,
  });
}

/** Default `VADOptions`. */
export function defaultVADOptions(): VADOptions {
  return VADOptions.create({
    threshold: 0,
    minSpeechDurationMs: 100,
    minSilenceDurationMs: 300,
  });
}
