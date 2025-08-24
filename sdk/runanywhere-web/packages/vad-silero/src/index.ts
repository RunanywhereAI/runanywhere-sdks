/**
 * Silero VAD Adapter Implementation
 * Wraps @ricky0123/vad-web for voice activity detection
 */

import type { MicVAD } from '@ricky0123/vad-web';
import {
  BaseAdapter,
  type VADAdapter,
  type VADEvents,
  type VADConfig,
  type VADMetrics,
  type AdapterType,
  Result,
  logger,
  ServiceRegistry
} from '@runanywhere/core';

export class SileroVADAdapter extends BaseAdapter<VADEvents> implements VADAdapter {
  readonly id = 'silero';
  readonly name = 'Silero VAD';
  readonly version = '1.0.0';

  private vad?: MicVAD;
  private isRunning = false;
  private isPaused = false;
  private metrics: VADMetrics = {
    totalDetections: 0,
    avgSpeechDuration: 0,
    lastDetectionTime: undefined,
    noiseLevel: 0,
    totalSpeechSegments: 0,
    totalSilenceMs: 0,
    totalSpeechMs: 0,
    lastActivityTime: null,
  };
  private lastActivityStart = 0;

  async initialize(config?: VADConfig): Promise<Result<void, Error>> {
    try {
      // Dynamically import to avoid bundling if not used
      const vadModule = await import('@ricky0123/vad-web');

      this.vad = await vadModule.MicVAD.new({
        positiveSpeechThreshold: config?.positiveSpeechThreshold ?? 0.9,
        negativeSpeechThreshold: config?.negativeSpeechThreshold ?? 0.75,
        minSpeechFrames: config?.minSpeechDuration ? Math.floor(config.minSpeechDuration / 32) : 3,
        preSpeechPadFrames: config?.preSpeechPadding ? Math.floor(config.preSpeechPadding / 32) : 10,

        onSpeechStart: () => {
          if (!this.isPaused) {
            this.lastActivityStart = Date.now();
            this.emit('speech_start');
          }
        },

        onSpeechEnd: (audio: Float32Array) => {
          if (!this.isPaused) {
            const duration = Date.now() - this.lastActivityStart;
            this.updateMetrics(duration);
            this.emit('speech_end', audio);
          }
        },

        onVADMisfire: () => {
          this.emit('vad_misfire');
        },
      });

      logger.info(`Silero VAD initialized successfully`, 'SileroVADAdapter');
      return Result.ok(undefined);
    } catch (error) {
      logger.error('Failed to initialize Silero VAD', 'SileroVADAdapter', { error });
      return Result.err(error as Error);
    }
  }

  async start(): Promise<Result<void, Error>> {
    if (!this.vad) {
      return Result.err(new Error('VAD not initialized'));
    }

    if (this.isRunning) {
      return Result.ok(undefined);
    }

    try {
      await this.vad.start();
      this.isRunning = true;
      this.isPaused = false;
      logger.info('Silero VAD started', 'SileroVADAdapter');
      return Result.ok(undefined);
    } catch (error) {
      logger.error('Failed to start VAD', 'SileroVADAdapter', { error });
      return Result.err(error as Error);
    }
  }

  stop(): void {
    if (!this.vad || !this.isRunning) {
      return;
    }

    try {
      this.vad.pause();
      this.isRunning = false;
      this.isPaused = false;
      logger.info('Silero VAD stopped', 'SileroVADAdapter');
    } catch (error) {
      logger.error('Failed to stop VAD', 'SileroVADAdapter', { error });
    }
  }

  pause(): void {
    if (this.vad && this.isRunning) {
      this.vad.pause();
      this.isPaused = true;
      logger.debug('VAD paused', 'SileroVADAdapter');
    }
  }

  resume(): void {
    if (this.vad && this.isRunning && this.isPaused) {
      this.vad.start();
      this.isPaused = false;
      logger.debug('VAD resumed', 'SileroVADAdapter');
    }
  }

  private updateMetrics(speechDuration: number): void {
    this.metrics.totalDetections++;
    this.metrics.totalSpeechSegments++;
    this.metrics.totalSpeechMs += speechDuration;
    this.metrics.lastDetectionTime = Date.now();
    this.metrics.lastActivityTime = Date.now();

    // Update average speech duration
    this.metrics.avgSpeechDuration =
      this.metrics.totalSpeechMs / this.metrics.totalSpeechSegments;
  }

  getMetrics(): VADMetrics {
    return { ...this.metrics };
  }

  isHealthy(): boolean {
    return this.vad !== undefined && this.isRunning;
  }

  destroy(): void {
    if (this.vad) {
      this.vad.destroy();
      this.vad = undefined;
    }
    this.isRunning = false;
    this.isPaused = false;
    this.emitter.removeAllListeners();
    logger.info('Silero VAD destroyed', 'SileroVADAdapter');
  }
}

// Auto-register with ServiceRegistry if available
if (typeof window !== 'undefined') {
  try {
    const registry = ServiceRegistry.getInstance();
    registry.register('VAD' as AdapterType, 'silero', SileroVADAdapter as any);
    logger.info('Silero VAD adapter auto-registered', 'SileroVADAdapter');
  } catch (error) {
    // ServiceRegistry not available, skip auto-registration
    logger.debug('ServiceRegistry not available for auto-registration', 'SileroVADAdapter');
  }
}

// Named exports
export { SileroVADAdapter as default };
export const adapter = SileroVADAdapter;
