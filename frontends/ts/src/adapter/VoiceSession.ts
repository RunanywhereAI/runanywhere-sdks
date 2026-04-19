// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import type { SolutionConfig } from './RunAnywhere.js';
import { RunAnywhereError, type VoiceEvent } from './VoiceEvent.js';

/**
 * Async iterable over VoiceAgent events.
 *
 *     const session = RunAnywhere.solution({ kind: 'voice-agent', config: {} });
 *     for await (const event of session.run()) {
 *         switch (event.kind) { ... }
 *     }
 */
export class VoiceSession {
  private readonly handle: number;
  public  readonly config: SolutionConfig;

  private constructor(config: SolutionConfig, handle: number) {
    this.config = config;
    this.handle = handle;
  }

  static create(config: SolutionConfig): VoiceSession {
    // TODO(phase-3): encode proto3 SolutionConfig bytes, call
    //                ra_pipeline_create_from_solution via JSI / WASM.
    return new VoiceSession(config, 0);
  }

  async *run(): AsyncIterable<VoiceEvent> {
    if (this.handle === 0) {
      yield {
        kind: 'error',
        code: -6,
        message: 'RunAnywhere v2 native core not linked in this build',
      };
      return;
    }
    // TODO(phase-3): native callback → proto3 decode → yield.
  }

  stop(): void {
    // TODO(phase-3): ra_pipeline_cancel(handle)
  }
}

export { RunAnywhereError };
