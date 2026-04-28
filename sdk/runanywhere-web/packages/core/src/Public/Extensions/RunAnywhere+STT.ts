/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-text namespace — mirrors Swift's `RunAnywhere+STT.swift`.
 * Provides `RunAnywhere.stt.*` capability surface around transcribe.
 */

import type { STTOptions, STTOutput } from '@runanywhere/proto-ts/stt_options';
import type { STTTranscriptionResult, STTTranscribeOptions } from '../../types/index';
import { transcribe } from './RunAnywhere+Convenience';

export type { STTOptions, STTOutput };

export const STT = {
  async transcribe(
    audio: Float32Array | File,
    options?: STTTranscribeOptions,
  ): Promise<STTTranscriptionResult> {
    return transcribe(audio, options);
  },
};
