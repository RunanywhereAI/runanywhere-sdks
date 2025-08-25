/**
 * Silero VAD Adapter Implementation
 * Uses @ricky0123/vad-web library directly
 */

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

// Import the actual VAD library
import { MicVAD, type RealTimeVADOptions } from '@ricky0123/vad-web';

export interface SileroVADConfig extends VADConfig {
  // Extended config for Silero VAD
  model?: 'v5' | 'legacy';
  baseAssetPath?: string;
  onnxWASMBasePath?: string;
}

export class SileroVADAdapter extends BaseAdapter<VADEvents> implements VADAdapter {
  readonly id = 'silero';
  readonly name = 'Silero VAD';
  readonly version = '1.0.0';

  private micVAD?: MicVAD;
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

  async initialize(config?: SileroVADConfig): Promise<Result<void, Error>> {
    try {
      logger.info('Initializing Silero VAD with @ricky0123/vad-web', 'SileroVADAdapter');

      // Configure VAD options
      const vadOptions: Partial<RealTimeVADOptions> = {
        positiveSpeechThreshold: config?.positiveSpeechThreshold ?? 0.9,
        negativeSpeechThreshold: config?.negativeSpeechThreshold ?? 0.75,
        minSpeechFrames: config?.minSpeechDuration ? Math.floor(config.minSpeechDuration / 32) : 3,
        preSpeechPadFrames: config?.preSpeechPadding ? Math.floor(config.preSpeechPadding / 32) : 10,
        model: config?.model ?? 'v5',

        // Use CDN for assets if not specified
        baseAssetPath: config?.baseAssetPath ?? 'https://cdn.jsdelivr.net/npm/@ricky0123/vad-web@0.0.24/dist/',
        onnxWASMBasePath: config?.onnxWASMBasePath ?? 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.14.0/dist/',

        // Set up callbacks
        onSpeechStart: () => {
          if (!this.isPaused) {
            this.lastActivityStart = Date.now();
            logger.debug('Speech started', 'SileroVADAdapter');
            this.emit('speech_start');
          }
        },

        onSpeechEnd: (audio: Float32Array) => {
          if (!this.isPaused) {
            const duration = Date.now() - this.lastActivityStart;
            this.updateMetrics(duration);
            logger.debug('Speech ended', 'SileroVADAdapter', { audioLength: audio.length });
            this.emit('speech_end', audio);
          }
        },

        onVADMisfire: () => {
          logger.debug('VAD misfire', 'SileroVADAdapter');
          this.emit('vad_misfire');
        },

        onFrameProcessed: (probabilities) => {
          // Can emit frame probabilities if needed
          // logger.trace('Frame processed', 'SileroVADAdapter', { probabilities });
        }
      };

      // Create MicVAD instance
      this.micVAD = await MicVAD.new(vadOptions);

      logger.info('Silero VAD initialized successfully', 'SileroVADAdapter');
      return Result.ok(undefined);

    } catch (error) {
      logger.error('Failed to initialize Silero VAD', 'SileroVADAdapter', { error });
      return Result.err(error as Error);
    }
  }

  async start(): Promise<Result<void, Error>> {
    if (!this.micVAD) {
      return Result.err(new Error('VAD not initialized'));
    }

    if (this.isRunning) {
      return Result.ok(undefined);
    }

    try {
      this.micVAD.start();
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
    if (!this.micVAD || !this.isRunning) {
      return;
    }

    try {
      this.micVAD.pause();
      this.isRunning = false;
      this.isPaused = false;
      logger.info('Silero VAD stopped', 'SileroVADAdapter');
    } catch (error) {
      logger.error('Failed to stop VAD', 'SileroVADAdapter', { error });
    }
  }

  pause(): void {
    if (this.micVAD && this.isRunning) {
      this.micVAD.pause();
      this.isPaused = true;
      logger.debug('VAD paused', 'SileroVADAdapter');
    }
  }

  resume(): void {
    if (this.micVAD && this.isRunning && this.isPaused) {
      // MicVAD.resume() is async
      (this.micVAD as any).resume().then(() => {
        this.micVAD?.start();
        this.isPaused = false;
        logger.debug('VAD resumed', 'SileroVADAdapter');
      }).catch((error: Error) => {
        logger.error('Failed to resume VAD', 'SileroVADAdapter', { error });
      });
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
    return this.micVAD !== undefined && this.isRunning;
  }

  destroy(): void {
    if (this.micVAD) {
      this.micVAD.destroy();
      this.micVAD = undefined;
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
