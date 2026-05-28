/**
 * RunAnywhere+AudioConvert.ts
 *
 * Public PCM conversion helpers for example apps and host integrations.
 * Matches iOS: RAAudioConvert.swift
 *
 * Mirrors the commons `rac_audio_pcm16_to_float32` inline routine so callers
 * feeding raw Int16 microphone PCM into `RunAnywhere.detectVoiceActivity(...)`
 * / `transcribe(...)` do not need to reimplement the divide-by-32768.0
 * normalisation, matching the canonical commons audio normalisation contract.
 */

/**
 * Convert a buffer of Int16 PCM samples to Float32 samples in the range
 * `[-1.0, 1.0]`. Divides each sample by `32768.0`.
 *
 * Matches iOS: static func pcm16ToFloat32(_ int16Data: Data) -> Data
 *
 * @param int16Bytes Raw Int16 PCM samples (little-endian, as captured by
 *   `getUserMedia`). The bit pattern is preserved verbatim.
 * @returns Float32 samples. The layout matches what
 *   `RunAnywhere.detectVoiceActivity(...)` and the STT/VAD streaming APIs
 *   accept as input.
 */
export function pcm16ToFloat32(int16Bytes: ArrayBuffer): Float32Array {
  const int16Count = Math.floor(int16Bytes.byteLength / 2);
  if (int16Count === 0) return new Float32Array(0);
  const input = new DataView(int16Bytes);
  const out = new Float32Array(int16Count);
  for (let i = 0; i < int16Count; i++) {
    out[i] = input.getInt16(i * 2, true) / 32768.0;
  }
  return out;
}

/**
 * Convenience alias returning the normalised samples directly. Matches iOS:
 * static func pcm16ToFloat32Samples(_ int16Data: Data) -> [Float]. On RN both
 * overloads return a `Float32Array`; this name exists for cross-SDK call-site
 * parity with Swift.
 */
export function pcm16ToFloat32Samples(int16Bytes: ArrayBuffer): Float32Array {
  return pcm16ToFloat32(int16Bytes);
}

/**
 * Namespace bundle so the helpers can be attached to the public `RunAnywhere`
 * object (`RunAnywhere.pcm16ToFloat32(...)`) the same way other extensions are.
 */
export const AudioConvert = {
  pcm16ToFloat32,
  pcm16ToFloat32Samples,
};
