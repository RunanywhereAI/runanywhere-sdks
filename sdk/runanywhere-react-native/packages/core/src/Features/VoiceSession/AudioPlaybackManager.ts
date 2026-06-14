/**
 * AudioPlaybackManager.ts
 *
 * Internal audio playback used by `RunAnywhere.speak()` and
 * `RunAnywhere.stopSpeaking()`. Bridges the JS-only TTS PCM bytes through the
 * SDK's own Nitro `AudioPlayback` HybridObject (AVAudioPlayer on iOS,
 * AudioTrack on Android) — no host-app native module required.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift`.
 */

import { AudioPlayback } from '../../Internal/Nitro/NitroAudioPlaybackSpec';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AudioPlaybackManager');

type PlaybackState = 'idle' | 'loading' | 'playing' | 'paused' | 'stopped' | 'error';

export class AudioPlaybackManager {
  private state: PlaybackState = 'idle';

  /**
   * Play raw PCM float32 audio (the format emitted by TTS) at the given
   * sample rate. Encodes to an in-memory 16-bit WAV and hands the bytes to
   * the native player directly.
   */
  async play(audioData: ArrayBuffer | string, sampleRate = 22050): Promise<void> {
    if (this.state === 'playing') {
      this.stop();
    }

    this.state = 'loading';
    logger.info('Loading audio for playback...');

    try {
      const pcmBytes =
        typeof audioData === 'string'
          ? base64ToArrayBuffer(audioData)
          : audioData;
      const wavBuffer = createWavFromPCMFloat32(pcmBytes, sampleRate);

      this.state = 'playing';
      // Resolves when playback finishes; rejects on failure/interruption.
      await AudioPlayback.play(wavBuffer);
      this.state = 'idle';
    } catch (error) {
      // `stop()` may have run while we awaited — re-read the state without
      // TS narrowing it to the pre-await value.
      if ((this.state as PlaybackState) === 'stopped') {
        // stop() interrupts the in-flight play() — not an error.
        return;
      }
      this.state = 'error';
      logger.error(
        `Playback failed: ${error instanceof Error ? error.message : String(error)}`
      );
      throw error;
    }
  }

  /** Play an audio file from disk. Resolves when playback finishes. */
  async playFile(filePath: string): Promise<void> {
    this.state = 'playing';
    logger.info(`Playing audio file: ${filePath}`);

    try {
      await AudioPlayback.playFile(filePath);
      this.state = 'idle';
    } catch (error) {
      // `stop()` may have run while we awaited — re-read the state without
      // TS narrowing it to the pre-await value.
      if ((this.state as PlaybackState) === 'stopped') {
        return;
      }
      this.state = 'error';
      throw error;
    }
  }

  /** Stop current playback (rejects an in-flight play promise natively). */
  stop(): void {
    if (this.state === 'idle' || this.state === 'stopped') return;

    logger.info('Stopping playback');
    this.state = 'stopped';
    try {
      AudioPlayback.stop();
    } catch (error) {
      logger.warning(
        `stop() failed: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /** Pause current playback (Swift AudioPlaybackManager.pause() parity). */
  pause(): void {
    if (this.state !== 'playing') return;
    this.state = 'paused';
    AudioPlayback.pause();
  }

  /** Resume paused playback (Swift AudioPlaybackManager.resume() parity). */
  resume(): void {
    if (this.state !== 'paused') return;
    this.state = 'playing';
    AudioPlayback.resume();
  }

  /** Whether audio is currently playing. */
  get isPlaying(): boolean {
    return AudioPlayback.isPlaying;
  }

  /** Current playback position in seconds. */
  get currentTime(): number {
    return AudioPlayback.currentTime;
  }

  /** Total duration of the loaded audio in seconds. */
  get duration(): number {
    return AudioPlayback.duration;
  }
}

/**
 * Encode raw float32 PCM samples into an in-memory 16-bit mono WAV buffer.
 */
function createWavFromPCMFloat32(
  pcmFloat32: ArrayBuffer,
  sampleRate: number
): ArrayBuffer {
  const floatView = new Float32Array(pcmFloat32);
  const numSamples = floatView.length;
  const int16Samples = new Int16Array(numSamples);
  for (let i = 0; i < numSamples; i++) {
    const floatSample = floatView[i] ?? 0;
    const sample = Math.max(-1, Math.min(1, floatSample));
    int16Samples[i] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
  }

  const wavDataSize = int16Samples.length * 2;
  const wavBuffer = new ArrayBuffer(44 + wavDataSize);
  const wavView = new DataView(wavBuffer);

  writeString(wavView, 0, 'RIFF');
  wavView.setUint32(4, 36 + wavDataSize, true);
  writeString(wavView, 8, 'WAVE');

  writeString(wavView, 12, 'fmt ');
  wavView.setUint32(16, 16, true);
  wavView.setUint16(20, 1, true);
  wavView.setUint16(22, 1, true);
  wavView.setUint32(24, sampleRate, true);
  wavView.setUint32(28, sampleRate * 2, true);
  wavView.setUint16(32, 2, true);
  wavView.setUint16(34, 16, true);

  writeString(wavView, 36, 'data');
  wavView.setUint32(40, wavDataSize, true);

  const wavBytes = new Uint8Array(wavBuffer);
  const int16Bytes = new Uint8Array(int16Samples.buffer);
  for (let i = 0; i < int16Bytes.length; i++) {
    wavBytes[44 + i] = int16Bytes[i]!;
  }

  return wavBuffer;
}

function writeString(view: DataView, offset: number, str: string): void {
  for (let i = 0; i < str.length; i++) {
    view.setUint8(offset + i, str.charCodeAt(i));
  }
}

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}
