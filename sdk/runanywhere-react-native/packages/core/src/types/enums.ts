/**
 * RunAnywhere React Native SDK — Enums.
 *
 * Public enums are proto-canonical. This module keeps only tiny RN helper
 * values that do not have an IDL counterpart.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/
 */

// ============================================================================
// Re-exported from @runanywhere/proto-ts — single source of truth.
// ============================================================================

export {
  // sdk_events.proto
  SDKComponent,
  EventDestination,
} from '@runanywhere/proto-ts/sdk_events';

export {
  // component_types.proto — shared lifecycle + categorization
  ComponentLifecycleState,
  EventCategory,
} from '@runanywhere/proto-ts/component_types';

export {
  // errors.proto — severity taxonomy
  ErrorSeverity,
} from '@runanywhere/proto-ts/errors';

export {
  // hardware_profile.proto — acceleration preference
  AccelerationPreference,
} from '@runanywhere/proto-ts/hardware_profile';

export {
  // llm_options.proto
  ExecutionTarget,
} from '@runanywhere/proto-ts/llm_options';

export {
  // model_types.proto — the canonical option/format/category enums.
  AudioFormat,
  InferenceFramework,
  ModelArtifactType,
  ModelCategory,
  ModelFormat,
  RoutingPolicy,
  SDKEnvironment,
  ModelSource,
} from '@runanywhere/proto-ts/model_types';

// ============================================================================
// RN-only survivors (no proto equivalent — see audit `02_PARITY.md` §"Type-
// coverage gaps (no proto exists)").
// ============================================================================

/**
 * Framework modality (input/output types). RN-local — used by
 * model-registry helpers that have no proto counterpart.
 */
export enum FrameworkModality {
  TextToText = 'textToText',
  VoiceToText = 'voiceToText',
  TextToVoice = 'textToVoice',
  ImageToText = 'imageToText',
  TextToImage = 'textToImage',
  Multimodal = 'multimodal',
}

/**
 * Human-readable display names for model categories. RN-local helper;
 * proto exposes labels via numeric → string conversion only. Keyed by
 * the proto enum values via `ModelCategory[i]` after the re-export.
 */
import type { ModelCategory as ModelCategoryProto } from '@runanywhere/proto-ts/model_types';
export const ModelCategoryDisplayNames: Partial<Record<ModelCategoryProto, string>> = {};

/**
 * Privacy mode for data handling. RN-local — describes how the SDK
 * routes telemetry, not part of the proto API surface.
 */
export enum PrivacyMode {
  Public = 'public',
  Private = 'private',
  Restricted = 'restricted',
}
