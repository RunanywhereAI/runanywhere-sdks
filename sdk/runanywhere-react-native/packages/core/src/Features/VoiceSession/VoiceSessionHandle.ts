/**
 * VoiceSessionHandle.ts
 *
 * High-level voice session API for simplified voice assistant integration.
 * Handles audio capture, VAD, and processing internally.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceSession.swift
 */

import { EventBus } from '../../Public/Events';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { AudioCaptureManager } from './AudioCaptureManager';
import { AudioPlaybackManager } from './AudioPlaybackManager';
import * as VoiceAgent from '../../Public/Extensions/RunAnywhere+VoiceAgent';
import type { VoiceTurnResult } from '../../types/VoiceAgentTypes';

const logger = new SDKLogger('VoiceSession');

/**
 * Voice session configuration
 */
export interface VoiceSessionConfig {
  /** Silence duration (seconds) before processing speech (default: 1.5) */
  silenceDuration?: number;

  /** Minimum audio level to detect speech (0.0 - 1.0, default: 0.1) */
  speechThreshold?: number;

  /** Whether to auto-play TTS response (default: true) */
  autoPlayTTS?: boolean;

  /** Whether to auto-resume listening after TTS playback (default: true) */
  continuousMode?: boolean;

  /** Language code (default: 'en') */
  language?: string;

  /** System prompt for LLM */
  systemPrompt?: string;
}

/**
 * Default voice session configuration
 */
export const DEFAULT_VOICE_SESSION_CONFIG: Required<VoiceSessionConfig> = {
  silenceDuration: 1.5,
  speechThreshold: 0.1,
  autoPlayTTS: true,
  continuousMode: true,
  language: 'en',
  systemPrompt: '',
};

/**
 * Voice session event types
 */
export type VoiceSessionEventType =
  | 'started'
  | 'listening'
  | 'speechStarted'
  | 'speechEnded'
  | 'processing'
  | 'transcribed'
  | 'responded'
  | 'speaking'
  | 'turnCompleted'
  | 'stopped'
  | 'error';

/**
 * Voice session event
 */
export interface VoiceSessionEvent {
  type: VoiceSessionEventType;
  timestamp: number;

  /** Audio level (for 'listening' events) */
  audioLevel?: number;

  /** Transcription text (for 'transcribed' events) */
  transcription?: string;

  /** Response text (for 'responded' events) */
  response?: string;

  /** Audio data base64 (for 'turnCompleted' events) */
  audio?: string;

  /** Error message (for 'error' events) */
  error?: string;
}

/**
 * Voice session event callback
 */
export type VoiceSessionEventCallback = (event: VoiceSessionEvent) => void;

/**
 * Voice session state
 */
export type VoiceSessionState =
  | 'idle'
  | 'starting'
  | 'listening'
  | 'processing'
  | 'speaking'
  | 'stopped'
  | 'error';

/**
 * VoiceSessionHandle
 *
 * Handle to control an active voice session.
 * Manages the full voice interaction loop: listen -> transcribe -> respond -> speak.
 */
export class VoiceSessionHandle {
  private config: Required<VoiceSessionConfig>;
  private audioCapture: AudioCaptureManager;
  private audioPlayback: AudioPlaybackManager;
  private eventCallback: VoiceSessionEventCallback | null = null;
  private eventListeners: VoiceSessionEventCallback[] = [];

  private state: VoiceSessionState = 'idle';
  private audioBuffer: ArrayBuffer[] = [];
  private lastSpeechTime: number | null = null;
  private isSpeechActive = false;
  private silenceCheckInterval: ReturnType<typeof setInterval> | null = null;

  constructor(config: VoiceSessionConfig = {}) {
    this.config = { ...DEFAULT_VOICE_SESSION_CONFIG, ...config };
    this.audioCapture = new AudioCaptureManager({ sampleRate: 16000 });
    this.audioPlayback = new AudioPlaybackManager();
  }

  /**
   * Current session state
   */
  get sessionState(): VoiceSessionState {
    return this.state;
  }

  /**
   * Whether the session is running (listening or processing)
   */
  get isRunning(): boolean {
    return this.state !== 'idle' && this.state !== 'stopped' && this.state !== 'error';
  }

  /**
   * Whether audio is currently playing
   */
  get isSpeaking(): boolean {
    return this.audioPlayback.isPlaying;
  }

  /**
   * Current audio level (0.0 - 1.0)
   */
  get audioLevel(): number {
    return this.audioCapture.audioLevel;
  }

  /**
   * Start the voice session
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      logger.warning('Session already running');
      return;
    }

    this.state = 'starting';
    logger.info('Starting voice session...');

    try {
      // Check if voice agent is ready
      const isReady = await VoiceAgent.isVoiceAgentReady();
      if (!isReady) {
        logger.info('Voice agent not ready, attempting to initialize with loaded models...');
        const initialized = await VoiceAgent.initializeVoiceAgentWithLoadedModels();
        if (!initialized) {
          throw new Error('Voice agent not ready. Load STT, LLM, and TTS models first.');
        }
      }

      // Request microphone permission
      const hasPermission = await this.audioCapture.requestPermission();
      if (!hasPermission) {
        throw new Error('Microphone permission denied');
      }

      // Start listening
      this.emit({ type: 'started', timestamp: Date.now() });
      await this.startListening();

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.state = 'error';
      logger.error(`Failed to start session: ${errorMsg}`);
      this.emit({ type: 'error', timestamp: Date.now(), error: errorMsg });
      throw error;
    }
  }

  /**
   * Stop the voice session
   */
  stop(): void {
    if (this.state === 'idle' || this.state === 'stopped') {
      return;
    }

    logger.info('Stopping voice session');
    this.state = 'stopped';

    // Stop audio capture and playback
    this.audioCapture.stopRecording();
    this.audioPlayback.stop();

    // Clear timers
    if (this.silenceCheckInterval) {
      clearInterval(this.silenceCheckInterval);
      this.silenceCheckInterval = null;
    }

    // Clear state
    this.audioBuffer = [];
    this.isSpeechActive = false;
    this.lastSpeechTime = null;

    this.emit({ type: 'stopped', timestamp: Date.now() });
    logger.info('Voice session stopped');
  }

  /**
   * Force process current audio (push-to-talk mode)
   */
  async sendNow(): Promise<void> {
    if (!this.isRunning) {
      logger.warning('Session not running');
      return;
    }

    this.isSpeechActive = false;
    await this.processCurrentAudio();
  }

  /**
   * Add event listener
   */
  addEventListener(callback: VoiceSessionEventCallback): () => void {
    this.eventListeners.push(callback);
    return () => {
      const index = this.eventListeners.indexOf(callback);
      if (index > -1) {
        this.eventListeners.splice(index, 1);
      }
    };
  }

  /**
   * Set single event callback (alternative to addEventListener)
   */
  setEventCallback(callback: VoiceSessionEventCallback | null): void {
    this.eventCallback = callback;
  }

  /**
   * Create async iterator for events
   */
  async *events(): AsyncGenerator<VoiceSessionEvent> {
    const queue: VoiceSessionEvent[] = [];
    let resolver: ((value: VoiceSessionEvent | null) => void) | null = null;
    let done = false;

    const unsubscribe = this.addEventListener((event) => {
      if (event.type === 'stopped' || event.type === 'error') {
        done = true;
      }

      if (resolver) {
        const currentResolver = resolver;
        resolver = null;
        currentResolver(event);
      } else {
        queue.push(event);
      }
    });

    try {
      while (!done) {
        if (queue.length > 0) {
          const event = queue.shift()!;
          yield event;
          if (event.type === 'stopped' || event.type === 'error') {
            break;
          }
        } else {
          const event = await new Promise<VoiceSessionEvent | null>((resolve) => {
            resolver = resolve;
          });
          if (event === null) break;
          yield event;
        }
      }
    } finally {
      unsubscribe();
    }
  }

  /**
   * Cleanup resources
   */
  cleanup(): void {
    this.stop();
    this.audioCapture.cleanup();
    this.audioPlayback.cleanup();
    this.eventListeners = [];
    this.eventCallback = null;
    logger.info('VoiceSessionHandle cleaned up');
  }

  // Private methods

  private emit(event: VoiceSessionEvent): void {
    // Call single callback
    if (this.eventCallback) {
      this.eventCallback(event);
    }

    // Call all listeners
    for (const listener of this.eventListeners) {
      try {
        listener(event);
      } catch (error) {
        logger.error(`Event listener error: ${error}`);
      }
    }

    // Also publish to EventBus
    // Map internal event type to EventBus voice session event type
    switch (event.type) {
      case 'started':
        EventBus.publish('Voice', { type: 'voiceSession_started' });
        break;
      case 'listening':
        EventBus.publish('Voice', { type: 'voiceSession_listening', audioLevel: event.audioLevel });
        break;
      case 'speechStarted':
        EventBus.publish('Voice', { type: 'voiceSession_speechStarted' });
        break;
      case 'speechEnded':
        EventBus.publish('Voice', { type: 'voiceSession_speechEnded' });
        break;
      case 'processing':
        EventBus.publish('Voice', { type: 'voiceSession_processing' });
        break;
      case 'transcribed':
        EventBus.publish('Voice', { type: 'voiceSession_transcribed', transcription: event.transcription });
        break;
      case 'responded':
        EventBus.publish('Voice', { type: 'voiceSession_responded', response: event.response });
        break;
      case 'speaking':
        EventBus.publish('Voice', { type: 'voiceSession_speaking' });
        break;
      case 'turnCompleted':
        EventBus.publish('Voice', {
          type: 'voiceSession_turnCompleted',
          transcription: event.transcription,
          response: event.response,
          audio: event.audio
        });
        break;
      case 'stopped':
        EventBus.publish('Voice', { type: 'voiceSession_stopped' });
        break;
      case 'error':
        EventBus.publish('Voice', { type: 'voiceSession_error', error: event.error });
        break;
    }
  }

  private async startListening(): Promise<void> {
    this.state = 'listening';
    this.audioBuffer = [];
    this.lastSpeechTime = null;
    this.isSpeechActive = false;

    // Set up audio level callback
    this.audioCapture.setAudioLevelCallback((level) => {
      this.emit({ type: 'listening', timestamp: Date.now(), audioLevel: level });
      this.checkSpeechState(level);
    });

    // Start recording
    await this.audioCapture.startRecording((data) => {
      this.handleAudioData(data);
    });

    // Start silence check interval
    this.silenceCheckInterval = setInterval(() => {
      this.checkSilenceTimeout();
    }, 100);
  }

  private handleAudioData(data: ArrayBuffer): void {
    if (!this.isRunning) return;
    this.audioBuffer.push(data);
  }

  private checkSpeechState(level: number): void {
    if (!this.isRunning) return;

    if (level > this.config.speechThreshold) {
      if (!this.isSpeechActive) {
        logger.debug('Speech started');
        this.isSpeechActive = true;
        this.emit({ type: 'speechStarted', timestamp: Date.now() });
      }
      this.lastSpeechTime = Date.now();
    }
  }

  private checkSilenceTimeout(): void {
    if (!this.isRunning || !this.isSpeechActive) return;

    if (this.lastSpeechTime) {
      const silenceDuration = (Date.now() - this.lastSpeechTime) / 1000;

      if (silenceDuration > this.config.silenceDuration) {
        logger.debug('Speech ended (silence detected)');
        this.isSpeechActive = false;
        this.emit({ type: 'speechEnded', timestamp: Date.now() });

        // Only process if we have enough audio (at least 0.5s at 16kHz)
        const totalBytes = this.audioBuffer.reduce((sum, buf) => sum + buf.byteLength, 0);
        if (totalBytes > 16000) {
          this.processCurrentAudio();
        } else {
          this.audioBuffer = [];
        }
      }
    }
  }

  private async processCurrentAudio(): Promise<void> {
    // Gather audio data
    const totalLength = this.audioBuffer.reduce((acc, buf) => acc + buf.byteLength, 0);
    const audioData = new ArrayBuffer(totalLength);
    const view = new Uint8Array(audioData);
    let offset = 0;
    for (const buffer of this.audioBuffer) {
      view.set(new Uint8Array(buffer), offset);
      offset += buffer.byteLength;
    }

    this.audioBuffer = [];

    if (totalLength === 0) return;

    // Stop listening during processing
    this.audioCapture.stopRecording();
    if (this.silenceCheckInterval) {
      clearInterval(this.silenceCheckInterval);
      this.silenceCheckInterval = null;
    }

    this.state = 'processing';
    this.emit({ type: 'processing', timestamp: Date.now() });

    try {
      // Process the voice turn
      const result = await VoiceAgent.processVoiceTurn(audioData);

      if (!result.speechDetected) {
        logger.info('No speech detected');
        if (this.config.continuousMode && this.isRunning) {
          await this.startListening();
        }
        return;
      }

      // Emit transcription
      if (result.transcription) {
        this.emit({
          type: 'transcribed',
          timestamp: Date.now(),
          transcription: result.transcription
        });
      }

      // Emit response
      if (result.response) {
        this.emit({
          type: 'responded',
          timestamp: Date.now(),
          response: result.response
        });
      }

      // Play TTS if enabled
      if (this.config.autoPlayTTS && result.synthesizedAudio) {
        this.state = 'speaking';
        this.emit({ type: 'speaking', timestamp: Date.now() });
        await this.audioPlayback.play(result.synthesizedAudio);
      }

      // Emit complete result
      this.emit({
        type: 'turnCompleted',
        timestamp: Date.now(),
        transcription: result.transcription,
        response: result.response,
        audio: result.synthesizedAudio,
      });

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(`Processing failed: ${errorMsg}`);
      this.emit({ type: 'error', timestamp: Date.now(), error: errorMsg });
    }

    // Resume listening if continuous mode
    if (this.config.continuousMode && this.isRunning) {
      this.state = 'listening';
      await this.startListening();
    }
  }
}
