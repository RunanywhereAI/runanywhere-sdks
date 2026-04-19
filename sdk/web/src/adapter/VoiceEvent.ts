// SPDX-License-Identifier: Apache-2.0
// Identical shape to frontends/ts — kept as its own file so web doesn't
// pull the `react-native` peer dep. Future: factor into a shared package.
export type VoiceEvent =
  | { kind: 'user-said';        text: string; isFinal: boolean }
  | { kind: 'assistant-token';  text: string; tokenKind: TokenKind; isFinal: boolean }
  | { kind: 'audio';            pcm: Uint8Array; sampleRateHz: number }
  | { kind: 'interrupted';      reason: string }
  | { kind: 'error';            code: number; message: string };

export type TokenKind = 'answer' | 'thought' | 'tool-call';

export class RunAnywhereError extends Error {
  constructor(public readonly code: number, message: string) {
    super(`[${code}] ${message}`);
    this.name = 'RunAnywhereError';
  }
}
