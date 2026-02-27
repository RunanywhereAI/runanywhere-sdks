/**
 * AudioFileLoader
 *
 * Decodes a browser audio File/Blob into a mono Float32Array PCM buffer
 * suitable for on-device STT transcription.
 *
 * Centralizing this conversion in the SDK means host applications only
 * need to pass a File — the resampling, channel-mixing, and Web Audio
 * setup are all handled here.
 *
 * Supported input formats: anything the browser's AudioContext can decode
 * (wav, mp3, m4a, ogg, flac, aac, opus, webm, etc.)
 */

export interface AudioFileLoaderResult {
  /** Mono PCM samples, resampled to targetSampleRate */
  samples: Float32Array;
  /** Sample rate of the returned buffer (matches targetSampleRate) */
  sampleRate: number;
  /** Original file duration in seconds */
  durationSeconds: number;
}

export class AudioFileLoader {
  /**
   * Decode an audio File to a mono Float32Array PCM buffer.
   * Resamples to targetSampleRate if the file's native rate differs.
   *
   * @param file            Any browser-supported audio file
   * @param targetSampleRate Output sample rate (default: 16000 Hz for STT models)
   */
  static async toFloat32Array(
    file: File,
    targetSampleRate = 16000,
  ): Promise<AudioFileLoaderResult> {
    const arrayBuffer = await file.arrayBuffer();

    // Decode at the file's native sample rate
    const nativeCtx = new AudioContext();
    let audioBuffer: AudioBuffer;
    try {
      audioBuffer = await nativeCtx.decodeAudioData(arrayBuffer);
    } finally {
      await nativeCtx.close();
    }

    const durationSeconds = audioBuffer.duration;

    // If already at target rate, take channel 0 directly (copy to avoid detached buffer issues)
    if (audioBuffer.sampleRate === targetSampleRate) {
      return {
        samples: new Float32Array(audioBuffer.getChannelData(0)),
        sampleRate: targetSampleRate,
        durationSeconds,
      };
    }

    // Resample to target rate using OfflineAudioContext
    const targetLength = Math.ceil(durationSeconds * targetSampleRate);
    const offlineCtx = new OfflineAudioContext(1, targetLength, targetSampleRate);
    const source = offlineCtx.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(offlineCtx.destination);
    source.start();

    const resampled = await offlineCtx.startRendering();
    return {
      samples: new Float32Array(resampled.getChannelData(0)),
      sampleRate: targetSampleRate,
      durationSeconds,
    };
  }
}
