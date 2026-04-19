// SPDX-License-Identifier: Apache-2.0

import type { SolutionConfig, RunAnywhereWebOptions } from './RunAnywhere.js';
import type { VoiceEvent } from './VoiceEvent.js';

/**
 * Matches the emscripten-emitted module surface for the core's
 * ra_pipeline_* functions. An application loads racommons_core.js from the
 * WASM bundle and registers the module with VoiceSession.setWasmModule
 * once per page. All subsequent VoiceSession instances share that module.
 */
export interface WasmCoreModule {
  _ra_pipeline_create_voice_agent(cfgPtr: number, outPtr: number): number;
  _ra_pipeline_destroy(handle: number): void;
  _ra_pipeline_run(handle: number): number;
  _ra_pipeline_cancel(handle: number): number;
  _ra_pipeline_feed_audio(handle: number, pcmPtr: number, n: number,
                           sampleRateHz: number): number;
  _ra_pipeline_inject_barge_in(handle: number): number;

  _malloc(size: number): number;
  _free(ptr: number): void;
  HEAP8:  Int8Array;
  HEAPU8: Uint8Array;
  HEAPF32: Float32Array;
  HEAP32: Int32Array;
  HEAPU32: Uint32Array;

  addFunction?(f: Function, sig: string): number;
  removeFunction?(idx: number): void;
}

let wasmModule: WasmCoreModule | null = null;

export class VoiceSession {
  private handle = 0;
  public  readonly config: SolutionConfig;

  private constructor(config: SolutionConfig) {
    this.config = config;
  }

  /** Register the emscripten-loaded WASM module at page init. */
  static setWasmModule(m: WasmCoreModule | null): void { wasmModule = m; }

  static async create(config: SolutionConfig,
                      _opts: RunAnywhereWebOptions = {}): Promise<VoiceSession> {
    return new VoiceSession(config);
  }

  async *run(): AsyncIterable<VoiceEvent> {
    if (!wasmModule) {
      yield {
        kind: 'error',
        code: -6,
        message: 'RunAnywhere WASM bundle not loaded; call ' +
                 'VoiceSession.setWasmModule(module) after emscripten init',
      };
      return;
    }
    if (this.config.kind !== 'voice-agent') {
      yield {
        kind: 'error',
        code: -7,
        message: 'only voice-agent solutions are wired through the WASM core yet',
      };
      return;
    }
    // Event-stream wiring via addFunction + HEAP* pointer walking is
    // deferred until the WASM bundle is published; until then we expose
    // a clean "not yet wired" error so downstream apps can integrate the
    // surface without a crash.
    yield {
      kind: 'error',
      code: -6,
      message: 'WASM event stream not yet wired — use @runanywhere/core via ' +
               'TurboModule on React Native or libracommons_core on desktop for ' +
               'a fully bridged path',
    };
  }

  stop(): void {
    if (this.handle !== 0 && wasmModule) {
      wasmModule._ra_pipeline_cancel(this.handle);
    }
  }

  bargeIn(): void {
    if (this.handle !== 0 && wasmModule) {
      wasmModule._ra_pipeline_inject_barge_in(this.handle);
    }
  }
}
