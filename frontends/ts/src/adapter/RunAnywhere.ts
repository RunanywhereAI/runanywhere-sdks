// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — public TypeScript / React Native entry point.

import { VoiceSession } from './VoiceSession.js';

export type SolutionConfig =
  | { kind: 'voice-agent'; config: VoiceAgentConfig }
  | { kind: 'rag';         config: RAGConfig        }
  | { kind: 'wake-word';   config: WakeWordConfig   };

export interface VoiceAgentConfig {
  llm?:              string;
  stt?:              string;
  tts?:              string;
  vad?:              string;
  sampleRateHz?:     number;
  chunkMs?:          number;
  enableBargeIn?:    boolean;
  emitPartials?:     boolean;
  emitThoughts?:     boolean;
  systemPrompt?:     string;
  maxContextTokens?: number;
  temperature?:      number;
}

export interface RAGConfig {
  embedModel?:      string;
  rerankModel?:     string;
  llm?:             string;
  vectorStorePath?: string;
  retrieveK?:       number;
  rerankTop?:       number;
}

export interface WakeWordConfig {
  model?:     string;
  keyword?:   string;
  threshold?: number;
  preRollMs?: number;
}

export const RunAnywhere = {
  /** Open a VoiceAgent / RAG / WakeWord session from a solution config. */
  solution(config: SolutionConfig): VoiceSession {
    return VoiceSession.create(config);
  },

  /**
   * Dynamic plugin load — React Native / Node only. Delegates to the
   * registered NativePipelineBindings (the TurboModule / N-API wrapper)
   * when one is present; returns false otherwise.
   */
  loadPlugin(libPath: string): boolean {
    const hostAny = RunAnywhere as unknown as {
      _hostLoadPlugin?: (path: string) => boolean;
    };
    return hostAny._hostLoadPlugin
      ? hostAny._hostLoadPlugin(libPath)
      : false;
  },

  /**
   * Host plug-in (React Native / Node) installs its loader here at
   * startup. See VoiceSession.setNativeBindings for the analogous
   * per-session surface.
   */
  setHostLoadPlugin(fn: ((path: string) => boolean) | null): void {
    (RunAnywhere as unknown as { _hostLoadPlugin?: ((p: string) => boolean) | null })
      ._hostLoadPlugin = fn ?? undefined;
  },
};
