// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Nitro Module spec for the RunAnywhere native bridge. Generated
// TurboModule bindings expose every method here to JS.

import type { HybridObject } from 'react-native-nitro-modules';

export interface RunAnywhereNative
  extends HybridObject<{ ios: 'c++'; android: 'c++' }> {

  /// Core lifecycle
  initialize(apiKey: string, baseUrl: string, environment: number): void;
  shutdown(): void;
  isInitialized(): boolean;

  /// LLM
  llmCreate(modelId: string, modelPath: string, format: number): bigint;
  llmDestroy(session: bigint): void;
  llmGenerate(session: bigint, prompt: string): Promise<string>;
  llmCancel(session: bigint): void;

  /// STT
  sttCreate(modelId: string, modelPath: string): bigint;
  sttDestroy(session: bigint): void;
  sttFeedAudio(session: bigint, pcm: Float32Array, sampleRate: number): void;
  sttFlush(session: bigint): Promise<string>;

  /// TTS
  ttsCreate(modelId: string, modelPath: string): bigint;
  ttsDestroy(session: bigint): void;
  ttsSynthesize(session: bigint, text: string): Promise<Float32Array>;

  /// Auth
  authIsAuthenticated(): boolean;
  authGetAccessToken(): string;
  authHandleAuthenticateResponse(body: string): number;

  /// Telemetry
  telemetryTrack(name: string, propertiesJson: string): number;

  /// RAG
  ragStoreCreate(dim: number): bigint;
  ragStoreDestroy(handle: bigint): void;
  ragStoreAdd(handle: bigint, rowId: string, metaJson: string,
                embedding: Float32Array): number;
  ragStoreSearch(handle: bigint, query: Float32Array, topK: number): string;

  /// Version / build info
  abiVersion(): number;
  buildInfo(): string;
}
