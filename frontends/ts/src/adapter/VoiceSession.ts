// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import type { SolutionConfig } from './RunAnywhere.js';
import { RunAnywhereError, type VoiceEvent } from './VoiceEvent.js';

/**
 * Matches the `ra_pipeline_*` C ABI shape. A host application registers
 * an implementation via `VoiceSession.setNativeBindings` at startup:
 *
 *   - React Native host: `NativeModules.RACommonsCore` wraps the Swift /
 *     Kotlin bindings via JSI.
 *   - Node.js host: a `require('bindings')('racommons_core')` N-API wrapper
 *     fulfills this shape.
 *   - Browser host: @runanywhere/web-core fulfills this shape from a WASM
 *     emscripten bundle.
 *
 * When no bindings are registered, every VoiceSession.run() yields a
 * BACKEND_UNAVAILABLE error instead of attempting to load a native library.
 */
export interface NativePipelineBindings {
  /** Returns an opaque native handle (0 on failure). */
  createVoiceAgent(config: Record<string, unknown>): number;
  /** Asynchronous event stream from the native pipeline. */
  subscribe(handle: number, onEvent: (event: VoiceEvent) => void,
            onDone: () => void, onError: (code: number, msg: string) => void): void;
  run(handle: number): number;
  cancel(handle: number): number;
  destroy(handle: number): void;
  feedAudio(handle: number, samples: Float32Array, sampleRateHz: number): number;
  bargeIn(handle: number): number;
}

let nativeBindings: NativePipelineBindings | null = null;

/**
 * Async iterable over VoiceAgent events.
 *
 *     const session = RunAnywhere.solution({ kind: 'voice-agent', config: {} });
 *     for await (const event of session.run()) {
 *         switch (event.kind) { ... }
 *     }
 */
export class VoiceSession {
  private handle: number = 0;
  public  readonly config: SolutionConfig;
  private readonly queue: VoiceEvent[] = [];
  private closed = false;
  private error: { code: number; message: string } | null = null;
  private wake: (() => void) | null = null;

  private constructor(config: SolutionConfig) {
    this.config = config;
  }

  /** Register the native bindings. Called once at application startup. */
  static setNativeBindings(b: NativePipelineBindings | null): void {
    nativeBindings = b;
  }

  static create(config: SolutionConfig): VoiceSession {
    const s = new VoiceSession(config);
    if (!nativeBindings) return s;
    if (config.kind !== 'voice-agent') return s;
    const va = config.config;
    s.handle = nativeBindings.createVoiceAgent({
      llm:               va.llm ?? 'qwen3-4b',
      stt:               va.stt ?? 'whisper-base',
      tts:               va.tts ?? 'kokoro',
      vad:               va.vad ?? 'silero-v5',
      sampleRateHz:      va.sampleRateHz ?? 16000,
      chunkMs:           va.chunkMs ?? 20,
      enableBargeIn:     va.enableBargeIn ?? true,
      systemPrompt:      va.systemPrompt ?? '',
      maxContextTokens:  va.maxContextTokens ?? 4096,
      temperature:       va.temperature ?? 0.7,
      emitPartials:      va.emitPartials ?? true,
      emitThoughts:      va.emitThoughts ?? false,
    });
    if (s.handle !== 0) {
      nativeBindings.subscribe(s.handle,
        (event) => { s.queue.push(event); s.wake?.(); },
        ()      => { s.closed = true;     s.wake?.(); },
        (c, m)  => { s.error = { code: c, message: m }; s.closed = true; s.wake?.(); });
    }
    return s;
  }

  async *run(): AsyncIterable<VoiceEvent> {
    if (!nativeBindings) {
      yield {
        kind: 'error',
        code: -6,
        message: 'RunAnywhere native bindings not registered; ' +
                 'call VoiceSession.setNativeBindings() at app startup',
      };
      return;
    }
    if (this.handle === 0) {
      yield {
        kind: 'error',
        code: -6,
        message: 'ra_pipeline_create_voice_agent returned null handle',
      };
      return;
    }
    const rc = nativeBindings.run(this.handle);
    if (rc !== 0) {
      yield { kind: 'error', code: rc, message: `ra_pipeline_run failed: ${rc}` };
      return;
    }
    while (true) {
      while (this.queue.length > 0) {
        yield this.queue.shift()!;
      }
      if (this.closed) {
        if (this.error) {
          yield { kind: 'error', code: this.error.code, message: this.error.message };
        }
        return;
      }
      await new Promise<void>((res) => { this.wake = () => { this.wake = null; res(); }; });
    }
  }

  stop(): void {
    if (this.handle !== 0 && nativeBindings) {
      nativeBindings.cancel(this.handle);
    }
  }

  bargeIn(): void {
    if (this.handle !== 0 && nativeBindings) {
      nativeBindings.bargeIn(this.handle);
    }
  }

  feedAudio(samples: Float32Array, sampleRateHz: number): void {
    if (this.handle !== 0 && nativeBindings) {
      nativeBindings.feedAudio(this.handle, samples, sampleRateHz);
    }
  }
}

export { RunAnywhereError };
