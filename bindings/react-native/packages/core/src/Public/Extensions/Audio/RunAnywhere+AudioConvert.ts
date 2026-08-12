/**
 * RunAnywhere+AudioConvert.ts
 *
 * Public PCM conversion helpers for example apps and host integrations.
 * Thin wrappers over commons `rac_audio_*` via the Nitro RunAnywhereCore bridge.
 */

import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  isNativeModuleAvailable,
  requireNativeModule,
} from '../../../native';

function requireAudioNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

/**
 * Convert a buffer of Int16 PCM samples to Float32 samples in the range
 * `[-1.0, 1.0]` via commons `rac_audio_pcm16_to_float32`.
 */
export function pcm16ToFloat32(int16Bytes: ArrayBuffer): Float32Array {
  const native = requireAudioNative();
  const floatBytes = native.audioPcm16ToFloat32(int16Bytes);
  return new Float32Array(floatBytes.slice(0));
}

/**
 * Convenience alias returning the normalised samples directly. Matches iOS:
 * static func pcm16ToFloat32Samples(_ int16Data: Data) -> [Float].
 */
export function pcm16ToFloat32Samples(int16Bytes: ArrayBuffer): Float32Array {
  return pcm16ToFloat32(int16Bytes);
}

/**
 * Wrap raw 16-bit mono PCM samples in a canonical WAV via
 * `rac_audio_int16_to_wav`.
 */
export function pcm16ToWav(
  int16Bytes: ArrayBuffer,
  sampleRate: number
): ArrayBuffer {
  return requireAudioNative().audioInt16ToWav(int16Bytes, sampleRate);
}

/**
 * Encode Float32 mono PCM as a WAV container via `rac_audio_float32_to_wav`
 * (canonical RAC_AUDIO_PCM16_SCALE quantization — not asymmetric 0x8000/0x7fff).
 */
export function float32ToWav(
  float32Bytes: ArrayBuffer,
  sampleRate: number
): ArrayBuffer {
  return requireAudioNative().audioFloat32ToWav(float32Bytes, sampleRate);
}

/**
 * Namespace bundle so the helpers can be attached to the public `RunAnywhere`
 * object (`RunAnywhere.pcm16ToFloat32(...)`) the same way other extensions are.
 */
export const AudioConvert = {
  pcm16ToFloat32,
  pcm16ToFloat32Samples,
  pcm16ToWav,
  float32ToWav,
};
