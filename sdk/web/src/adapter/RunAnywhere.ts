// SPDX-License-Identifier: Apache-2.0
import { VoiceSession } from './VoiceSession.js';

export type SolutionConfig =
  | { kind: 'voice-agent'; config: VoiceAgentConfig }
  | { kind: 'rag';         config: RAGConfig        }
  | { kind: 'wake-word';   config: WakeWordConfig   };

export interface VoiceAgentConfig {
  llm?: string;
  stt?: string;
  tts?: string;
  vad?: string;
  sampleRateHz?: number;
  enableBargeIn?: boolean;
  emitPartials?: boolean;
  systemPrompt?: string;
}

export interface RAGConfig {
  embedModel?: string;
  rerankModel?: string;
  llm?: string;
  retrieveK?: number;
}

export interface WakeWordConfig {
  model?: string;
  keyword?: string;
  threshold?: number;
}

export interface RunAnywhereWebOptions {
  /** URL of the WASM module — loaded lazily on first session. */
  wasmUrl?: string;
}

export const RunAnywhere = {
  /** Loads the WASM module and constructs a VoiceSession. */
  async solution(config: SolutionConfig,
                 opts: RunAnywhereWebOptions = {}): Promise<VoiceSession> {
    return VoiceSession.create(config, opts);
  },
};
