"use strict";
// SPDX-License-Identifier: Apache-2.0
//
// GENERATED FILE — DO NOT EDIT.
// Regenerate with: idl/codegen/generate_defaults_pool.py
//
// Values come from `(runanywhere.v1.rac_default)` annotations in
// idl/sdk_defaults.proto. That file is the single declaration of every default
// here; the C header and the other three SDK languages are generated from
// the same annotations, so editing this copy only desynchronizes one SDK.
Object.defineProperty(exports, "__esModule", { value: true });
exports.storageDefaults = exports.structuredOutputDefaults = exports.environmentDefaults = exports.fFIDefaults = exports.workerDefaults = exports.hybridDefaults = exports.voiceAgentDefaults = exports.audioCaptureDefaults = exports.connectDefaults = exports.networkDefaults = void 0;
/** Central default pool. Read these instead of retyping a literal. */
exports.networkDefaults = Object.freeze({
    requestTimeoutMs: 60000,
    resourceTimeoutMs: 600000,
    streamingTimeoutMs: 86400000,
    adapterTimeoutMs: 30000,
    connectTimeoutMs: 30000,
    streamChunkBytes: 262144,
    maxRetries: 3,
    retryBackoffBaseMs: 100,
});
exports.connectDefaults = Object.freeze({
    connectTimeoutMs: 5000,
    generationReadTimeoutMs: 120000,
});
exports.audioCaptureDefaults = Object.freeze({
    micSampleRateHz: 16000,
    micChannels: 1,
    micChannelCapacity: 128,
    micTapBufferFrames: 4096,
    ttsSampleRateHz: 22050,
});
exports.voiceAgentDefaults = Object.freeze({
    maxTokens: 96,
    temperature: 0.0,
    defaultVadModelId: "silero-vad",
    speechRmsThreshold: 0.015,
    speechFloorMultiplier: 2.0,
});
exports.hybridDefaults = Object.freeze({
    sttConfidenceThreshold: 0.5,
});
exports.workerDefaults = Object.freeze({
    handshakeTimeoutMs: 10000,
    backendInitTimeoutMs: 120000,
});
exports.fFIDefaults = Object.freeze({
    pathBufferBytes: 1024,
});
exports.environmentDefaults = Object.freeze({
    productionBaseUrl: "https://api.runanywhere.ai",
    developmentBaseUrl: "https://dev-api.runanywhere.ai",
    developmentPlaceholderUrl: "https://dev.runanywhere.local",
});
exports.structuredOutputDefaults = Object.freeze({
    maxTokens: 512,
    temperature: 0.0,
});
exports.storageDefaults = Object.freeze({
    contextLength: 2048,
});
