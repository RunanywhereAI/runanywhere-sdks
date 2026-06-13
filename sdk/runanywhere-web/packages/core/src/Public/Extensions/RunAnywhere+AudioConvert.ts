/**
 * RunAnywhere+AudioConvert.ts
 *
 * Public PCM conversion helpers — mirrors Swift's `RAAudioConvert.swift`
 * exactly: the flat `RunAnywhere.pcm16ToFloat32` / `pcm16ToFloat32Samples` /
 * `pcm16ToWav` statics (no namespace). Callers feeding raw Int16 microphone
 * PCM into `RunAnywhere.detectVoiceActivity(...)` / `transcribe(...)` do not
 * need to reimplement the divide-by-32768.0 normalisation, matching the
 * canonical commons `rac_audio_pcm16_to_float32` audio normalisation contract.
 */

/**
 * Convert a buffer of Int16 PCM samples to Float32 samples in the range
 * `[-1.0, 1.0]`. Divides each sample by `32768.0`.
 *
 * Mirrors Swift `RunAnywhere.pcm16ToFloat32(_:)`.
 *
 * @param int16Bytes Raw Int16 PCM samples (little-endian, as captured by
 *   `getUserMedia` / `AudioWorklet`). The bit pattern is preserved verbatim.
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
 * Convenience alias returning the normalised samples directly. Mirrors Swift
 * `RunAnywhere.pcm16ToFloat32Samples(_:)`. On Web both overloads return a
 * `Float32Array`; this name exists for cross-SDK call-site parity with Swift.
 */
export function pcm16ToFloat32Samples(int16Bytes: ArrayBuffer): Float32Array {
  return pcm16ToFloat32(int16Bytes);
}

/**
 * Wrap raw 16-bit mono PCM samples in a canonical 44-byte WAV (RIFF)
 * container: `RIFF` + `fmt ` (16-byte PCM chunk, format tag 1, 1 channel) +
 * `data`. Pure-TS port of Swift `RunAnywhere.pcm16ToWav(_:sampleRate:)`
 * (RAAudioConvert.swift:67-98).
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
export function pcm16ToWav(int16Bytes: ArrayBuffer, sampleRate: number): Uint8Array {
  const pcmFormatTag = 1;
  const channels = 1;
  const bitsPerSample = 16;
  const blockAlign = (channels * bitsPerSample) / 8;
  const byteRate = sampleRate * blockAlign;
  const fmtChunkSize = 16;
  const dataLength = int16Bytes.byteLength;

  const wav = new Uint8Array(44 + dataLength);
  const view = new DataView(wav.buffer);
  let offset = 0;
  const appendASCII = (text: string): void => {
    for (let i = 0; i < text.length; i++) {
      wav[offset++] = text.charCodeAt(i);
    }
  };
  const appendUint32 = (value: number): void => {
    view.setUint32(offset, value, true);
    offset += 4;
  };
  const appendUint16 = (value: number): void => {
    view.setUint16(offset, value, true);
    offset += 2;
  };

  appendASCII('RIFF');
  appendUint32(36 + dataLength);
  appendASCII('WAVE');
  appendASCII('fmt ');
  appendUint32(fmtChunkSize);
  appendUint16(pcmFormatTag);
  appendUint16(channels);
  appendUint32(sampleRate);
  appendUint32(byteRate);
  appendUint16(blockAlign);
  appendUint16(bitsPerSample);
  appendASCII('data');
  appendUint32(dataLength);
  wav.set(new Uint8Array(int16Bytes), offset);
  return wav;
}
