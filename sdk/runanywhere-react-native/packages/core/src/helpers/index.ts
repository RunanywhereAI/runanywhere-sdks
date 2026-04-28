/**
 * helpers/
 *
 * Phase C-prime ergonomic helpers — TypeScript's flat-namespace analogue of
 * the Kotlin / Swift extension methods. These free functions augment the
 * proto-encoded types from `@runanywhere/proto-ts/*` with default factories
 * and validation predicates so consumers can stay on the canonical wire
 * shape without writing the same `proto.create({...})` boilerplate at every
 * call site.
 *
 * Each module re-exports its modality's proto types so consumers can do:
 *
 *     import { sttDefaults, isSTTConfigValid, STTConfiguration } from '@runanywhere/core/helpers/stt';
 *
 * and never need to touch `@runanywhere/proto-ts` directly.
 */

export * as sttHelpers from './stt';
export * as ttsHelpers from './tts';
export * as vadHelpers from './vad';
export * as visionLanguageHelpers from './visionLanguage';
export * as ragHelpers from './rag';
export * as loraHelpers from './lora';
export * as diffusionHelpers from './diffusion';
export * as structuredOutputHelpers from './structuredOutput';
export * as voiceAgentHelpers from './voiceAgent';
