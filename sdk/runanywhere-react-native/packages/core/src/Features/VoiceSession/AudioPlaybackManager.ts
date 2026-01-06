/**
 * AudioPlaybackManager.ts
 *
 * Manages audio playback for TTS output.
 * Provides a cross-platform abstraction for audio playback in React Native.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift
 */

import { EventBus } from '../../Public/Events';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AudioPlaybackManager');

/**
 * Playback state
 */
export type PlaybackState = 'idle' | 'loading' | 'playing' | 'paused' | 'stopped' | 'error';

/**
 * Playback completion callback
 */
export type PlaybackCompletionCallback = () => void;

/**
 * Playback error callback
 */
export type PlaybackErrorCallback = (error: Error) => void;

/**
 * Audio playback configuration
 */
export interface PlaybackConfig {
  /** Volume (0.0 - 1.0) */
  volume?: number;

  /** Playback rate multiplier */
  rate?: number;
}

/**
 * AudioPlaybackManager
 *
 * Handles audio playback for TTS and other audio output needs.
 * Uses React Native's audio APIs or native modules for cross-platform support.
 */
export class AudioPlaybackManager {
  private state: PlaybackState = 'idle';
  private volume = 1.0;
  private rate = 1.0;
  private completionCallback: PlaybackCompletionCallback | null = null;
  private errorCallback: PlaybackErrorCallback | null = null;
  private currentAudioData: ArrayBuffer | null = null;
  private playbackStartTime: number | null = null;
  private playbackDuration: number | null = null;

  constructor(config: PlaybackConfig = {}) {
    this.volume = config.volume ?? 1.0;
    this.rate = config.rate ?? 1.0;
  }

  /**
   * Current playback state
   */
  get playbackState(): PlaybackState {
    return this.state;
  }

  /**
   * Whether audio is currently playing
   */
  get isPlaying(): boolean {
    return this.state === 'playing';
  }

  /**
   * Whether audio is paused
   */
  get isPaused(): boolean {
    return this.state === 'paused';
  }

  /**
   * Current volume level
   */
  get currentVolume(): number {
    return this.volume;
  }

  /**
   * Current playback rate
   */
  get currentRate(): number {
    return this.rate;
  }

  /**
   * Play audio data
   * @param audioData Audio data to play (WAV format expected)
   * @returns Promise that resolves when playback completes
   */
  async play(audioData: ArrayBuffer | string): Promise<void> {
    if (this.state === 'playing') {
      this.stop();
    }

    this.state = 'loading';
    logger.info('Loading audio for playback...');

    try {
      // Convert base64 string to ArrayBuffer if needed
      let data: ArrayBuffer;
      if (typeof audioData === 'string') {
        // Decode base64
        const binaryString = atob(audioData);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
        data = bytes.buffer;
      } else {
        data = audioData;
      }

      this.currentAudioData = data;
      this.playbackStartTime = Date.now();

      // Estimate duration from audio data
      // Assuming 16-bit PCM at 22050 Hz (common TTS output)
      this.playbackDuration = data.byteLength / (22050 * 2);

      this.state = 'playing';
      logger.info(`Playing audio (${(data.byteLength / 1024).toFixed(1)} KB)`);

      EventBus.publish('Voice', {
        type: 'playbackStarted',
        duration: this.playbackDuration,
      });

      // In production, this would use actual audio playback APIs:
      // - expo-av Audio.Sound
      // - react-native-audio-api
      // - or a custom native module

      // For now, simulate playback completion after estimated duration
      return new Promise((resolve, reject) => {
        const timeoutMs = (this.playbackDuration ?? 1) * 1000 / this.rate;

        setTimeout(() => {
          if (this.state === 'playing') {
            this.handlePlaybackComplete();
            resolve();
          } else if (this.state === 'error') {
            reject(new Error('Playback failed'));
          } else {
            resolve(); // Stopped or paused
          }
        }, timeoutMs);
      });

    } catch (error) {
      this.state = 'error';
      logger.error(`Playback failed: ${error}`);
      EventBus.publish('Voice', { type: 'playbackFailed', error: String(error) });
      throw error;
    }
  }

  /**
   * Play audio from base64 string
   */
  async playBase64(base64Audio: string): Promise<void> {
    return this.play(base64Audio);
  }

  /**
   * Stop playback
   */
  stop(): void {
    if (this.state === 'idle' || this.state === 'stopped') {
      return;
    }

    logger.info('Stopping playback');
    this.state = 'stopped';
    this.currentAudioData = null;

    EventBus.publish('Voice', { type: 'playbackStopped' });

    if (this.completionCallback) {
      this.completionCallback();
    }
  }

  /**
   * Pause playback
   */
  pause(): void {
    if (this.state === 'playing') {
      this.state = 'paused';
      logger.info('Playback paused');
      EventBus.publish('Voice', { type: 'playbackPaused' });
    }
  }

  /**
   * Resume playback
   */
  resume(): void {
    if (this.state === 'paused') {
      this.state = 'playing';
      logger.info('Playback resumed');
      EventBus.publish('Voice', { type: 'playbackResumed' });
    }
  }

  /**
   * Set volume
   * @param volume Volume level (0.0 - 1.0)
   */
  setVolume(volume: number): void {
    this.volume = Math.max(0, Math.min(1, volume));
    logger.debug(`Volume set to ${this.volume}`);
  }

  /**
   * Set playback rate
   * @param rate Playback rate multiplier (0.5 - 2.0)
   */
  setRate(rate: number): void {
    this.rate = Math.max(0.5, Math.min(2, rate));
    logger.debug(`Rate set to ${this.rate}`);
  }

  /**
   * Set completion callback
   */
  setCompletionCallback(callback: PlaybackCompletionCallback | null): void {
    this.completionCallback = callback;
  }

  /**
   * Set error callback
   */
  setErrorCallback(callback: PlaybackErrorCallback | null): void {
    this.errorCallback = callback;
  }

  /**
   * Get current playback position in seconds
   */
  getCurrentPosition(): number {
    if (!this.playbackStartTime || this.state !== 'playing') {
      return 0;
    }
    return (Date.now() - this.playbackStartTime) / 1000;
  }

  /**
   * Get total duration in seconds
   */
  getDuration(): number {
    return this.playbackDuration ?? 0;
  }

  /**
   * Cleanup resources
   */
  cleanup(): void {
    this.stop();
    this.completionCallback = null;
    this.errorCallback = null;
    this.currentAudioData = null;
    this.state = 'idle';
    logger.info('AudioPlaybackManager cleaned up');
  }

  // Private methods

  private handlePlaybackComplete(): void {
    const duration = this.playbackStartTime
      ? (Date.now() - this.playbackStartTime) / 1000
      : 0;

    this.state = 'idle';
    this.currentAudioData = null;
    this.playbackStartTime = null;

    logger.info(`Playback completed (${duration.toFixed(2)}s)`);

    EventBus.publish('Voice', {
      type: 'playbackCompleted',
      duration,
    });

    if (this.completionCallback) {
      this.completionCallback();
    }
  }
}
