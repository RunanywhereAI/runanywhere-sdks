// SPDX-License-Identifier: Apache-2.0

import type { SolutionConfig, RunAnywhereWebOptions } from './RunAnywhere.js';
import type { VoiceEvent } from './VoiceEvent.js';

export class VoiceSession {
  private readonly handle: number;
  public  readonly config: SolutionConfig;

  private constructor(config: SolutionConfig, handle: number) {
    this.config = config;
    this.handle = handle;
  }

  static async create(config: SolutionConfig,
                      _opts: RunAnywhereWebOptions): Promise<VoiceSession> {
    // TODO(phase-3): load wasm bundle, call ra_pipeline_create_from_solution
    //                through emscripten asyncify bridge.
    return new VoiceSession(config, 0);
  }

  async *run(): AsyncIterable<VoiceEvent> {
    if (this.handle === 0) {
      yield {
        kind: 'error',
        code: -6,
        message: 'RunAnywhere v2 WASM bundle not loaded',
      };
      return;
    }
    // TODO(phase-3): asyncify callback bridge → yield events.
  }

  stop(): void {
    // TODO(phase-3)
  }
}
