import { EventEmitter } from 'eventemitter3';
import { pipeline, env, Pipeline } from '@xenova/transformers';
import { Result, logger, AudioError } from '@runanywhere/core';
import type {
  WhisperConfig,
  TranscriptionSegment,
  TranscriptionResult,
  DownloadProgress,
  PartialTranscription
} from '../types';

// Configure Transformers.js
env.allowLocalModels = true;
env.useBrowserCache = true;
env.backends.onnx.wasm.numThreads = 1;

export class WhisperService extends EventEmitter {
  private transcriber: Pipeline | null = null;
  private isLoading = false;
  private isReady = false;
  private config: WhisperConfig;
  private abortController?: AbortController;

  constructor(config: Partial<WhisperConfig> = {}) {
    super();
    this.config = {
      model: 'whisper-tiny',
      task: 'transcribe',
      temperature: 0,
      beamSize: 1,
      patience: 1,
      lengthPenalty: 1,
      repetitionPenalty: 1.1,
      noRepeatNgramSize: 3,
      returnTimestamps: true,
      chunkLengthSec: 30,
      strideLengthSec: 5,
      ...config
    };
  }

  async initialize(): Promise<Result<void, Error>> {
    if (this.isReady) {
      return Result.ok(undefined);
    }

    if (this.isLoading) {
      return Result.err(new AudioError('Whisper model is already loading'));
    }

    this.isLoading = true;
    this.emit('loading');

    try {
      logger.info('Loading Whisper model', 'Whisper', { model: this.config.model });

      // Load the transcription pipeline
      this.transcriber = await pipeline(
        'automatic-speech-recognition',
        `Xenova/${this.config.model}.en`,
        {
          progress_callback: (progress: any) => {
            const downloadProgress: DownloadProgress = {
              loaded: progress.loaded,
              total: progress.total,
              progress: progress.progress || (progress.loaded / progress.total)
            };
            this.emit('downloadProgress', downloadProgress);
          }
        }
      );

      this.isReady = true;
      this.isLoading = false;

      logger.info('Whisper model loaded successfully', 'Whisper');
      this.emit('ready');

      return Result.ok(undefined);
    } catch (error) {
      this.isLoading = false;
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Failed to load Whisper model: ${err.message}`, 'Whisper');
      this.emit('error', err);
      return Result.err(err);
    }
  }

  async transcribe(
    audio: Float32Array,
    options: Partial<WhisperConfig> = {}
  ): Promise<Result<TranscriptionResult, Error>> {
    if (!this.isReady || !this.transcriber) {
      return Result.err(new AudioError('Whisper model not initialized'));
    }

    const startTime = performance.now();
    this.abortController = new AbortController();

    try {
      const config = { ...this.config, ...options };

      logger.debug('Starting transcription', 'Whisper', {
        audioLength: audio.length,
        sampleRate: 16000
      });

      this.emit('transcriptionStart');

      // Run transcription
      const output = await this.transcriber(audio, {
        return_timestamps: config.returnTimestamps,
        chunk_length_s: config.chunkLengthSec,
        stride_length_s: config.strideLengthSec,
        language: config.language,
        task: config.task,
        // Generation parameters
        temperature: config.temperature,
        num_beams: config.beamSize,
        patience: config.patience,
        length_penalty: config.lengthPenalty,
        repetition_penalty: config.repetitionPenalty,
        no_repeat_ngram_size: config.noRepeatNgramSize
      });

      const processingTime = performance.now() - startTime;
      const duration = audio.length / 16000; // Assuming 16kHz sample rate

      // Parse segments
      const segments: TranscriptionSegment[] = [];
      if (output.chunks && Array.isArray(output.chunks)) {
        for (const chunk of output.chunks) {
          segments.push({
            text: chunk.text || '',
            start: chunk.timestamp?.[0] ?? 0,
            end: chunk.timestamp?.[1] ?? duration,
            confidence: chunk.confidence
          });

          // Emit partial results
          const partial: PartialTranscription = {
            text: chunk.text || '',
            timestamp: chunk.timestamp?.[0]
          };
          this.emit('partialTranscription', partial);
        }
      }

      const result: TranscriptionResult = {
        text: output.text || '',
        segments,
        language: output.language,
        duration,
        processingTime
      };

      logger.info('Transcription completed', 'Whisper', {
        duration: `${duration.toFixed(2)}s`,
        processingTime: `${processingTime.toFixed(0)}ms`,
        rtf: (processingTime / 1000 / duration).toFixed(2)
      });

      this.emit('transcriptionComplete', result);
      return Result.ok(result);

    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        logger.info('Transcription cancelled', 'Whisper');
        return Result.err(new AudioError('Transcription cancelled'));
      }

      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Transcription failed: ${err.message}`, 'Whisper');
      this.emit('transcriptionError', err);
      return Result.err(err);
    } finally {
      this.abortController = undefined;
    }
  }

  cancel(): void {
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = undefined;
    }
  }

  async changeModel(model: WhisperConfig['model']): Promise<Result<void, Error>> {
    this.isReady = false;
    this.transcriber = null;
    this.config.model = model;
    return this.initialize();
  }

  isHealthy(): boolean {
    return this.isReady && this.transcriber !== null;
  }

  destroy(): void {
    this.cancel();
    this.transcriber = null;
    this.isReady = false;
    this.removeAllListeners();
  }
}
