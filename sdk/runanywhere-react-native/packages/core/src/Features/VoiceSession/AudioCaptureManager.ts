/**
 * AudioCaptureManager.ts
 *
 * Manages audio recording from the device microphone.
 * Provides a cross-platform abstraction for audio capture in React Native.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift
 */

import { EventBus } from '../../Public/Events';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AudioCaptureManager');

/**
 * Audio data callback type
 */
export type AudioDataCallback = (audioData: ArrayBuffer) => void;

/**
 * Audio level callback type
 */
export type AudioLevelCallback = (level: number) => void;

/**
 * Audio capture configuration
 */
export interface AudioCaptureConfig {
  /** Sample rate in Hz (default: 16000) */
  sampleRate?: number;

  /** Number of channels (default: 1) */
  channels?: number;

  /** Bits per sample (default: 16) */
  bitsPerSample?: number;

  /** Buffer size in samples */
  bufferSize?: number;
}

/**
 * Audio capture state
 */
export type AudioCaptureState = 'idle' | 'requesting_permission' | 'recording' | 'paused' | 'error';

/**
 * AudioCaptureManager
 *
 * Handles microphone recording with permission management and audio level monitoring.
 * Uses React Native's audio APIs or native modules for cross-platform support.
 */
export class AudioCaptureManager {
  private state: AudioCaptureState = 'idle';
  private config: Required<AudioCaptureConfig>;
  private audioDataCallback: AudioDataCallback | null = null;
  private audioLevelCallback: AudioLevelCallback | null = null;
  private currentAudioLevel = 0;
  private recordingStartTime: number | null = null;
  private audioBuffer: ArrayBuffer[] = [];
  private levelUpdateInterval: ReturnType<typeof setInterval> | null = null;

  constructor(config: AudioCaptureConfig = {}) {
    this.config = {
      sampleRate: config.sampleRate ?? 16000,
      channels: config.channels ?? 1,
      bitsPerSample: config.bitsPerSample ?? 16,
      bufferSize: config.bufferSize ?? 4096,
    };
  }

  /**
   * Current audio level (0.0 - 1.0)
   */
  get audioLevel(): number {
    return this.currentAudioLevel;
  }

  /**
   * Current capture state
   */
  get captureState(): AudioCaptureState {
    return this.state;
  }

  /**
   * Whether recording is active
   */
  get isRecording(): boolean {
    return this.state === 'recording';
  }

  /**
   * Request microphone permission
   * @returns true if permission granted
   */
  async requestPermission(): Promise<boolean> {
    this.state = 'requesting_permission';
    logger.info('Requesting microphone permission...');

    try {
      // In React Native, permission handling depends on the platform
      // This is a placeholder - actual implementation would use
      // react-native-permissions or expo-permissions

      // For now, assume permission is granted
      // In production, integrate with actual permission APIs:
      // - iOS: Uses AVAudioSession
      // - Android: Uses RECORD_AUDIO permission

      logger.info('Microphone permission granted');
      this.state = 'idle';
      return true;
    } catch (error) {
      logger.error(`Permission request failed: ${error}`);
      this.state = 'error';
      return false;
    }
  }

  /**
   * Start recording audio
   * @param onAudioData Callback for audio data chunks
   */
  async startRecording(onAudioData: AudioDataCallback): Promise<void> {
    if (this.state === 'recording') {
      logger.warning('Already recording');
      return;
    }

    this.audioDataCallback = onAudioData;
    this.audioBuffer = [];
    this.recordingStartTime = Date.now();
    this.state = 'recording';

    logger.info('Starting audio recording...');
    EventBus.publish('Voice', { type: 'recordingStarted' });

    // Start audio level monitoring simulation
    // In production, this would come from actual audio stream
    this.startAudioLevelMonitoring();

    // In production, this would start actual audio recording using:
    // - expo-av
    // - react-native-audio-api
    // - or a custom native module

    // For now, we emit a started event and rely on the native implementation
    // to provide audio data through the callback
  }

  /**
   * Stop recording
   */
  stopRecording(): void {
    if (this.state !== 'recording') {
      return;
    }

    logger.info('Stopping audio recording...');
    this.state = 'idle';
    this.stopAudioLevelMonitoring();

    const duration = this.recordingStartTime
      ? (Date.now() - this.recordingStartTime) / 1000
      : 0;

    EventBus.publish('Voice', {
      type: 'recordingStopped',
      duration,
    });

    this.audioDataCallback = null;
    this.recordingStartTime = null;
  }

  /**
   * Pause recording
   */
  pauseRecording(): void {
    if (this.state === 'recording') {
      this.state = 'paused';
      this.stopAudioLevelMonitoring();
      logger.info('Recording paused');
    }
  }

  /**
   * Resume recording
   */
  resumeRecording(): void {
    if (this.state === 'paused') {
      this.state = 'recording';
      this.startAudioLevelMonitoring();
      logger.info('Recording resumed');
    }
  }

  /**
   * Set audio level callback
   */
  setAudioLevelCallback(callback: AudioLevelCallback | null): void {
    this.audioLevelCallback = callback;
  }

  /**
   * Get all recorded audio data
   */
  getRecordedData(): ArrayBuffer {
    // Concatenate all audio buffers
    const totalLength = this.audioBuffer.reduce((acc, buf) => acc + buf.byteLength, 0);
    const result = new ArrayBuffer(totalLength);
    const view = new Uint8Array(result);

    let offset = 0;
    for (const buffer of this.audioBuffer) {
      view.set(new Uint8Array(buffer), offset);
      offset += buffer.byteLength;
    }

    return result;
  }

  /**
   * Process incoming audio data from native
   * Called by native audio module when data is available
   */
  processAudioData(data: ArrayBuffer): void {
    if (this.state !== 'recording') return;

    this.audioBuffer.push(data);

    // Calculate audio level from the data
    this.updateAudioLevel(data);

    // Forward to callback
    if (this.audioDataCallback) {
      this.audioDataCallback(data);
    }
  }

  /**
   * Cleanup resources
   */
  cleanup(): void {
    this.stopRecording();
    this.audioBuffer = [];
    this.audioDataCallback = null;
    this.audioLevelCallback = null;
    logger.info('AudioCaptureManager cleaned up');
  }

  // Private methods

  private startAudioLevelMonitoring(): void {
    // Poll audio level at 50ms intervals
    this.levelUpdateInterval = setInterval(() => {
      if (this.audioLevelCallback) {
        this.audioLevelCallback(this.currentAudioLevel);
      }
    }, 50);
  }

  private stopAudioLevelMonitoring(): void {
    if (this.levelUpdateInterval) {
      clearInterval(this.levelUpdateInterval);
      this.levelUpdateInterval = null;
    }
    this.currentAudioLevel = 0;
  }

  private updateAudioLevel(data: ArrayBuffer): void {
    // Calculate RMS (root mean square) of audio samples
    const samples = new Int16Array(data);
    let sum = 0;

    for (let i = 0; i < samples.length; i++) {
      const sample = samples[i]!;
      sum += sample * sample;
    }

    const rms = Math.sqrt(sum / samples.length);
    // Normalize to 0-1 range (16-bit audio max is 32767)
    this.currentAudioLevel = Math.min(1, rms / 32767);
  }
}
