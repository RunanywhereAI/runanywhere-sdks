import {
  BaseAdapter,
  type STTAdapter,
  type STTEvents,
  type STTConfig,
  type STTMetrics,
  type TranscriptionResult,
  type ModelInfo,
  type TranscribeOptions,
  Result,
  logger,
} from '@runanywhere/core';
import { WHISPER_WEB_CONSTANTS, MODELS } from './constants.js';
import { type WorkerMessage, type WorkerResponse, type TranscriptionOutput } from './types.js';

export interface WhisperWebSTTConfig extends STTConfig {
  model?: keyof typeof MODELS;
  device?: 'wasm' | 'webgpu';
  dtype?: string;
  language?: string;
  task?: 'transcribe' | 'translate';
}

export class WhisperWebSTTAdapter extends BaseAdapter<STTEvents> implements STTAdapter {
  readonly id = 'whisper-web';
  readonly name = 'Whisper Web (Fork Implementation)';
  readonly version = '1.0.0';
  readonly supportedModels: ModelInfo[] = Object.entries(MODELS).map(([id, [name]]) => ({
    id,
    name: `Whisper ${name.charAt(0).toUpperCase() + name.slice(1)}`,
    size: 'Variable',
    languages: ['en', 'multi'],
    accuracy: 'high' as const,
    speed: 'medium' as const
  }));

  private worker?: Worker;
  private currentModel?: string;
  private config?: WhisperWebSTTConfig;
  private isInitialized = false;
  private modelLoaded = false;
  private workerReady = false;
  private metrics: STTMetrics = {
    totalTranscriptions: 0,
    avgProcessingTime: 0,
    modelLoadTime: 0
  };

  async initialize(config?: WhisperWebSTTConfig): Promise<Result<void, Error>> {
    try {
      this.config = config;
      logger.info('Initializing WhisperWebSTTAdapter', 'WhisperWebSTTAdapter');

      // Create worker using ES module pattern from fork
      const workerUrl = '/stt-whisper-web-worker.js';
      this.worker = new Worker(workerUrl, {
        type: 'module',
        name: 'whisper-web-worker'
      });

      this.worker.onmessage = (event) => this.handleWorkerMessage(event.data);
      this.worker.onerror = (error) => {
        logger.error('Worker error', 'WhisperWebSTTAdapter', { error });
        this.emit('error', error as any);
      };

      // Fork doesn't wait for worker ready - just mark as initialized
      this.isInitialized = true;
      this.workerReady = true;
      logger.info('WhisperWebSTTAdapter initialized successfully', 'WhisperWebSTTAdapter');

      return Result.ok(undefined);
    } catch (error) {
      logger.error('Failed to initialize WhisperWebSTTAdapter', 'WhisperWebSTTAdapter', { error });
      return Result.err(error as Error);
    }
  }

  async loadModel(modelId: string): Promise<Result<void, Error>> {
    if (!this.isInitialized) {
      return Result.err(new Error('Adapter not initialized'));
    }

    this.currentModel = modelId;
    this.modelLoaded = true;
    return Result.ok(undefined);
  }

  // Removed waitForWorkerReady - fork doesn't have this pattern

  private handleWorkerMessage(message: WorkerResponse): void {
    const { status, data } = message;

    switch (status) {
      case 'progress':
        this.emit('model_loading', {
          progress: message.progress || 0,
          message: message.message || 'Loading model...'
        });
        break;

      case 'update':
        // Handle streaming updates with chunks (EXACT from fork)
        if (data?.chunks && data.chunks.length > 0) {
          const latestChunk = data.chunks[data.chunks.length - 1];
          if (latestChunk?.text) {
            this.emit('partial_transcript', latestChunk.text);
          }
        }
        break;

      case 'chunk':
        if (data?.text) {
          this.emit('partial_transcript', data.text);
        }
        break;

      case 'complete':
        // Transcription completed - handled in waitForTranscription
        break;

      case 'error':
        this.emit('error', new Error(message.message || 'Worker error'));
        break;
    }
  }

  async transcribe(
    audio: Float32Array,
    options?: TranscribeOptions
  ): Promise<Result<TranscriptionResult, Error>> {
    if (!this.worker || !this.workerReady) {
      return Result.err(new Error('Worker not ready'));
    }

    try {
      const startTime = performance.now();
      const model = this.config?.model || 'onnx-community/whisper-tiny';
      const dtype = this.config?.dtype || WHISPER_WEB_CONSTANTS.DEFAULT_DTYPE;
      const gpu = this.config?.device === 'webgpu';

      // CRITICAL: Make sure we have a proper Float32Array
      // Some browsers might need a fresh array to ensure proper transfer
      let audioToSend: Float32Array;

      // Check if the audio buffer is detached or needs refresh
      if (!audio.buffer || audio.buffer.byteLength === 0) {
        logger.error('Audio buffer is detached or empty!', 'WhisperWebSTTAdapter');
        return Result.err(new Error('Audio buffer is invalid'));
      }

      // Use the audio directly without copying (like fork)
      audioToSend = audio;

      // Send transcription request (EXACT pattern from fork)
      const workerMessage: WorkerMessage = {
        audio: audioToSend,
        model,
        dtype,
        gpu,
        subtask: !model.endsWith(".en") ? (options?.task || this.config?.task || 'transcribe') : null,
        language: !model.endsWith(".en") && (options?.language || this.config?.language || null) !== "auto"
                 ? (options?.language || this.config?.language || null)
                 : null
      };

      // DEBUG: Log audio data details
      logger.info(`Sending to worker - Audio length: ${audioToSend.length}, Model: ${model}, Subtask: ${workerMessage.subtask}, Language: ${workerMessage.language}`, 'WhisperWebSTTAdapter');

      // More detailed audio logging
      const audioSample = audio.slice(0, 10);
      const hasNonZero = audio.some(v => v !== 0);
      const firstNonZeroIndex = audio.findIndex(v => v !== 0);
      const audioStats = {
        firstSamples: Array.from(audioSample),
        hasNonZero,
        firstNonZeroIndex,
        minValue: Math.min(...Array.from(audio.slice(0, Math.min(1000, audio.length)))),
        maxValue: Math.max(...Array.from(audio.slice(0, Math.min(1000, audio.length)))),
        isFloat32Array: audio instanceof Float32Array,
        audioBuffer: audio.buffer,
        byteLength: audio.buffer.byteLength
      };

      logger.info(`Audio data details: ${JSON.stringify(audioStats)}`, 'WhisperWebSTTAdapter');

      this.worker.postMessage(workerMessage);

      const result = await this.waitForTranscription();

      // Update metrics
      const processingTime = performance.now() - startTime;
      this.metrics.totalTranscriptions++;
      this.metrics.avgProcessingTime =
        (this.metrics.avgProcessingTime * (this.metrics.totalTranscriptions - 1) + processingTime) /
        this.metrics.totalTranscriptions;

      return Result.ok(result);
    } catch (error) {
      logger.error('Transcription failed', 'WhisperWebSTTAdapter', { error });
      return Result.err(error as Error);
    }
  }

  private async waitForTranscription(): Promise<TranscriptionResult> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Transcription timeout')), 60000);

      const handler = (event: MessageEvent) => {
        if (event.data.status === 'complete') {
          clearTimeout(timeout);
          this.worker!.removeEventListener('message', handler);

          // Transform fork output to our format
          const output = event.data.data as TranscriptionOutput;
          const result: TranscriptionResult = {
            text: output.text || '',
            confidence: 1.0,
            language: this.config?.language || 'en',
            timestamps: output.chunks?.map(chunk => ({
              text: chunk.text,
              start: chunk.timestamp[0],
              end: chunk.timestamp[1] || chunk.timestamp[0]
            })) || []
          };

          resolve(result);
        } else if (event.data.status === 'error') {
          clearTimeout(timeout);
          this.worker!.removeEventListener('message', handler);
          reject(new Error(event.data.data?.message || 'Transcription failed'));
        }
      };

      this.worker!.addEventListener('message', handler);
    });
  }

  // Standard adapter methods
  destroy(): void {
    if (this.worker) {
      this.worker.terminate();
      this.worker = undefined;
    }
    this.removeAllListeners();
    this.isInitialized = false;
    this.workerReady = false;
    this.modelLoaded = false;
  }

  isModelLoaded(): boolean {
    return this.modelLoaded;
  }

  getLoadedModel(): ModelInfo | null {
    if (!this.currentModel) return null;
    return this.supportedModels.find(m => m.id === this.currentModel) || null;
  }

  isHealthy(): boolean {
    return this.isInitialized && this.workerReady;
  }

  getMetrics(): STTMetrics {
    return { ...this.metrics };
  }
}

// Export utilities for use in React components
export { convertStereoToMono, createAudioContext } from './utils/audio.js';
export { webmFixDuration } from './utils/BlobFix.js';
export { WHISPER_WEB_CONSTANTS, MODELS } from './constants.js';
export type { WorkerMessage, WorkerResponse, TranscriptionOutput } from './types.js';

export default WhisperWebSTTAdapter;
