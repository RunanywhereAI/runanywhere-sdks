// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Native bindings contract — host (React Native JSI / Node N-API / web WASM)
// implements this shape and registers it via `setNativeSessionBindings` at
// startup. Session classes (LLMSession, STTSession, ...) delegate to it.

import type { LLMToken, TranscriptChunk, VADEvent, AuthData } from './Types.js';

export interface NativeSessionBindings {
  // LLM
  llmCreate(modelId: string, modelPath: string, format: number): number;
  llmDestroy(handle: number): void;
  llmGenerate(handle: number, prompt: string,
              onToken: (t: LLMToken) => void,
              onError: (code: number, msg: string) => void): number;
  llmCancel(handle: number): number;
  llmReset(handle: number): number;
  llmInjectSystemPrompt(handle: number, prompt: string): number;
  llmAppendContext(handle: number, text: string): number;
  llmGenerateFromContext(handle: number, query: string,
                          onToken: (t: LLMToken) => void,
                          onError: (code: number, msg: string) => void): number;
  llmClearContext(handle: number): number;

  // STT
  sttCreate(modelId: string, modelPath: string, format: number,
            onChunk: (c: TranscriptChunk) => void): number;
  sttDestroy(handle: number): void;
  sttFeedAudio(handle: number, samples: Float32Array, sampleRateHz: number): number;
  sttFlush(handle: number): number;

  // TTS
  ttsCreate(modelId: string, modelPath: string, format: number): number;
  ttsDestroy(handle: number): void;
  ttsSynthesize(handle: number, text: string):
    { pcm: Float32Array; sampleRateHz: number } | null;
  ttsCancel(handle: number): number;

  // VAD
  vadCreate(modelId: string, modelPath: string, format: number,
            onEvent: (e: VADEvent) => void): number;
  vadDestroy(handle: number): void;
  vadFeedAudio(handle: number, samples: Float32Array, sampleRateHz: number): number;

  // Embed
  embedCreate(modelId: string, modelPath: string, format: number): number;
  embedDestroy(handle: number): void;
  embedText(handle: number, text: string): Float32Array | null;
  embedDims(handle: number): number;

  // SDK state
  stateInitialize(env: number, apiKey: string, baseUrl: string, deviceId: string): number;
  stateIsInitialized(): boolean;
  stateReset(): void;
  stateGetEnvironment(): number;
  stateGetApiKey(): string;
  stateGetBaseUrl(): string;
  stateGetDeviceId(): string;
  stateSetAuth(data: AuthData): number;
  stateGetAccessToken(): string;
  stateGetRefreshToken(): string;
  stateGetUserId(): string;
  stateGetOrganizationId(): string;
  stateIsAuthenticated(): boolean;
  stateTokenNeedsRefresh(horizonSeconds: number): boolean;
  stateGetTokenExpiresAt(): number;
  stateClearAuth(): void;
  stateIsDeviceRegistered(): boolean;
  stateSetDeviceRegistered(registered: boolean): void;
  stateValidateApiKey(key: string): boolean;
  stateValidateBaseUrl(url: string): boolean;
}

let bindings: NativeSessionBindings | null = null;

export function setNativeSessionBindings(b: NativeSessionBindings | null): void {
  bindings = b;
}

export function getNativeSessionBindings(): NativeSessionBindings | null {
  return bindings;
}

export function requireNativeSessionBindings(): NativeSessionBindings {
  if (!bindings) {
    const err = new Error('native session bindings not registered; ' +
      'host (React Native TurboModule / Node N-API / WASM) must call ' +
      'setNativeSessionBindings() at startup');
    (err as unknown as { code: number }).code = -6;
    throw err;
  }
  return bindings;
}
