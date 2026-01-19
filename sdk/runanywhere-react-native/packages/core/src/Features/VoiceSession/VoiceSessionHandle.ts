/**
 * VoiceSessionHandle.ts
 *
 * High-level voice session API for simplified voice assistant integration.
 * Handles audio capture, VAD, and processing internally.
 *
 * Matches Swift SDK: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceSession.swift
 *
 * Usage:
 * ```typescript
 * // Start a voice session
 * const session = await RunAnywhere.startVoiceSession();
 *
 * // Consume events
 * for await (const event of session.events()) {
 *   switch (event.type) {
 *     case 'listening': updateAudioMeter(event.audioLevel); break;
 *     case 'transcribed': showUserText(event.transcription); break;
 *     case 'responded': showAssistantText(event.response); break;
 *     case 'speaking': showSpeakingIndicator(); break;
 *   }
 * }
 *
 * // Or use callback
 * const session = await RunAnywhere.startVoiceSession({
 *   onEvent: (event) => { ... }
 * });
 * ```
 */

import { EventBus } from '../../Public/Events';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { AudioCaptureManager } from './AudioCaptureManager';
import { AudioPlaybackManager } from './AudioPlaybackManager';
import * as STT from '../../Public/Extensions/RunAnywhere+STT';
import * as TextGeneration from '../../Public/Extensions/RunAnywhere+TextGeneration';
import * as TTS from '../../Public/Extensions/RunAnywhere+TTS';

const logger = new SDKLogger('VoiceSession');

// ============================================================================
// Types
// ============================================================================

/**
 * Voice session configuration
 * Matches Swift: VoiceSessionConfig
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

  /** Language code for STT (default: 'en') */
  language?: string;

  /** System prompt for LLM */
  systemPrompt?: string;

  /** Event callback (alternative to using events() iterator) */
  onEvent?: VoiceSessionEventCallback;
}

/**
 * Default configuration
 */
export const DEFAULT_VOICE_SESSION_CONFIG: Required<Omit<VoiceSessionConfig, 'onEvent'>> = {
  silenceDuration: 1.5,
  speechThreshold: 0.1,
  autoPlayTTS: true,
  continuousMode: true,
  language: 'en',
  systemPrompt: '',
};

/**
 * Voice session event types
 * Matches Swift: VoiceSessionEvent
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
  /** Audio level (for 'listening' events, 0.0 - 1.0) */
  audioLevel?: number;
  /** User's transcribed text (for 'transcribed' and 'turnCompleted' events) */
  transcription?: string;
  /** Assistant's response (for 'responded' and 'turnCompleted' events) */
  response?: string;
  /** TTS audio data (for 'turnCompleted' events) */
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

// ============================================================================
// VoiceSessionHandle
// ============================================================================

/**
 * VoiceSessionHandle
 *
 * Handle to control an active voice session.
 * Manages the full voice interaction loop: listen -> transcribe -> respond -> speak.
 *
 * Matches Swift SDK: VoiceSessionHandle actor
 */
export class VoiceSessionHandle {
  private config: Required<Omit<VoiceSessionConfig, 'onEvent'>>;
  private audioCapture: AudioCaptureManager;
  private audioPlayback: AudioPlaybackManager;
  private eventCallback: VoiceSessionEventCallback | null = null;
  private eventListeners: VoiceSessionEventCallback[] = [];

  private state: VoiceSessionState = 'idle';
  private isSpeechActive = false;
  private lastSpeechTime: number | null = null;
  private vadInterval: ReturnType<typeof setInterval> | null = null;
  private currentAudioLevel = 0;

  constructor(config: VoiceSessionConfig = {}) {
    const { onEvent, ...rest } = config;
    this.config = { ...DEFAULT_VOICE_SESSION_CONFIG, ...rest };
    this.audioCapture = new AudioCaptureManager({ sampleRate: 16000 });
    this.audioPlayback = new AudioPlaybackManager();

    if (onEvent) {
      this.eventCallback = onEvent;
    }
  }

  // ============================================================================
  // Public Properties
  // ============================================================================

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
    return this.currentAudioLevel;
  }

  // ============================================================================
  // Public Methods
  // ============================================================================

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
      // Check if models are loaded
      const sttLoaded = await STT.isSTTModelLoaded();
      const llmLoaded = await TextGeneration.isModelLoaded();
      const ttsLoaded = await TTS.isTTSModelLoaded();

      if (!sttLoaded || !llmLoaded || !ttsLoaded) {
        throw new Error(
          `Voice agent not ready. Models loaded: STT=${sttLoaded}, LLM=${llmLoaded}, TTS=${ttsLoaded}`
        );
      }

      // Request microphone permission
      const hasPermission = await this.audioCapture.requestPermission();
      if (!hasPermission) {
        throw new Error('Microphone permission denied');
      }

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

    // Stop audio
    this.audioCapture.cleanup();
    this.audioPlayback.stop();

    // Clear VAD
    if (this.vadInterval) {
      clearInterval(this.vadInterval);
      this.vadInterval = null;
    }

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
   * Matches Swift's AsyncStream pattern
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

  // ============================================================================
  // Private Methods
  // ============================================================================

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

    // Publish to EventBus for app-wide observation
    // Map event type to EventBus type (note: we avoid spreading 'type' twice)
    const { type, ...eventData } = event;
    const eventBusType = `voiceSession_${type}` as const;

    switch (eventBusType) {
      case 'voiceSession_started':
        EventBus.publish('Voice', { type: 'voiceSession_started' });
        break;
      case 'voiceSession_listening':
        EventBus.publish('Voice', { type: 'voiceSession_listening', audioLevel: eventData.audioLevel });
        break;
      case 'voiceSession_speechStarted':
        EventBus.publish('Voice', { type: 'voiceSession_speechStarted' });
        break;
      case 'voiceSession_speechEnded':
        EventBus.publish('Voice', { type: 'voiceSession_speechEnded' });
        break;
      case 'voiceSession_processing':
        EventBus.publish('Voice', { type: 'voiceSession_processing' });
        break;
      case 'voiceSession_transcribed':
        EventBus.publish('Voice', { type: 'voiceSession_transcribed', transcription: eventData.transcription });
        break;
      case 'voiceSession_responded':
        EventBus.publish('Voice', { type: 'voiceSession_responded', response: eventData.response });
        break;
      case 'voiceSession_speaking':
        EventBus.publish('Voice', { type: 'voiceSession_speaking' });
        break;
      case 'voiceSession_turnCompleted':
        EventBus.publish('Voice', {
          type: 'voiceSession_turnCompleted',
          transcription: eventData.transcription,
          response: eventData.response,
          audio: eventData.audio,
        });
        break;
      case 'voiceSession_stopped':
        EventBus.publish('Voice', { type: 'voiceSession_stopped' });
        break;
      case 'voiceSession_error':
        EventBus.publish('Voice', { type: 'voiceSession_error', error: eventData.error });
        break;
    }
  }

  private async startListening(): Promise<void> {
    this.state = 'listening';
    this.isSpeechActive = false;
    this.lastSpeechTime = null;

    // Set up audio level callback
    this.audioCapture.setAudioLevelCallback((level) => {
      this.currentAudioLevel = level;
      this.emit({ type: 'listening', timestamp: Date.now(), audioLevel: level });
    });

    // Start recording
    await this.audioCapture.startRecording();

    // Start VAD monitoring loop (matches Swift's startAudioLevelMonitoring)
    this.startVADMonitoring();
  }

  /**
   * VAD monitoring loop - runs every 50ms
   * Matches Swift: startAudioLevelMonitoring()
   */
  private startVADMonitoring(): void {
    this.vadInterval = setInterval(() => {
      this.checkSpeechState(this.currentAudioLevel);
    }, 50);
  }

  /**
   * Check speech state based on audio level
   * Matches Swift: checkSpeechState(level:)
   */
  private checkSpeechState(level: number): void {
    if (!this.isRunning || this.state === 'processing' || this.state === 'speaking') {
      return;
    }

    if (level > this.config.speechThreshold) {
      // Speech detected
      if (!this.isSpeechActive) {
        logger.debug('Speech started');
        this.isSpeechActive = true;
        this.emit({ type: 'speechStarted', timestamp: Date.now() });
      }
      this.lastSpeechTime = Date.now();

    } else if (this.isSpeechActive) {
      // Was speaking, now silent - check if silence is long enough
      if (this.lastSpeechTime) {
        const silenceDuration = (Date.now() - this.lastSpeechTime) / 1000;

        if (silenceDuration > this.config.silenceDuration) {
          logger.debug(`Speech ended (silence: ${silenceDuration.toFixed(2)}s)`);
          this.isSpeechActive = false;
          this.emit({ type: 'speechEnded', timestamp: Date.now() });

          // Process the audio
          this.processCurrentAudio();
        }
      }
    }
  }

  /**
   * Process current audio through the pipeline: STT -> LLM -> TTS
   */
  private async processCurrentAudio(): Promise<void> {
    // Stop VAD and recording
    if (this.vadInterval) {
      clearInterval(this.vadInterval);
      this.vadInterval = null;
    }

    this.state = 'processing';
    this.emit({ type: 'processing', timestamp: Date.now() });

    try {
      // Stop recording and get audio file
      const { path: audioPath } = await this.audioCapture.stopRecording();
      logger.info(`Audio recorded: ${audioPath}`);

      // Transcribe using STT
      const sttResult = await STT.transcribeFile(audioPath, {
        language: this.config.language,
      });
      const transcription = sttResult.text?.trim() || '';

      if (!transcription) {
        logger.info('No speech detected in audio');
        if (this.config.continuousMode && this.isRunning) {
          await this.startListening();
        }
        return;
      }

      // Emit transcription
      this.emit({
        type: 'transcribed',
        timestamp: Date.now(),
        transcription,
      });
      logger.info(`Transcribed: "${transcription}"`);

      // Generate response using LLM
      const prompt = this.config.systemPrompt
        ? `${this.config.systemPrompt}\n\nUser: ${transcription}\nAssistant:`
        : transcription;

      const llmResult = await TextGeneration.generate(prompt, {
        maxTokens: 500,
        temperature: 0.7,
      });
      const response = llmResult.text || '';

      // Emit response
      this.emit({
        type: 'responded',
        timestamp: Date.now(),
        response,
      });
      logger.info(`Response: "${response.substring(0, 100)}..."`);

      // Synthesize and play TTS if enabled
      let synthesizedAudio: string | undefined;

      if (this.config.autoPlayTTS && response) {
        this.state = 'speaking';
        this.emit({ type: 'speaking', timestamp: Date.now() });

        try {
          const ttsResult = await TTS.synthesize(response);
          synthesizedAudio = ttsResult.audioData;

          if (synthesizedAudio) {
            await this.audioPlayback.play(synthesizedAudio, ttsResult.sampleRate);
          }
        } catch (ttsError) {
          logger.warning(`TTS failed: ${ttsError}`);
        }
      }

      // Emit complete result
      this.emit({
        type: 'turnCompleted',
        timestamp: Date.now(),
        transcription,
        response,
        audio: synthesizedAudio,
      });

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.state = 'error';
      logger.error(`Processing failed: ${errorMsg}`);
      this.emit({ type: 'error', timestamp: Date.now(), error: errorMsg });
      return; // Don't resume listening on error
    }

    // Resume listening if continuous mode
    if (this.config.continuousMode && this.isRunning) {
      this.state = 'listening';
      await this.startListening();
    }
  }
}
