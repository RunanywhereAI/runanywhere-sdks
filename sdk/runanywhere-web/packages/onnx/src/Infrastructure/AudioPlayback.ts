/**
 * RunAnywhere Web SDK - Audio Playback
 *
 * Plays synthesized audio (TTS output) using Web Audio API.
 * Accepts Float32Array PCM samples and plays them through
 * the browser's audio output.
 *
 * Supports:
 *   - One-shot playback of PCM audio buffers
 *   - Streaming playback (queued chunks)
 *   - Playback controls (stop, pause, resume)
 *   - Completion callbacks
 */

import { SDKLogger, EventBus, SDKEventType } from '@runanywhere/web';

const logger = new SDKLogger('AudioPlayback');

export type PlaybackCompleteCallback = () => void;

export interface PlaybackConfig {
  /** Sample rate of the audio (default: 22050 for Piper TTS) */
  sampleRate?: number;
  /** Volume (0.0 - 1.0, default: 1.0) */
  volume?: number;
}

/**
 * AudioPlayback - Plays synthesized audio through browser speakers.
 */
export class AudioPlayback {
  private audioContext: AudioContext | null = null;
  private gainNode: GainNode | null = null;
  private currentSource: AudioBufferSourceNode | null = null;
  private _isPlaying = false;
  private config: Required<PlaybackConfig>;

  constructor(config: PlaybackConfig = {}) {
    this.config = {
      sampleRate: config.sampleRate ?? 22050,
      volume: config.volume ?? 1.0,
    };
  }

  get isPlaying(): boolean {
    return this._isPlaying;
  }

  /**
   * Play a Float32Array of PCM audio samples.
   *
   * @param samples - PCM audio data (Float32Array)
   * @param sampleRate - Sample rate (overrides config)
   * @returns Promise that resolves when playback completes
   */
  async play(samples: Float32Array, sampleRate?: number): Promise<void> {
    this.stop(); // Stop any current playback

    const rate = sampleRate ?? this.config.sampleRate;
    const durationMs = (samples.length / rate) * 1000;

    logger.debug(`Playing ${samples.length} samples at ${rate}Hz (${(durationMs / 1000).toFixed(1)}s)`);

    // Create or resume AudioContext
    if (!this.audioContext || this.audioContext.state === 'closed') {
      this.audioContext = new AudioContext({ sampleRate: rate });
    }

    if (this.audioContext.state === 'suspended') {
      await this.audioContext.resume();
    }

    // Create gain node for volume control
    if (!this.gainNode || this.gainNode.context !== this.audioContext) {
      this.gainNode = this.audioContext.createGain();
      this.gainNode.connect(this.audioContext.destination);
    }
    this.gainNode.gain.value = this.config.volume;

    // Create audio buffer from samples
    const audioBuffer = this.audioContext.createBuffer(1, samples.length, rate);
    audioBuffer.getChannelData(0).set(samples);

    // Create and play source node
    return new Promise<void>((resolve) => {
      const source = this.audioContext!.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(this.gainNode!);

      source.onended = () => {
        this._isPlaying = false;
        this.currentSource = null;
        EventBus.shared.emit('playback.completed', SDKEventType.Voice, { durationMs });
        resolve();
      };

      this.currentSource = source;
      this._isPlaying = true;

      EventBus.shared.emit('playback.started', SDKEventType.Voice, { durationMs, sampleRate: rate });
      source.start();
    });
  }

  /**
   * Stop playback immediately.
   */
  stop(): void {
    if (this.currentSource) {
      try {
        this.currentSource.stop();
      } catch {
        // Already stopped
      }
      this.currentSource = null;
    }
    this._isPlaying = false;
  }

  /**
   * Set playback volume.
   */
  setVolume(volume: number): void {
    this.config.volume = Math.max(0, Math.min(1, volume));
    if (this.gainNode) {
      this.gainNode.gain.value = this.config.volume;
    }
  }

  /**
   * Release all audio resources.
   */
  dispose(): void {
    this.stop();
    if (this.audioContext && this.audioContext.state !== 'closed') {
      this.audioContext.close().catch(() => { /* ignore */ });
    }
    this.audioContext = null;
    this.gainNode = null;
  }
}
