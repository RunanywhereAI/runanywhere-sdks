import { MicVAD } from '@ricky0123/vad-web';
import { EventEmitter } from 'eventemitter3';
import { logger, AudioError } from '@runanywhere/core';
import type { VADConfig, VADEvent, VADService, VADMetrics } from './types';
import { DEFAULT_VAD_CONFIG } from './types';

/**
 * Modern Web VAD Service implementation
 * Uses @ricky0123/vad-web with Web Audio API
 */
export class WebVADService extends EventEmitter implements VADService {
  private vad: MicVAD | null = null;
  private config: VADConfig;
  private isRunning = false;
  private isPaused = false;
  private metrics: VADMetrics = {
    totalSpeechSegments: 0,
    totalSpeechDuration: 0,
    averageEnergy: 0,
    lastActivityTime: 0
  };
  private energySamples: number[] = [];
  private speechStartTime: number | null = null;

  constructor() {
    super();
    this.config = DEFAULT_VAD_CONFIG;
  }

  async initialize(config: Partial<VADConfig> = {}): Promise<void> {
    this.config = { ...DEFAULT_VAD_CONFIG, ...config };

    logger.info('Initializing VAD service', 'VAD', { config: this.config });

    try {
      // Check for browser compatibility
      if (!this.checkBrowserSupport()) {
        throw new AudioError('Browser does not support required audio APIs');
      }

      // Load VAD model with modern configuration
      this.vad = await MicVAD.new({
        positiveSpeechThreshold: this.config.positiveSpeechThreshold,
        negativeSpeechThreshold: this.config.negativeSpeechThreshold,
        preSpeechPadFrames: this.config.preSpeechPadFrames,
        minSpeechFrames: this.config.minSpeechFrames,
        submitUserSpeechOnPause: this.config.submitUserSpeechOnPause,
        frameSamples: this.config.frameSamples,

        onSpeechStart: () => {
          this.handleSpeechStart();
        },

        onSpeechEnd: (audio: Float32Array) => {
          this.handleSpeechEnd(audio);
        },

        onVADMisfire: () => {
          logger.warn('VAD misfire detected', 'VAD');
          this.emit('vad:misfire');
        }
      });

      // Set up audio level monitoring
      this.setupAudioLevelMonitoring();

      logger.info('VAD service initialized successfully', 'VAD');
      this.emit('initialized');

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('Failed to initialize VAD', 'VAD', { error: errorMessage });
      throw new AudioError(`VAD initialization failed: ${errorMessage}`);
    }
  }

  private checkBrowserSupport(): boolean {
    if (typeof window === 'undefined') {
      logger.warn('Not in browser environment', 'VAD');
      return false;
    }

    const hasGetUserMedia = !!(
      navigator.mediaDevices &&
      navigator.mediaDevices.getUserMedia
    );

    const hasAudioContext = !!(
      window.AudioContext ||
      (window as any).webkitAudioContext
    );

    if (!hasGetUserMedia) {
      logger.error('getUserMedia not supported', 'VAD');
    }

    if (!hasAudioContext) {
      logger.error('AudioContext not supported', 'VAD');
    }

    return hasGetUserMedia && hasAudioContext;
  }

  private handleSpeechStart(): void {
    this.speechStartTime = Date.now();
    this.metrics.lastActivityTime = this.speechStartTime;

    logger.debug('Speech started', 'VAD');
    this.emit('speech_start');

    const event: VADEvent = {
      type: 'speech_start',
      timestamp: this.speechStartTime
    };
    this.emit('vad:event', event);
  }

  private handleSpeechEnd(audio: Float32Array): void {
    const endTime = Date.now();
    const duration = this.speechStartTime ? (endTime - this.speechStartTime) / 1000 : 0;

    // Update metrics
    this.metrics.totalSpeechSegments++;
    this.metrics.totalSpeechDuration += duration;
    this.metrics.lastActivityTime = endTime;

    // Calculate energy
    const energy = this.calculateEnergy(audio);
    this.updateAverageEnergy(energy);

    logger.debug('Speech ended', 'VAD', {
      duration: `${duration.toFixed(2)}s`,
      samples: audio.length,
      energy: energy.toFixed(3)
    });

    this.emit('speech_end', audio);

    const event: VADEvent = {
      type: 'speech_end',
      timestamp: endTime,
      data: audio,
      energy,
      duration
    };
    this.emit('vad:event', event);

    this.speechStartTime = null;
  }

  private setupAudioLevelMonitoring(): void {
    if (!this.vad) return;

    // Monitor audio levels at 10Hz
    const monitorInterval = setInterval(() => {
      if (!this.isRunning || this.isPaused) {
        return;
      }

      // Get current audio level (simplified - would need actual implementation)
      const level = this.getCurrentAudioLevel();
      this.emit('audio_level', level);

      const event: VADEvent = {
        type: 'audio_level',
        timestamp: Date.now(),
        energy: level
      };
      this.emit('vad:event', event);
    }, 100);

    // Clean up on destroy
    this.once('destroy', () => clearInterval(monitorInterval));
  }

  private getCurrentAudioLevel(): number {
    // Simplified - actual implementation would analyze audio stream
    return Math.random() * 0.1; // Placeholder
  }

  async start(): Promise<void> {
    if (!this.vad) {
      throw new AudioError('VAD not initialized. Call initialize() first.');
    }

    if (this.isRunning) {
      logger.warn('VAD already running', 'VAD');
      return;
    }

    logger.info('Starting VAD', 'VAD');

    try {
      await this.vad.start();
      this.isRunning = true;
      this.isPaused = false;
      this.emit('started');
      logger.info('VAD started successfully', 'VAD');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('Failed to start VAD', 'VAD', { error: errorMessage });
      throw new AudioError(`Failed to start VAD: ${errorMessage}`);
    }
  }

  stop(): void {
    if (!this.vad || !this.isRunning) {
      return;
    }

    logger.info('Stopping VAD', 'VAD');
    this.vad.pause();
    this.isRunning = false;
    this.isPaused = false;
    this.emit('stopped');
    logger.info('VAD stopped', 'VAD');
  }

  pause(): void {
    if (!this.vad || !this.isRunning || this.isPaused) {
      return;
    }

    logger.debug('Pausing VAD', 'VAD');
    this.vad.pause();
    this.isPaused = true;
    this.emit('paused');
  }

  resume(): void {
    if (!this.vad || !this.isRunning || !this.isPaused) {
      return;
    }

    logger.debug('Resuming VAD', 'VAD');
    this.vad.start();
    this.isPaused = false;
    this.emit('resumed');
  }

  async process(audio: Float32Array): Promise<VADEvent | null> {
    // Manual processing mode for pre-recorded audio
    const energy = this.calculateEnergy(audio);
    const timestamp = Date.now();

    // Simple voice detection based on energy threshold
    const isVoice = energy > 0.01; // Simplified threshold

    if (isVoice) {
      this.metrics.lastActivityTime = timestamp;
      this.updateAverageEnergy(energy);

      return {
        type: 'speech_segment',
        timestamp,
        data: audio,
        energy
      };
    }

    return null;
  }

  private calculateEnergy(audio: Float32Array): number {
    let sum = 0;
    for (let i = 0; i < audio.length; i++) {
      const sample = audio[i] ?? 0;
      sum += sample * sample;
    }
    return Math.sqrt(sum / audio.length);
  }

  private updateAverageEnergy(energy: number): void {
    this.energySamples.push(energy);

    // Keep only last 100 samples for moving average
    if (this.energySamples.length > 100) {
      this.energySamples.shift();
    }

    const sum = this.energySamples.reduce((a, b) => a + b, 0);
    this.metrics.averageEnergy = sum / this.energySamples.length;
  }

  onSpeechStart(callback: () => void): void {
    this.on('speech_start', callback);
  }

  onSpeechEnd(callback: (audio: Float32Array) => void): void {
    this.on('speech_end', callback);
  }

  onAudioLevel(callback: (level: number) => void): void {
    this.on('audio_level', callback);
  }

  getMetrics(): VADMetrics {
    return { ...this.metrics };
  }

  isHealthy(): boolean {
    return this.isRunning && !this.isPaused && this.vad !== null;
  }

  destroy(): void {
    logger.info('Destroying VAD service', 'VAD');

    this.stop();

    if (this.vad) {
      this.vad.destroy();
      this.vad = null;
    }

    this.energySamples = [];
    this.metrics = {
      totalSpeechSegments: 0,
      totalSpeechDuration: 0,
      averageEnergy: 0,
      lastActivityTime: 0
    };

    this.emit('destroy');
    this.removeAllListeners();

    logger.info('VAD service destroyed', 'VAD');
  }
}

/**
 * Service token for DI container
 */
export const VAD_SERVICE_TOKEN = Symbol.for('VADService');
