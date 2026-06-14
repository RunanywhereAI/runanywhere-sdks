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
 * Wrap raw 16-bit mono PCM samples in a canonical 44-byte WAV (RIFF)
 * container: `RIFF` + `fmt ` (16-byte PCM chunk, format tag 1, 1 channel) +
 * `data`. Matches iOS: `RAAudioConvert.pcm16ToWav(_:sampleRate:)`.
 *
 * Use this when a consumer needs a self-describing audio container rather
 * than headerless PCM — e.g. cloud STT providers that upload the bytes as an
 * `audio/wav` file part.
 *
 * @param int16Bytes Raw Int16 mono PCM samples (little-endian). The sample
 *   bytes are copied verbatim after the header.
 * @param sampleRate Capture sample rate in Hz (e.g. 16000).
 * @returns The same samples prefixed with a WAV header.
 */
export function pcm16ToWav(
  int16Bytes: ArrayBuffer,
  sampleRate: number
): ArrayBuffer {
  const pcmFormatTag = 1;
  const channels = 1;
  const bitsPerSample = 16;
  const blockAlign = (channels * bitsPerSample) / 8;
  const byteRate = sampleRate * blockAlign;
  const fmtChunkSize = 16;
  const dataLength = int16Bytes.byteLength;

  const wav = new ArrayBuffer(44 + dataLength);
  const view = new DataView(wav);
  const writeAscii = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) {
      view.setUint8(offset + i, text.charCodeAt(i));
    }
  };

  writeAscii(0, 'RIFF');
  view.setUint32(4, 36 + dataLength, true);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  view.setUint32(16, fmtChunkSize, true);
  view.setUint16(20, pcmFormatTag, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  writeAscii(36, 'data');
  view.setUint32(40, dataLength, true);
  new Uint8Array(wav, 44).set(new Uint8Array(int16Bytes));
  return wav;
}

/**
 * Namespace bundle so the helpers can be attached to the public `RunAnywhere`
 * object (`RunAnywhere.pcm16ToFloat32(...)`) the same way other extensions are.
 */
export const AudioConvert = {
  pcm16ToFloat32,
  pcm16ToFloat32Samples,
  pcm16ToWav,
};
