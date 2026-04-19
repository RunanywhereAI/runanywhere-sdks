// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

export type VoiceEvent =
  | { kind: 'user-said';        text: string; isFinal: boolean }
  | { kind: 'assistant-token';  text: string; tokenKind: TokenKind; isFinal: boolean }
  | { kind: 'audio';            pcm: Uint8Array; sampleRateHz: number }
  | { kind: 'interrupted';      reason: string }
  | { kind: 'state-change';     previous: PipelineState; current: PipelineState }
  | { kind: 'metrics';          latencyMs: number }
  | { kind: 'error';            code: number; message: string };

export type TokenKind = 'answer' | 'thought' | 'tool-call';

export type PipelineState =
  | 'idle' | 'listening' | 'thinking' | 'speaking' | 'stopped';

export class RunAnywhereError extends Error {
  constructor(public readonly code: number, message: string) {
    super(`[${code}] ${message}`);
    this.name = 'RunAnywhereError';
  }
}
