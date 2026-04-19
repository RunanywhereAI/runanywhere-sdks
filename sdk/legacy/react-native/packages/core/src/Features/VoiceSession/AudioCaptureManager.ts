/**
 * AudioCaptureManager.ts
 *
 * Manages audio recording from the device microphone.
 * Provides a cross-platform abstraction for audio capture in React Native.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift
 */

import { Platform, PermissionsAndroid, NativeModules } from 'react-native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AudioCaptureManager');

// Lazy-load EventBus to avoid circular dependency issues during module initialization
// The circular dependency: AudioCaptureManager -> EventBus -> SDKLogger -> ... -> AudioCaptureManager
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let _eventBus: any = null;
function getEventBus() {
  if (!_eventBus) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      _eventBus = require('../../Public/Events').EventBus;
    } catch {
      logger.warning('EventBus not available');
    }
  }
  return _eventBus;
}

/**
 * Safely publish an event to the EventBus
 * Handles cases where EventBus may not be fully initialized
 */
function safePublish(eventType: string, event: Record<string, unknown>): void {
  try {
    const eventBus = getEventBus();
    if (eventBus?.publish) {
      eventBus.publish(eventType, event);
    }
  } catch {
    // Ignore EventBus errors - events are non-critical for audio functionality
  }
}

// Native iOS Audio Module (provided by the app)
const NativeAudioModule = Platform.OS === 'ios' ? NativeModules.NativeAudioModule : null;

// Lazy load LiveAudioStream for Android
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let LiveAudioStream: any = null;

function getLiveAudioStream() {
  if (Platform.OS !== 'android') return null;
  if (!LiveAudioStream) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      LiveAudioStream = require('react-native-live-audio-stream').default;
    } catch {
      logger.warning('react-native-live-audio-stream not available');
      return null;
    }
  }
  return LiveAudioStream;
}

/**
 * Audio data callback type
 */
export type AudioDataCallback = (audioData: ArrayBuffer) => void;

/**
 * Audio level callback type (level is 0.0 - 1.0)
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
}

/**
 * Audio capture state
 */
export type AudioCaptureState = 'idle' | 'requesting_permission' | 'recording' | 'paused' | 'error';

/**
 * AudioCaptureManager
 *
 * Handles microphone recording with permission management and audio level monitoring.
 * Uses platform-native audio APIs:
 * - iOS: NativeAudioModule (AVFoundation)
 * - Android: react-native-live-audio-stream
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
  private recordingPath: string | null = null;
  private androidAudioChunks: string[] = [];

  constructor(config: AudioCaptureConfig = {}) {
    this.config = {
      sampleRate: config.sampleRate ?? 16000,
      channels: config.channels ?? 1,
      bitsPerSample: config.bitsPerSample ?? 16,
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
      if (Platform.OS === 'android') {
        const grants = await PermissionsAndroid.requestMultiple([
          PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
        ]);
        const granted = grants[PermissionsAndroid.PERMISSIONS.RECORD_AUDIO] === PermissionsAndroid.RESULTS.GRANTED;
        logger.info(`Android microphone permission: ${granted ? 'granted' : 'denied'}`);
        this.state = granted ? 'idle' : 'error';
        return granted;
      }

      // iOS: Permission is requested when starting recording
      logger.info('Microphone permission granted (iOS)');
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
  async startRecording(onAudioData?: AudioDataCallback): Promise<void> {
    if (this.state === 'recording') {
      logger.warning('Already recording');
      return;
    }

    this.audioDataCallback = onAudioData ?? null;
    this.audioBuffer = [];
    this.recordingStartTime = Date.now();
    this.state = 'recording';

    logger.info('Starting audio recording...');
    safePublish('Voice', { type: 'recordingStarted' });

    if (Platform.OS === 'ios') {
      await this.startIOSRecording();
    } else {
      await this.startAndroidRecording();
    }
  }

  /**
   * Stop recording and return recorded audio file path
   */
  async stopRecording(): Promise<{ path: string; durationMs: number }> {
    if (this.state !== 'recording') {
      throw new Error('Not recording');
    }

    logger.info('Stopping audio recording...');
    this.state = 'idle';
    this.stopAudioLevelMonitoring();

    const durationMs = this.recordingStartTime ? Date.now() - this.recordingStartTime : 0;
    let path = '';

    if (Platform.OS === 'ios') {
      path = await this.stopIOSRecording();
    } else {
      path = await this.stopAndroidRecording();
    }

    safePublish('Voice', { type: 'recordingStopped', duration: durationMs / 1000 });

    this.audioDataCallback = null;
    this.recordingStartTime = null;

    return { path, durationMs };
  }

  /**
   * Set audio level callback
   */
  setAudioLevelCallback(callback: AudioLevelCallback | null): void {
    this.audioLevelCallback = callback;
  }

  /**
   * Cleanup resources
   */
  cleanup(): void {
    if (this.state === 'recording') {
      this.stopRecording().catch(() => {});
    }
    this.audioBuffer = [];
    this.audioDataCallback = null;
    this.audioLevelCallback = null;
    this.stopAudioLevelMonitoring();
    logger.info('AudioCaptureManager cleaned up');
  }

  // iOS Implementation

  private async startIOSRecording(): Promise<void> {
    if (!NativeAudioModule) {
      throw new Error('NativeAudioModule not available on iOS');
    }

    try {
      const result = await NativeAudioModule.startRecording();
      this.recordingPath = result.path;
      logger.info(`iOS recording started: ${result.path}`);

      // Start audio level polling
      this.startAudioLevelMonitoring();
    } catch (error) {
      this.state = 'error';
      throw error;
    }
  }

  private async stopIOSRecording(): Promise<string> {
    if (!NativeAudioModule) {
      throw new Error('NativeAudioModule not available');
    }

    const result = await NativeAudioModule.stopRecording();
    return result.path;
  }

  // Android Implementation

  private async startAndroidRecording(): Promise<void> {
    const audioStream = getLiveAudioStream();
    if (!audioStream) {
      throw new Error('LiveAudioStream not available on Android');
    }

    this.androidAudioChunks = [];

    audioStream.init({
      sampleRate: this.config.sampleRate,
      channels: this.config.channels,
      bitsPerSample: this.config.bitsPerSample,
      audioSource: 6, // VOICE_RECOGNITION
      bufferSize: 4096,
    });

    audioStream.on('data', (data: string) => {
      this.androidAudioChunks.push(data);

      // Calculate audio level from chunk
      const level = this.calculateAudioLevelFromBase64(data);
      this.currentAudioLevel = level;

      if (this.audioLevelCallback) {
        this.audioLevelCallback(level);
      }

      // Convert to ArrayBuffer and forward to callback
      if (this.audioDataCallback) {
        const buffer = this.base64ToArrayBuffer(data);
        this.audioDataCallback(buffer);
      }
    });

    audioStream.start();
    logger.info('Android recording started');
  }

  private async stopAndroidRecording(): Promise<string> {
    const audioStream = getLiveAudioStream();
    if (audioStream) {
      audioStream.stop();
    }

    // Create WAV file from chunks
    const path = await this.createWavFileFromChunks();
    this.androidAudioChunks = [];
    return path;
  }

  private async createWavFileFromChunks(): Promise<string> {
    // Combine all audio chunks into PCM data
    let totalLength = 0;
    const decodedChunks: Uint8Array[] = [];

    for (const chunk of this.androidAudioChunks) {
      const decoded = Uint8Array.from(atob(chunk), c => c.charCodeAt(0));
      decodedChunks.push(decoded);
      totalLength += decoded.length;
    }

    // Create combined PCM buffer
    const pcmData = new Uint8Array(totalLength);
    let offset = 0;
    for (const chunk of decodedChunks) {
      pcmData.set(chunk, offset);
      offset += chunk.length;
    }

    // Create WAV header
    const wavHeader = this.createWavHeader(totalLength);
    const headerBytes = new Uint8Array(wavHeader);

    // Combine header and PCM data
    const wavData = new Uint8Array(headerBytes.length + pcmData.length);
    wavData.set(headerBytes, 0);
    wavData.set(pcmData, headerBytes.length);

    // Write to file using RNFS
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const RNFS = require('react-native-fs');
      const fileName = `recording_${Date.now()}.wav`;
      const filePath = `${RNFS.CachesDirectoryPath}/${fileName}`;

      const wavBase64 = this.arrayBufferToBase64(wavData.buffer);
      await RNFS.writeFile(filePath, wavBase64, 'base64');

      logger.info(`Android WAV file created: ${filePath}`);
      return filePath;
    } catch (error) {
      logger.error(`Failed to create WAV file: ${error}`);
      throw error;
    }
  }

  // Audio Level Monitoring

  private startAudioLevelMonitoring(): void {
    if (Platform.OS === 'ios' && NativeAudioModule) {
      // Poll audio level from native module
      this.levelUpdateInterval = setInterval(async () => {
        if (this.state !== 'recording') return;

        try {
          const result = await NativeAudioModule.getAudioLevel();
          // Convert linear level (0-1) to normalized (0-1)
          this.currentAudioLevel = result.level;

          if (this.audioLevelCallback) {
            this.audioLevelCallback(this.currentAudioLevel);
          }
        } catch {
          // Ignore errors
        }
      }, 50);
    }
    // Android audio level is calculated inline in the data callback
  }

  private stopAudioLevelMonitoring(): void {
    if (this.levelUpdateInterval) {
      clearInterval(this.levelUpdateInterval);
      this.levelUpdateInterval = null;
    }
    this.currentAudioLevel = 0;
  }

  // Utilities

  private calculateAudioLevelFromBase64(base64Data: string): number {
    try {
      const bytes = Uint8Array.from(atob(base64Data), c => c.charCodeAt(0));
      const samples = new Int16Array(bytes.buffer);

      if (samples.length === 0) return 0;

      let sumSquares = 0;
      for (let i = 0; i < samples.length; i++) {
        const normalized = samples[i]! / 32768.0;
        sumSquares += normalized * normalized;
      }

      const rms = Math.sqrt(sumSquares / samples.length);
      return Math.min(1, rms * 3); // Amplify slightly for visibility
    } catch {
      return 0;
    }
  }

  private base64ToArrayBuffer(base64: string): ArrayBuffer {
    const binaryString = atob(base64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
  }

  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]!);
    }
    return btoa(binary);
  }

  private createWavHeader(dataLength: number): ArrayBuffer {
    const buffer = new ArrayBuffer(44);
    const view = new DataView(buffer);
    const { sampleRate, channels, bitsPerSample } = this.config;
    const byteRate = sampleRate * channels * (bitsPerSample / 8);
    const blockAlign = channels * (bitsPerSample / 8);

    // RIFF header
    this.writeString(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataLength, true);
    this.writeString(view, 8, 'WAVE');

    // fmt chunk
    this.writeString(view, 12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, channels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, bitsPerSample, true);

    // data chunk
    this.writeString(view, 36, 'data');
    view.setUint32(40, dataLength, true);

    return buffer;
  }

  private writeString(view: DataView, offset: number, str: string): void {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  }
}
