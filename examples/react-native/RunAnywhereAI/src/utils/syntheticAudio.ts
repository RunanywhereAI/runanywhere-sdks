/**
 * syntheticAudio - deterministic 16-kHz mono PCM16 WAV generators.
 *
 * RN analog of iOS `SyntheticInputGenerator.swift` — produces the silent and
 * sine-tone inputs the STT benchmarks transcribe, so runs are reproducible
 * without microphone access.
 */

const SAMPLE_RATE = 16000;

function wavFromPcm16(pcm: Int16Array): Uint8Array {
  const dataSize = pcm.length * 2;
  const wav = new Uint8Array(44 + dataSize);
  const view = new DataView(wav.buffer);

  const writeString = (offset: number, str: string) => {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  };

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true); // PCM fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, SAMPLE_RATE, true);
  view.setUint32(28, SAMPLE_RATE * 2, true); // byte rate
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample
  writeString(36, 'data');
  view.setUint32(40, dataSize, true);

  for (let i = 0; i < pcm.length; i++) {
    view.setInt16(44 + i * 2, pcm[i], true);
  }
  return wav;
}

/** Silent WAV of the given duration. */
export function silentAudioWav(durationSeconds: number): Uint8Array {
  return wavFromPcm16(
    new Int16Array(Math.round(SAMPLE_RATE * durationSeconds))
  );
}

/** 440 Hz sine-tone WAV of the given duration. */
export function sineWaveAudioWav(
  durationSeconds: number,
  frequencyHz: number = 440
): Uint8Array {
  const sampleCount = Math.round(SAMPLE_RATE * durationSeconds);
  const pcm = new Int16Array(sampleCount);
  const amplitude = 0.3 * 0x7fff;
  for (let i = 0; i < sampleCount; i++) {
    pcm[i] = Math.round(
      amplitude * Math.sin((2 * Math.PI * frequencyHz * i) / SAMPLE_RATE)
    );
  }
  return wavFromPcm16(pcm);
}

export const SYNTHETIC_AUDIO_SAMPLE_RATE = SAMPLE_RATE;
