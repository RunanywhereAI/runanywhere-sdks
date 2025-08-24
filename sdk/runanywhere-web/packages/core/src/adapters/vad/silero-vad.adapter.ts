/**
 * Silero VAD Adapter Implementation
 * Wraps @ricky0123/vad-web for voice activity detection
 */

import type { MicVAD } from '@ricky0123/vad-web';
import type { VADAdapter, VADConfig, VADEvents, VADMetrics } from '../../interfaces/vad.interface';
import { Result } from '../../types/result';
import { BaseAdapter } from '../base.adapter';

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
            this.metrics.totalSpeechMs = (this.metrics.totalSpeechMs || 0) + duration;
            this.metrics.totalSpeechSegments = (this.metrics.totalSpeechSegments || 0) + 1;
            this.metrics.totalDetections++;
            this.metrics.avgSpeechDuration =
              (this.metrics.avgSpeechDuration * (this.metrics.totalDetections - 1) + duration) /
              this.metrics.totalDetections;
            this.metrics.lastDetectionTime = Date.now();
            this.metrics.lastActivityTime = Date.now();
            this.emit('speech_end', audio);
          }
        },

        onVADMisfire: () => {
          this.emit('vad_misfire');
        },
      });

      return Result.ok(undefined);
    } catch (error) {
      return Result.err(error as Error);
    }
  }

  async start(): Promise<Result<void, Error>> {
    if (!this.vad) {
      return Result.err(new Error('VAD not initialized'));
    }

    try {
      this.vad.start();
      this.isRunning = true;
      this.isPaused = false;
      return Result.ok(undefined);
    } catch (error) {
      return Result.err(error as Error);
    }
  }

  stop(): void {
    if (this.vad && this.isRunning) {
      this.vad.destroy();
      this.isRunning = false;
      this.isPaused = false;
    }
  }

  pause(): void {
    if (this.isRunning && !this.isPaused) {
      this.vad?.pause();
      this.isPaused = true;
    }
  }

  resume(): void {
    if (this.isRunning && this.isPaused) {
      this.vad?.start();
      this.isPaused = false;
    }
  }

  destroy(): void {
    this.stop();
    this.vad = undefined;
    this.removeAllListeners();
  }

  isHealthy(): boolean {
    return this.isRunning && !this.isPaused && !!this.vad;
  }

  getMetrics(): VADMetrics {
    return { ...this.metrics };
  }
}

// Metadata for registry
export const SileroVADAdapterMetadata = {
  id: 'silero',
  name: 'Silero VAD',
  version: '1.0.0',
  description: 'High-quality voice activity detection using Silero VAD model',
  modelSize: '4.3MB',
  offline: true,
  languages: ['multi'],
};
