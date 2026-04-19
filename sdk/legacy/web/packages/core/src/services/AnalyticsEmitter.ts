/**
 * AnalyticsEmitter — abstract telemetry emission interface.
 *
 * Backend-agnostic: the core package defines the interface, while the
 * llamacpp package provides the concrete WASM-backed implementation.
 * This mirrors the iOS architecture where all analytics events flow
 * through the C++ telemetry manager (rac_analytics_event_emit →
 * rac_telemetry_manager → HTTP callback).
 *
 * If no backend is registered, calls are silently dropped.
 */

import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('AnalyticsEmitter');

// ---------------------------------------------------------------------------
// Backend interface (implemented by @runanywhere/web-llamacpp)
// ---------------------------------------------------------------------------

export interface AnalyticsEmitterBackend {
  // STT events
  emitSTTModelLoadCompleted(modelId: string, modelName: string, durationMs: number, framework: number): void;
  emitSTTModelLoadFailed(modelId: string, errorCode: number, errorMessage: string): void;
  emitSTTTranscriptionCompleted(
    transcriptionId: string, modelId: string, text: string, confidence: number,
    durationMs: number, audioLengthMs: number, audioSizeBytes: number,
    wordCount: number, realTimeFactor: number, language: string,
    sampleRate: number, framework: number,
  ): void;
  emitSTTTranscriptionFailed(transcriptionId: string, modelId: string, errorCode: number, errorMessage: string): void;

  // TTS events
  emitTTSVoiceLoadCompleted(modelId: string, modelName: string, durationMs: number, framework: number): void;
  emitTTSVoiceLoadFailed(modelId: string, errorCode: number, errorMessage: string): void;
  emitTTSSynthesisCompleted(
    synthesisId: string, modelId: string, characterCount: number,
    audioDurationMs: number, audioSizeBytes: number, processingDurationMs: number,
    charactersPerSecond: number, sampleRate: number, framework: number,
  ): void;
  emitTTSSynthesisFailed(synthesisId: string, modelId: string, errorCode: number, errorMessage: string): void;

  // VAD events
  emitVADSpeechStarted(): void;
  emitVADSpeechEnded(speechDurationMs: number, energyLevel: number): void;

  // Model download events
  emitModelDownloadStarted(modelId: string): void;
  emitModelDownloadCompleted(modelId: string, fileSizeBytes: number, durationMs: number): void;
  emitModelDownloadFailed(modelId: string, errorMessage: string): void;
}

// ---------------------------------------------------------------------------
// Singleton holder
// ---------------------------------------------------------------------------

class AnalyticsEmitterHolder {
  private _backend: AnalyticsEmitterBackend | null = null;

  /** Register the concrete backend (called once by LlamaCppProvider). */
  registerBackend(backend: AnalyticsEmitterBackend): void {
    this._backend = backend;
    logger.info('Analytics emitter backend registered');
  }

  /** Remove the registered backend (called during cleanup). */
  removeBackend(): void {
    this._backend = null;
  }

  /** Whether a backend has been registered. */
  get hasBackend(): boolean {
    return this._backend !== null;
  }

  // -- STT -----------------------------------------------------------------

  emitSTTModelLoadCompleted(modelId: string, modelName: string, durationMs: number, framework: number): void {
    this.safe(() => this._backend?.emitSTTModelLoadCompleted(modelId, modelName, durationMs, framework));
  }

  emitSTTModelLoadFailed(modelId: string, errorCode: number, errorMessage: string): void {
    this.safe(() => this._backend?.emitSTTModelLoadFailed(modelId, errorCode, errorMessage));
  }

  emitSTTTranscriptionCompleted(
    transcriptionId: string, modelId: string, text: string, confidence: number,
    durationMs: number, audioLengthMs: number, audioSizeBytes: number,
    wordCount: number, realTimeFactor: number, language: string,
    sampleRate: number, framework: number,
  ): void {
    this.safe(() => this._backend?.emitSTTTranscriptionCompleted(
      transcriptionId, modelId, text, confidence,
      durationMs, audioLengthMs, audioSizeBytes,
      wordCount, realTimeFactor, language, sampleRate, framework,
    ));
  }

  emitSTTTranscriptionFailed(transcriptionId: string, modelId: string, errorCode: number, errorMessage: string): void {
    this.safe(() => this._backend?.emitSTTTranscriptionFailed(transcriptionId, modelId, errorCode, errorMessage));
  }

  // -- TTS -----------------------------------------------------------------

  emitTTSVoiceLoadCompleted(modelId: string, modelName: string, durationMs: number, framework: number): void {
    this.safe(() => this._backend?.emitTTSVoiceLoadCompleted(modelId, modelName, durationMs, framework));
  }

  emitTTSVoiceLoadFailed(modelId: string, errorCode: number, errorMessage: string): void {
    this.safe(() => this._backend?.emitTTSVoiceLoadFailed(modelId, errorCode, errorMessage));
  }

  emitTTSSynthesisCompleted(
    synthesisId: string, modelId: string, characterCount: number,
    audioDurationMs: number, audioSizeBytes: number, processingDurationMs: number,
    charactersPerSecond: number, sampleRate: number, framework: number,
  ): void {
    this.safe(() => this._backend?.emitTTSSynthesisCompleted(
      synthesisId, modelId, characterCount,
      audioDurationMs, audioSizeBytes, processingDurationMs,
      charactersPerSecond, sampleRate, framework,
    ));
  }

  emitTTSSynthesisFailed(synthesisId: string, modelId: string, errorCode: number, errorMessage: string): void {
    this.safe(() => this._backend?.emitTTSSynthesisFailed(synthesisId, modelId, errorCode, errorMessage));
  }

  // -- VAD -----------------------------------------------------------------

  emitVADSpeechStarted(): void {
    this.safe(() => this._backend?.emitVADSpeechStarted());
  }

  emitVADSpeechEnded(speechDurationMs: number, energyLevel: number): void {
    this.safe(() => this._backend?.emitVADSpeechEnded(speechDurationMs, energyLevel));
  }

  // -- Download ------------------------------------------------------------

  emitModelDownloadStarted(modelId: string): void {
    this.safe(() => this._backend?.emitModelDownloadStarted(modelId));
  }

  emitModelDownloadCompleted(modelId: string, fileSizeBytes: number, durationMs: number): void {
    this.safe(() => this._backend?.emitModelDownloadCompleted(modelId, fileSizeBytes, durationMs));
  }

  emitModelDownloadFailed(modelId: string, errorMessage: string): void {
    this.safe(() => this._backend?.emitModelDownloadFailed(modelId, errorMessage));
  }

  // -- Internal ------------------------------------------------------------

  /** Swallow any error from telemetry — must never crash the host app. */
  private safe(fn: () => void): void {
    try { fn(); } catch { /* silent — telemetry must never block the app */ }
  }
}

export const AnalyticsEmitter = new AnalyticsEmitterHolder();
