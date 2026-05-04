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

import * as sttHelpers from './stt';
import * as ttsHelpers from './tts';
import * as vadHelpers from './vad';
import * as visionLanguageHelpers from './visionLanguage';
import * as ragHelpers from './rag';
import * as loraHelpers from './lora';
import * as diffusionHelpers from './diffusion';
import * as structuredOutputHelpers from './structuredOutput';
import * as voiceAgentHelpers from './voiceAgent';

export {
  sttHelpers,
  ttsHelpers,
  vadHelpers,
  visionLanguageHelpers,
  ragHelpers,
  loraHelpers,
  diffusionHelpers,
  structuredOutputHelpers,
  voiceAgentHelpers,
};
