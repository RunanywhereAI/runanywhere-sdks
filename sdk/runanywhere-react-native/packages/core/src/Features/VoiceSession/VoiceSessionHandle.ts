/**
 * VoiceSessionHandle.ts
 * RunAnywhere SDK
 *
 * Handle to control an active voice session.
 * Matches iOS: Public/Extensions/RunAnywhere+VoiceSession.swift
 *
 * Note: In React Native, actual audio capture must be handled by the app
 * using external packages like react-native-live-audio-stream.
 * This class provides the session control interface and event streaming.
 */

import type { VoiceSessionEvent } from './VoiceSessionEvent';
import { VoiceSessionEventFactory } from './VoiceSessionEvent';
import type { VoiceSessionConfig } from './VoiceSessionConfig';
import { DEFAULT_VOICE_SESSION_CONFIG } from './VoiceSessionConfig';
import { VoiceSessionError } from './VoiceSessionError';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

/**
 * Listener for voice session events
 */
export type VoiceSessionEventListener = (event: VoiceSessionEvent) => void;

/**
 * Handle to control an active voice session.
 *
 * In React Native, audio capture is the app's responsibility.
 * Use this handle to:
 * - Feed audio data from external capture
 * - Receive session events
 * - Control session lifecycle (stop, sendNow)
 *
 * @example
 * ```typescript
 * const session = await RunAnywhere.startVoiceSession();
 *
 * // Subscribe to events
 * const unsubscribe = session.onEvent((event) => {
 *   switch (event.type) {
 *     case 'listening':
 *       updateAudioMeter(event.audioLevel);
 *       break;
 *     case 'turnCompleted':
 *       showResult(event.transcript, event.response);
 *       break;
 *   }
 * });
 *
 * // Feed audio from external capture
 * audioCapture.onData((data) => session.feedAudio(data));
 *
 * // Stop when done
 * await session.stop();
 * unsubscribe();
 * ```
 */
export class VoiceSessionHandle {
  private readonly logger = new SDKLogger('VoiceSession');
  private readonly config: VoiceSessionConfig;
  private listeners: Set<VoiceSessionEventListener> = new Set();

  private _isRunning = false;
  private audioBuffer: ArrayBuffer[] = [];
  private lastSpeechTime: number | null = null;
  private isSpeechActive = false;

  /**
   * Whether the session is currently running
   */
  get isRunning(): boolean {
    return this._isRunning;
  }

  constructor(config: Partial<VoiceSessionConfig> = {}) {
    this.config = { ...DEFAULT_VOICE_SESSION_CONFIG, ...config };
  }

  /**
   * Start the voice session
   * @internal Called by RunAnywhere.startVoiceSession()
   */
  async start(): Promise<void> {
    if (this._isRunning) {
      throw VoiceSessionError.alreadyRunning();
    }

    this._isRunning = true;
    this.audioBuffer = [];
    this.lastSpeechTime = null;
    this.isSpeechActive = false;

    this.emit(VoiceSessionEventFactory.started());
    this.logger.debug('Voice session started');
  }

  /**
   * Stop the voice session
   */
  async stop(): Promise<void> {
    if (!this._isRunning) {
      return;
    }

    this._isRunning = false;
    this.audioBuffer = [];
    this.lastSpeechTime = null;
    this.isSpeechActive = false;

    this.emit(VoiceSessionEventFactory.stopped());
    this.logger.debug('Voice session stopped');
  }

  /**
   * Force process current audio immediately (push-to-talk mode)
   * This triggers processing of any accumulated audio without waiting for silence detection
   */
  async sendNow(): Promise<void> {
    if (!this._isRunning) {
      throw VoiceSessionError.notStarted();
    }

    this.isSpeechActive = false;
    await this.processAccumulatedAudio();
  }

  /**
   * Feed audio data from external capture
   *
   * @param audioData - PCM audio data (16kHz, mono, 16-bit recommended)
   * @param audioLevel - Optional audio level (0.0 - 1.0) for speech detection
   */
  feedAudio(audioData: ArrayBuffer, audioLevel?: number): void {
    if (!this._isRunning) {
      return;
    }

    this.audioBuffer.push(audioData);

    // Handle audio level for speech detection
    if (audioLevel !== undefined) {
      this.handleAudioLevel(audioLevel);
    }
  }

  /**
   * Update audio level for UI feedback and speech detection
   * Call this periodically with the current audio level if not using feedAudio's audioLevel parameter
   *
   * @param level - Audio level (0.0 - 1.0)
   */
  updateAudioLevel(level: number): void {
    if (!this._isRunning) {
      return;
    }

    this.emit(VoiceSessionEventFactory.listening(level));
    this.handleAudioLevel(level);
  }

  /**
   * Subscribe to voice session events
   *
   * @param listener - Callback for events
   * @returns Unsubscribe function
   */
  onEvent(listener: VoiceSessionEventListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /**
   * Get the current configuration
   */
  getConfig(): Readonly<VoiceSessionConfig> {
    return this.config;
  }

  // MARK: - Private Methods

  private emit(event: VoiceSessionEvent): void {
    this.listeners.forEach((listener) => {
      try {
        listener(event);
      } catch (error) {
        this.logger.error(`Event listener error: ${error}`);
      }
    });
  }

  private handleAudioLevel(level: number): void {
    const now = Date.now();

    if (level > this.config.speechThreshold) {
      if (!this.isSpeechActive) {
        this.logger.debug('Speech started');
        this.isSpeechActive = true;
        this.emit(VoiceSessionEventFactory.speechStarted());
      }
      this.lastSpeechTime = now;
    } else if (this.isSpeechActive && this.lastSpeechTime !== null) {
      const silenceDuration = (now - this.lastSpeechTime) / 1000;

      if (silenceDuration > this.config.silenceDuration) {
        this.logger.debug('Speech ended, processing...');
        this.isSpeechActive = false;
        this.processAccumulatedAudio().catch((error) => {
          this.logger.error(`Processing error: ${error}`);
          this.emit(VoiceSessionEventFactory.error(String(error)));
        });
      }
    }
  }

  private async processAccumulatedAudio(): Promise<void> {
    if (this.audioBuffer.length === 0) {
      return;
    }

    // Combine audio buffers
    const totalLength = this.audioBuffer.reduce(
      (acc, buf) => acc + buf.byteLength,
      0
    );

    // Minimum audio length check (~0.5s at 16kHz, 16-bit = 16000 bytes)
    if (totalLength < 16000) {
      this.logger.debug('Audio too short, discarding');
      this.audioBuffer = [];
      return;
    }

    const combinedAudio = new ArrayBuffer(totalLength);
    const view = new Uint8Array(combinedAudio);
    let offset = 0;
    for (const buffer of this.audioBuffer) {
      view.set(new Uint8Array(buffer), offset);
      offset += buffer.byteLength;
    }

    this.audioBuffer = [];
    this.emit(VoiceSessionEventFactory.processing());

    try {
      // Use dynamic import to avoid circular dependency
      const { RunAnywhere } = await import('../../Public/RunAnywhere');
      const result = await RunAnywhere.processVoiceTurn(combinedAudio);

      if (!result.speechDetected) {
        this.logger.info('No speech detected in audio');
        // Resume listening in continuous mode
        if (this.config.continuousMode && this._isRunning) {
          this.lastSpeechTime = null;
        }
        return;
      }

      // Emit transcription event
      if (result.transcription) {
        this.emit(VoiceSessionEventFactory.transcribed(result.transcription));
      }

      // Emit response event
      if (result.response) {
        this.emit(VoiceSessionEventFactory.responded(result.response));
      }

      // Handle TTS playback if enabled and audio available
      if (this.config.autoPlayTTS && result.synthesizedAudio) {
        this.emit(VoiceSessionEventFactory.speaking());
        // Note: Actual audio playback should be handled by the app
        // The synthesizedAudio is included in the turnCompleted event
        this.logger.info(
          'TTS audio available - app should handle playback via turnCompleted event'
        );
      }

      // Emit complete turn result
      this.emit(
        VoiceSessionEventFactory.turnCompleted(
          result.transcription || '',
          result.response || '',
          result.synthesizedAudio
            ? new Uint8Array(result.synthesizedAudio).buffer
            : undefined
        )
      );
    } catch (error) {
      this.logger.error(`Voice processing failed: ${error}`);
      this.emit(VoiceSessionEventFactory.error(String(error)));
    }

    // Resume listening in continuous mode
    if (this.config.continuousMode && this._isRunning) {
      this.lastSpeechTime = null;
    }
  }
}
