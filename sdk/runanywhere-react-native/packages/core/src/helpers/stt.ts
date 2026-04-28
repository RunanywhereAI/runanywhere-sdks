/**
 * helpers/stt — ergonomic helpers for proto-encoded STT types.
 *
 * Re-exports the canonical proto types from
 * `@runanywhere/proto-ts/stt_options` and adds free-function defaults +
 * predicates so call sites don't have to call `STTConfiguration.create({...})`
 * with every field by hand.
 */

import {
  STTConfiguration,
  STTOptions,
  STTLanguage,
  type STTOutput,
} from '@runanywhere/proto-ts/stt_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';

export {
  STTConfiguration,
  STTOptions,
  STTLanguage,
  type STTOutput,
} from '@runanywhere/proto-ts/stt_options';

/** Returns a sensible default `STTConfiguration` for streaming transcription. */
export function defaultSTTConfig(modelId = ''): STTConfiguration {
  return STTConfiguration.create({
    modelId,
    language: STTLanguage.STT_LANGUAGE_AUTO,
    sampleRate: 16000,
    enableVad: true,
    audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
  });
}

/** Returns a sensible default `STTOptions` for runtime transcription overrides. */
export function defaultSTTOptions(): STTOptions {
  return STTOptions.create({
    language: STTLanguage.STT_LANGUAGE_AUTO,
    enablePunctuation: true,
    enableDiarization: false,
    maxSpeakers: 0,
    vocabularyList: [],
    enableWordTimestamps: false,
    beamSize: 0,
  });
}

/** True when the configuration carries enough info to run transcription. */
export function isSTTConfigValid(config: STTConfiguration): boolean {
  return config.modelId.length > 0 && config.sampleRate > 0;
}
