/**
 * helpers/tts — ergonomic helpers for proto-encoded TTS types.
 */

import {
  TTSConfiguration,
  TTSOptions,
  TTSVoiceGender,
} from '@runanywhere/proto-ts/tts_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';

export {
  TTSConfiguration,
  TTSOptions,
  TTSVoiceGender,
  type TTSOutput,
  type TTSSpeakResult,
  type TTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';

/** Default `TTSConfiguration` for synthesis. */
export function defaultTTSConfig(modelId = ''): TTSConfiguration {
  return TTSConfiguration.create({
    modelId,
    voice: '',
    languageCode: '',
    speakingRate: 1.0,
    pitch: 1.0,
    volume: 1.0,
    audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
    sampleRate: 22050,
    enableNeuralVoice: false,
    enableSsml: false,
  });
}

/** Default `TTSOptions` for per-call overrides. */
export function defaultTTSOptions(): TTSOptions {
  return TTSOptions.create({
    voice: '',
    languageCode: '',
    speakingRate: 1.0,
    pitch: 1.0,
    volume: 1.0,
    enableSsml: false,
    audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
  });
}

/** True when the configuration is plausibly synthesizable. */
export function isTTSConfigValid(config: TTSConfiguration): boolean {
  return config.modelId.length > 0;
}
