/**
 * AudioPlaybackManager.ts
 *
 * Manages audio playback for TTS output.
 * Provides a cross-platform abstraction for audio playback in React Native.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift
 */

import { Platform, NativeModules } from 'react-native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AudioPlaybackManager');

/**
 * Safely publish an event to the EventBus
 * Uses lazy loading to avoid circular dependency issues during module initialization
 */
function safePublish(eventType: string, event: Record<string, unknown>): void {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { EventBus } = require('../../Public/Events');
    if (EventBus?.publish) {
      EventBus.publish(eventType, event);
    }
  } catch {
    // Ignore EventBus errors - events are non-critical for playback functionality
  }
}

// Native iOS Audio Module
const NativeAudioModule = Platform.OS === 'ios' ? NativeModules.NativeAudioModule : null;

// Lazy load react-native-sound for Android
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let Sound: any = null;

function getSound() {
  if (Platform.OS === 'ios') return null;
  if (!Sound) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      Sound = require('react-native-sound').default;
      Sound.setCategory('Playback');
    } catch {
      logger.warning('react-native-sound not available');
      return null;
    }
  }
  return Sound;
}

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
 * Uses platform-native audio APIs:
 * - iOS: NativeAudioModule (AVAudioPlayer)
 * - Android: react-native-sound
 */
export class AudioPlaybackManager {
  private state: PlaybackState = 'idle';
  private volume = 1.0;
  private rate = 1.0;
  private completionCallback: PlaybackCompletionCallback | null = null;
  private errorCallback: PlaybackErrorCallback | null = null;
  private playbackStartTime: number | null = null;
  private playbackDuration: number | null = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private currentSound: any = null;

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
   * Play audio data (base64 PCM float32 from TTS)
   * @param audioData Base64 encoded audio data from TTS synthesis
   * @param sampleRate Sample rate of the audio (default: 22050)
   * @returns Promise that resolves when playback completes
   */
  async play(audioData: ArrayBuffer | string, sampleRate = 22050): Promise<void> {
    if (this.state === 'playing') {
      this.stop();
    }

    this.state = 'loading';
    logger.info('Loading audio for playback...');

    try {
      // Convert base64 PCM to WAV file
      let wavPath: string;
      if (typeof audioData === 'string') {
        wavPath = await this.createWavFromPCMFloat32(audioData, sampleRate);
      } else {
        // ArrayBuffer - convert to base64 first
        const base64 = this.arrayBufferToBase64(audioData);
        wavPath = await this.createWavFromPCMFloat32(base64, sampleRate);
      }

      // Play the WAV file
      await this.playFile(wavPath);

    } catch (error) {
      this.state = 'error';
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Playback failed: ${err.message}`);
      safePublish('Voice', { type: 'playbackFailed', error: err.message });

      if (this.errorCallback) {
        this.errorCallback(err);
      }
      throw error;
    }
  }

  /**
   * Play audio from file path
   */
  async playFile(filePath: string): Promise<void> {
    this.playbackStartTime = Date.now();
    this.state = 'playing';

    logger.info(`Playing audio file: ${filePath}`);
    safePublish('Voice', { type: 'playbackStarted' });

    if (Platform.OS === 'ios') {
      await this.playFileIOS(filePath);
    } else {
      await this.playFileAndroid(filePath);
    }
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

    if (Platform.OS === 'ios' && NativeAudioModule) {
      NativeAudioModule.stopPlayback().catch(() => {});
    } else if (this.currentSound) {
      this.currentSound.stop();
      this.currentSound.release();
      this.currentSound = null;
    }

    safePublish('Voice', { type: 'playbackStopped' });

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

      if (Platform.OS === 'ios' && NativeAudioModule) {
        NativeAudioModule.pausePlayback().catch(() => {});
      } else if (this.currentSound) {
        this.currentSound.pause();
      }

      logger.info('Playback paused');
      safePublish('Voice', { type: 'playbackPaused' });
    }
  }

  /**
   * Resume playback
   */
  resume(): void {
    if (this.state === 'paused') {
      this.state = 'playing';

      if (Platform.OS === 'ios' && NativeAudioModule) {
        NativeAudioModule.resumePlayback().catch(() => {});
      } else if (this.currentSound) {
        this.currentSound.play();
      }

      logger.info('Playback resumed');
      safePublish('Voice', { type: 'playbackResumed' });
    }
  }

  /**
   * Set volume
   * @param volume Volume level (0.0 - 1.0)
   */
  setVolume(volume: number): void {
    this.volume = Math.max(0, Math.min(1, volume));
    if (this.currentSound) {
      this.currentSound.setVolume(this.volume);
    }
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
    this.state = 'idle';
    logger.info('AudioPlaybackManager cleaned up');
  }

  // Private methods

  private async playFileIOS(filePath: string): Promise<void> {
    if (!NativeAudioModule) {
      throw new Error('NativeAudioModule not available');
    }

    return new Promise((resolve, reject) => {
      NativeAudioModule.playAudio(filePath)
        .then((result: { duration: number }) => {
          this.playbackDuration = result.duration;

          // Wait for playback to complete
          const checkInterval = setInterval(async () => {
            if (this.state !== 'playing') {
              clearInterval(checkInterval);
              resolve();
              return;
            }

            try {
              const status = await NativeAudioModule.getPlaybackStatus();
              if (!status.isPlaying) {
                clearInterval(checkInterval);
                this.handlePlaybackComplete();
                resolve();
              }
            } catch {
              clearInterval(checkInterval);
              this.handlePlaybackComplete();
              resolve();
            }
          }, 100);
        })
        .catch((error: Error) => {
          this.state = 'error';
          reject(error);
        });
    });
  }

  private async playFileAndroid(filePath: string): Promise<void> {
    const SoundClass = getSound();
    if (!SoundClass) {
      throw new Error('react-native-sound not available');
    }

    return new Promise((resolve, reject) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      this.currentSound = new SoundClass(filePath, '', (error: any) => {
        if (error) {
          this.state = 'error';
          reject(error);
          return;
        }

        this.playbackDuration = this.currentSound.getDuration();
        this.currentSound.setVolume(this.volume);

        this.currentSound.play((success: boolean) => {
          if (this.currentSound) {
            this.currentSound.release();
            this.currentSound = null;
          }

          if (success) {
            this.handlePlaybackComplete();
            resolve();
          } else {
            this.state = 'error';
            reject(new Error('Playback failed'));
          }
        });
      });
    });
  }

  private handlePlaybackComplete(): void {
    const duration = this.playbackStartTime
      ? (Date.now() - this.playbackStartTime) / 1000
      : 0;

    this.state = 'idle';
    this.playbackStartTime = null;

    logger.info(`Playback completed (${duration.toFixed(2)}s)`);

    safePublish('Voice', {
      type: 'playbackCompleted',
      duration,
    });

    if (this.completionCallback) {
      this.completionCallback();
    }
  }

  /**
   * Convert base64 PCM float32 audio to WAV file
   * TTS output is base64-encoded float32 PCM samples
   */
  private async createWavFromPCMFloat32(audioBase64: string, sampleRate: number): Promise<string> {
    // Decode base64 to get raw bytes
    const binaryString = atob(audioBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    // Convert float32 samples to int16 (WAV compatible)
    const floatView = new Float32Array(bytes.buffer);
    const numSamples = floatView.length;
    const int16Samples = new Int16Array(numSamples);

    for (let i = 0; i < numSamples; i++) {
      const floatSample = floatView[i] ?? 0;
      const sample = Math.max(-1, Math.min(1, floatSample));
      int16Samples[i] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
    }

    // Create WAV header (44 bytes)
    const wavDataSize = int16Samples.length * 2;
    const wavBuffer = new ArrayBuffer(44 + wavDataSize);
    const wavView = new DataView(wavBuffer);

    // RIFF header
    this.writeString(wavView, 0, 'RIFF');
    wavView.setUint32(4, 36 + wavDataSize, true);
    this.writeString(wavView, 8, 'WAVE');

    // fmt chunk
    this.writeString(wavView, 12, 'fmt ');
    wavView.setUint32(16, 16, true);
    wavView.setUint16(20, 1, true); // PCM
    wavView.setUint16(22, 1, true); // mono
    wavView.setUint32(24, sampleRate, true);
    wavView.setUint32(28, sampleRate * 2, true);
    wavView.setUint16(32, 2, true);
    wavView.setUint16(34, 16, true);

    // data chunk
    this.writeString(wavView, 36, 'data');
    wavView.setUint32(40, wavDataSize, true);

    // Copy audio data
    const wavBytes = new Uint8Array(wavBuffer);
    const int16Bytes = new Uint8Array(int16Samples.buffer);
    for (let i = 0; i < int16Bytes.length; i++) {
      wavBytes[44 + i] = int16Bytes[i]!;
    }

    // Write to file
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const RNFS = require('react-native-fs');
      const fileName = `tts_${Date.now()}.wav`;
      const filePath = `${RNFS.CachesDirectoryPath}/${fileName}`;

      const wavBase64 = this.arrayBufferToBase64(wavBuffer);
      await RNFS.writeFile(filePath, wavBase64, 'base64');

      logger.info(`WAV file created: ${filePath}`);
      return filePath;
    } catch (error) {
      logger.error(`Failed to create WAV file: ${error}`);
      throw error;
    }
  }

  private writeString(view: DataView, offset: number, str: string): void {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  }

  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]!);
    }
    return btoa(binary);
  }
}
