// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import { ModelFormat, RunAnywhereError,
         type TranscriptChunk, type VADEvent } from './Types.js';
import { requireNativeSessionBindings } from './NativeBindings.js';

/** Streaming speech-to-text session. */
export class STTSession {
  private handle: number;
  private readonly bindings = requireNativeSessionBindings();
  private readonly queue: TranscriptChunk[] = [];
  private wake: (() => void) | null = null;
  private closed = false;

  constructor(modelId: string, modelPath: string,
              format: ModelFormat = ModelFormat.WhisperKit) {
    this.handle = this.bindings.sttCreate(modelId, modelPath, format, (c) => {
      this.queue.push(c); this.wake?.();
    });
    if (this.handle === 0) {
      throw new RunAnywhereError(RunAnywhereError.BACKEND_UNAVAILABLE,
                                  'ra_stt_create returned null');
    }
  }

  feedAudio(samples: Float32Array, sampleRateHz: number): number {
    return this.bindings.sttFeedAudio(this.handle, samples, sampleRateHz);
  }

  flush(): number { return this.bindings.sttFlush(this.handle); }

  async *transcripts(): AsyncIterable<TranscriptChunk> {
    while (!this.closed) {
      while (this.queue.length > 0) yield this.queue.shift()!;
      if (this.closed) return;
      await new Promise<void>((res) => { this.wake = () => { this.wake = null; res(); }; });
    }
  }

  close(): void {
    this.closed = true; this.wake?.();
    if (this.handle !== 0) { this.bindings.sttDestroy(this.handle); this.handle = 0; }
  }
}

/** Text-to-speech session. Returns PCM + sample rate. */
export class TTSSession {
  private handle: number;
  private readonly bindings = requireNativeSessionBindings();

  constructor(modelId: string, modelPath: string,
              format: ModelFormat = ModelFormat.ONNX) {
    this.handle = this.bindings.ttsCreate(modelId, modelPath, format);
    if (this.handle === 0) {
      throw new RunAnywhereError(RunAnywhereError.BACKEND_UNAVAILABLE,
                                  'ra_tts_create returned null');
    }
  }

  synthesize(text: string): { pcm: Float32Array; sampleRateHz: number } {
    const r = this.bindings.ttsSynthesize(this.handle, text);
    if (!r) throw new RunAnywhereError(-1, 'ra_tts_synthesize failed');
    return r;
  }

  cancel(): number { return this.bindings.ttsCancel(this.handle); }
  close(): void {
    if (this.handle !== 0) { this.bindings.ttsDestroy(this.handle); this.handle = 0; }
  }
}

/** Voice activity detection session. */
export class VADSession {
  private handle: number;
  private readonly bindings = requireNativeSessionBindings();
  private readonly queue: VADEvent[] = [];
  private wake: (() => void) | null = null;
  private closed = false;

  constructor(modelId: string, modelPath: string,
              format: ModelFormat = ModelFormat.ONNX) {
    this.handle = this.bindings.vadCreate(modelId, modelPath, format, (e) => {
      this.queue.push(e); this.wake?.();
    });
    if (this.handle === 0) {
      throw new RunAnywhereError(RunAnywhereError.BACKEND_UNAVAILABLE,
                                  'ra_vad_create returned null');
    }
  }

  feedAudio(samples: Float32Array, sampleRateHz: number): number {
    return this.bindings.vadFeedAudio(this.handle, samples, sampleRateHz);
  }

  async *events(): AsyncIterable<VADEvent> {
    while (!this.closed) {
      while (this.queue.length > 0) yield this.queue.shift()!;
      if (this.closed) return;
      await new Promise<void>((res) => { this.wake = () => { this.wake = null; res(); }; });
    }
  }

  close(): void {
    this.closed = true; this.wake?.();
    if (this.handle !== 0) { this.bindings.vadDestroy(this.handle); this.handle = 0; }
  }
}

/** Text embedding session. */
export class EmbedSession {
  private handle: number;
  private readonly bindings = requireNativeSessionBindings();
  public readonly dims: number;

  constructor(modelId: string, modelPath: string,
              format: ModelFormat = ModelFormat.GGUF) {
    this.handle = this.bindings.embedCreate(modelId, modelPath, format);
    if (this.handle === 0) {
      throw new RunAnywhereError(RunAnywhereError.BACKEND_UNAVAILABLE,
                                  'ra_embed_create returned null');
    }
    this.dims = this.bindings.embedDims(this.handle);
  }

  embed(text: string): Float32Array {
    const r = this.bindings.embedText(this.handle, text);
    if (!r) throw new RunAnywhereError(-1, 'ra_embed_text failed');
    return r;
  }

  close(): void {
    if (this.handle !== 0) { this.bindings.embedDestroy(this.handle); this.handle = 0; }
  }
}
