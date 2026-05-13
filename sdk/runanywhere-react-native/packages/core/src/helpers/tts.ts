/**
 * helpers/tts
 *
 * Swift-parity conveniences for generated TTS proto types.
 */

import {
  TTSSpeakResult,
  type TTSOutput,
  type TTSSpeakResult as TTSSpeakResultType,
} from '@runanywhere/proto-ts/tts_options';

export {
  TTSConfiguration,
  TTSOptions,
  TTSVoiceGender,
  type TTSOutput,
  type TTSSpeakResult,
  type TTSVoiceInfo,
  type TTSPhonemeTimestamp,
  type TTSSynthesisMetadata,
  type TTSSynthesisRequest,
  type TTSServiceState,
  type TTSStreamEvent,
} from '@runanywhere/proto-ts/tts_options';

export function ttsOutputDuration(output: TTSOutput): number {
  return output.durationMs / 1000;
}

export function ttsSpeakResultFromOutput(output: TTSOutput): TTSSpeakResultType {
  return TTSSpeakResult.create({
    audioFormat: output.audioFormat,
    sampleRate: output.sampleRate,
    durationMs: output.durationMs,
    audioSizeBytes:
      output.audioSizeBytes > 0 ? output.audioSizeBytes : output.audioData.byteLength,
    metadata: output.metadata,
    timestampMs: output.timestampMs,
    errorMessage: output.errorMessage,
    errorCode: output.errorCode,
  });
}

export function ttsSpeakResultDuration(result: TTSSpeakResultType): number {
  return result.durationMs / 1000;
}
