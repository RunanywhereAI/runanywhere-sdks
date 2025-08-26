/**
 * TTS Adapter Implementation
 * Provides a unified interface for TTS services using Web Speech API
 */

import {
  BaseAdapter,
  type AdapterType,
  Result,
  logger,
  ServiceRegistry
} from '@runanywhere/core';
import { TTSService } from '../services/tts-service';
import type {
  TTSConfig,
  TTSOptions,
  SynthesisResult,
  VoiceInfo,
  TTSEvents
} from '../types';

export interface TTSAdapterConfig extends TTSConfig {
  // Extended config for TTS Adapter
  autoPlay?: boolean;
  maxRetries?: number;
  retryDelay?: number;
}

export class TTSAdapter extends BaseAdapter<TTSEvents> {
  readonly id = 'web-speech-tts';
  readonly name = 'Web Speech TTS';
  readonly version = '1.0.0';

  private ttsService?: TTSService;
  private config: TTSAdapterConfig;
  private isInitialized = false;

  constructor(config: TTSAdapterConfig = {}) {
    super();
    this.config = {
      engine: 'web-speech',
      voice: 'default',
      rate: 1.0,
      pitch: 1.0,
      volume: 1.0,
      language: 'en-US',
      autoPlay: true,
      maxRetries: 3,
      retryDelay: 1000,
      ...config
    };
  }

  async initialize(config?: TTSAdapterConfig): Promise<Result<void, Error>> {
    if (this.isInitialized) {
      return Result.ok(undefined);
    }

    try {
      logger.info('Initializing TTS Adapter', 'TTSAdapter');

      // Merge config
      if (config) {
        this.config = { ...this.config, ...config };
      }

      // Create TTS service
      this.ttsService = new TTSService(this.config);

      // Set up event forwarding
      this.setupEventForwarding();

      // Initialize the service
      const result = await this.ttsService.initialize();
      if (!result.success) {
        throw result.error;
      }

      this.isInitialized = true;
      logger.info('TTS Adapter initialized successfully', 'TTSAdapter');
      return Result.ok(undefined);

    } catch (error) {
      logger.error('Failed to initialize TTS Adapter', 'TTSAdapter', { error });
      return Result.err(error as Error);
    }
  }

  private setupEventForwarding(): void {
    if (!this.ttsService) return;

    // Forward all events from TTS service to adapter listeners
    this.ttsService.on('ready', () => this.emit('ready'));
    this.ttsService.on('loading', () => this.emit('loading'));
    this.ttsService.on('error', (error) => this.emit('error', error));
    this.ttsService.on('synthesisStart', (data) => this.emit('synthesisStart', data));
    this.ttsService.on('synthesisProgress', (progress) => this.emit('synthesisProgress', progress));
    this.ttsService.on('synthesisChunk', (chunk) => this.emit('synthesisChunk', chunk));
    this.ttsService.on('synthesisComplete', (result) => this.emit('synthesisComplete', result));
    this.ttsService.on('playbackStart', () => this.emit('playbackStart'));
    this.ttsService.on('playbackEnd', () => this.emit('playbackEnd'));
    this.ttsService.on('voicesChanged', (voices) => this.emit('voicesChanged', voices));
  }

  async synthesize(text: string, options?: TTSOptions): Promise<Result<SynthesisResult, Error>> {
    if (!this.isInitialized || !this.ttsService) {
      const initResult = await this.initialize();
      if (!initResult.success) {
        return Result.err(initResult.error);
      }
    }

    if (!text.trim()) {
      return Result.err(new Error('Text cannot be empty'));
    }

    try {
      logger.debug('Synthesizing text', 'TTSAdapter', { textLength: text.length });

      const result = await this.ttsService!.synthesize(text, options);

      if (result.success && this.config.autoPlay) {
        // Auto-play the synthesized audio
        await this.ttsService!.play(result.value.audioBuffer);
      }

      return result;
    } catch (error) {
      logger.error('Synthesis failed', 'TTSAdapter', { error });
      return Result.err(error as Error);
    }
  }

  async speak(text: string, options?: TTSOptions): Promise<Result<void, Error>> {
    const result = await this.synthesize(text, options);
    if (!result.success) {
      return Result.err(result.error);
    }

    if (!this.config.autoPlay) {
      // If auto-play is disabled, manually play the audio
      try {
        await this.ttsService!.play(result.value.audioBuffer);
        return Result.ok(undefined);
      } catch (error) {
        return Result.err(error as Error);
      }
    }

    return Result.ok(undefined);
  }

  getAvailableVoices(): VoiceInfo[] {
    if (!this.ttsService) {
      return [];
    }
    return this.ttsService.getAvailableVoices();
  }

  getPreferredVoice(language?: string): VoiceInfo | null {
    if (!this.ttsService) {
      return null;
    }
    return this.ttsService.getPreferredVoice(language);
  }

  cancel(): void {
    if (this.ttsService) {
      this.ttsService.cancel();
      logger.debug('TTS cancelled', 'TTSAdapter');
    }
  }

  pause(): void {
    if (this.ttsService) {
      this.ttsService.pause();
      logger.debug('TTS paused', 'TTSAdapter');
    }
  }

  resume(): void {
    if (this.ttsService) {
      this.ttsService.resume();
      logger.debug('TTS resumed', 'TTSAdapter');
    }
  }

  setVoice(voiceName: string): void {
    if (this.ttsService) {
      const voices = this.ttsService.getAvailableVoices();
      const voice = voices.find(v => v.name === voiceName);
      if (voice) {
        this.config.voice = voiceName;
        logger.debug('Voice changed', 'TTSAdapter', { voice: voiceName });
      }
    }
  }

  setRate(rate: number): void {
    this.config.rate = Math.max(0.1, Math.min(10, rate));
    logger.debug('Rate changed', 'TTSAdapter', { rate: this.config.rate });
  }

  setPitch(pitch: number): void {
    this.config.pitch = Math.max(0, Math.min(2, pitch));
    logger.debug('Pitch changed', 'TTSAdapter', { pitch: this.config.pitch });
  }

  setVolume(volume: number): void {
    this.config.volume = Math.max(0, Math.min(1, volume));
    logger.debug('Volume changed', 'TTSAdapter', { volume: this.config.volume });
  }

  isHealthy(): boolean {
    return this.isInitialized && this.ttsService?.isHealthy() === true;
  }

  destroy(): void {
    if (this.ttsService) {
      this.ttsService.destroy();
      this.ttsService = undefined;
    }
    this.isInitialized = false;
    this.emitter.removeAllListeners();
    logger.info('TTS Adapter destroyed', 'TTSAdapter');
  }
}

// Auto-register with ServiceRegistry if available
if (typeof window !== 'undefined') {
  try {
    const registry = ServiceRegistry.getInstance();
    registry.register('TTS' as AdapterType, 'web-speech-tts', TTSAdapter as any);
    logger.info('TTS adapter auto-registered', 'TTSAdapter');
  } catch (error) {
    // ServiceRegistry not available, skip auto-registration
    logger.debug('ServiceRegistry not available for auto-registration', 'TTSAdapter');
  }
}

// Named exports
export { TTSAdapter as default };
export const adapter = TTSAdapter;
