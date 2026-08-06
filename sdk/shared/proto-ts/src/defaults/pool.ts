// SPDX-License-Identifier: Apache-2.0
//
// GENERATED FILE — DO NOT EDIT.
// Regenerate with: idl/codegen/generate_defaults_pool.py
//
// Values come from `(runanywhere.v1.rac_default)` annotations in
// idl/sdk_defaults.proto. That file is the single declaration of every default
// here; the C header and the other three SDK languages are generated from
// the same annotations, so editing this copy only desynchronizes one SDK.

/** Central default pool. Read these instead of retyping a literal. */

export const networkDefaults = Object.freeze({
  requestTimeoutMs: 60000 as number,
  resourceTimeoutMs: 600000 as number,
  streamingTimeoutMs: 86400000 as number,
  adapterTimeoutMs: 30000 as number,
  connectTimeoutMs: 30000 as number,
  streamChunkBytes: 262144 as number,
  maxRetries: 3 as number,
  retryBackoffBaseMs: 100 as number,
});

export const connectDefaults = Object.freeze({
  connectTimeoutMs: 5000 as number,
  generationReadTimeoutMs: 120000 as number,
});

export const audioCaptureDefaults = Object.freeze({
  micSampleRateHz: 16000 as number,
  micChannels: 1 as number,
  micChannelCapacity: 128 as number,
  ttsSampleRateHz: 22050 as number,
});

export const voiceAgentDefaults = Object.freeze({
  maxTokens: 96 as number,
  temperature: 0.0 as number,
  defaultVadModelId: "silero-vad" as string,
  speechRmsThreshold: 0.015 as number,
  speechFloorMultiplier: 2.0 as number,
});

export const workerDefaults = Object.freeze({
  handshakeTimeoutMs: 10000 as number,
  backendInitTimeoutMs: 120000 as number,
});

export const fFIDefaults = Object.freeze({
  pathBufferBytes: 1024 as number,
});

export const environmentDefaults = Object.freeze({
  productionBaseUrl: "https://api.runanywhere.ai" as string,
  developmentBaseUrl: "https://dev-api.runanywhere.ai" as string,
  developmentPlaceholderUrl: "https://dev.runanywhere.local" as string,
});

export const structuredOutputDefaults = Object.freeze({
  maxTokens: 512 as number,
  temperature: 0.0 as number,
});

export const storageDefaults = Object.freeze({
  contextLength: 2048 as number,
});
