/**
 * HybridTypes.ts
 *
 * Public, structured model/backend identity + routing-policy + transcribe
 * result types for the STT hybrid router, plus the proto marshalling the
 * binding hands to commons.
 *
 * Mirrors the Swift `HybridModel.swift` / `HybridRoutingPolicy.swift` and the
 * Kotlin `RACModel` / `Backend` / `RACRouter.RoutingPolicy` catalog so the
 * three SDKs expose the same routing vocabulary and the same wire shape
 * (idl/hybrid_router.proto). Like the Swift binding it uses discriminated
 * unions instead of a class hierarchy.
 *
 * Division of labour — commons owns ALL routing. The policy expressed here is
 * a *declaration* of how the C router should choose between the offline and
 * online candidate; the router (in commons / WASM) owns every filter / rank /
 * cascade decision. This file only:
 *   * lets the caller express filters / cascade / rank as TS values, and
 *   * serializes them to `runanywhere.v1.Hybrid*` proto bytes for the
 *     proto-byte router ABI (rac_stt_hybrid_router_*_proto).
 */

import {
  HybridBackendKind,
  HybridModelDescriptor,
  HybridModelType,
  HybridRank,
  HybridRoutedMetadata,
  HybridRoutingPolicy,
  HybridSttTranscribeRequest,
  HybridSttTranscribeResponse,
} from '@runanywhere/proto-ts/hybrid_router';
import type {
  BatteryFilter,
  ConfidenceCascade,
  CustomFilter,
  HybridCascade,
  HybridFilter,
  HybridRoutingContext,
  HybridSttTranscribeOptions,
} from '@runanywhere/proto-ts/hybrid_router';

// Re-export the wire enums so callers can use them directly without importing
// from `@runanywhere/proto-ts` (the structured-types-as-data rule: provider is
// data, backend is a wire enum).
export { HybridBackendKind, HybridModelType, HybridRank };

// Re-export the generated routing metadata so downstream consumers keep a
// stable `HybridRoutedMetadata` import path from this module. The hand-written
// copy was field-for-field identical to the proto type, so it was deleted in
// favour of the generated one (idl/hybrid_router.proto).
export { HybridRoutedMetadata };

/** Default cloud STT provider when a caller omits one. Mirrors
 * `CloudSTT.defaultProvider` (Swift) / `BACKEND.DEFAULT_PROVIDER` (Kotlin). */
export const DEFAULT_CLOUD_PROVIDER = 'sarvam';

/** Suggested default confidence threshold for an STT confidence cascade.
 * Mirrors `RAC_HYBRID_STT_CONFIDENCE_THRESHOLD` in rac_hybrid_types.h — the
 * router uses the threshold carried in the installed policy; this is only the
 * recommended value to build it with. */
export const HYBRID_STT_CONFIDENCE_THRESHOLD = 0.5;

// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------

/**
 * A hard eligibility predicate. Every filter in a policy must pass for a
 * candidate to survive the filter phase (filters AND-compose). Concrete
 * semantics are evaluated inside commons (NETWORK / Battery against the
 * device-state vtable snapshot; Custom against the registered named
 * predicate). Discriminated union mirroring Swift's `HybridFilter`.
 */
export type HybridFilterSpec =
  | { kind: 'network' }
  | { kind: 'quality'; tier?: number }
  | { kind: 'battery'; minPercent?: number }
  | {
      kind: 'custom';
      name: string;
      description?: string;
      /**
       * Caller-supplied predicate. Registered with commons under `name`
       * via the custom-filter callback table; commons resolves it by name
       * and invokes it once per candidate during filtering. Return `true`
       * to keep the candidate eligible.
       *
       * The predicate runs synchronously on the router's request thread and
       * MUST be fast, reentrant, and side-effect-free.
       */
      check: (modelId: string) => boolean;
    };

/** One-network-filter spec. */
export function networkFilter(): HybridFilterSpec {
  return { kind: 'network' };
}

/** Battery filter: drops the online candidate below `minPercent` (0–100). */
export function batteryFilter(minPercent = 20): HybridFilterSpec {
  return { kind: 'battery', minPercent };
}

/** Named custom filter — the predicate is registered with commons by name. */
export function customFilter(
  name: string,
  check: (modelId: string) => boolean,
  description = '',
): HybridFilterSpec {
  return { kind: 'custom', name, description, check };
}

// ---------------------------------------------------------------------------
// Cascade
// ---------------------------------------------------------------------------

/**
 * A mid-request fallback trigger. At most one cascade per policy. Evaluated
 * inside commons on the primary candidate's confidence signal (and on a
 * primary error, treated as "no confidence"). Mirrors Swift's `HybridCascade`.
 */
export type HybridCascadeSpec = { kind: 'confidence'; threshold: number };

/** Confidence cascade: fall back when the primary scores below `threshold`. */
export function confidenceCascade(
  threshold: number = HYBRID_STT_CONFIDENCE_THRESHOLD,
): HybridCascadeSpec {
  return { kind: 'confidence', threshold };
}

// ---------------------------------------------------------------------------
// Routing policy
// ---------------------------------------------------------------------------

/**
 * The full routing policy attached to a model pair: filters (AND-composed),
 * an optional cascade, and a rank. Defaults to `PREFER_LOCAL_FIRST` with no
 * filters or cascade — i.e. "use the local candidate, fall back to online on
 * hard failure". Mirrors Swift's `HybridRoutingPolicy` /
 * Kotlin's `SimpleRouterPolicy` + `AdvanceRouterPolicy`.
 */
export interface HybridRoutingPolicySpec {
  hardFilters?: HybridFilterSpec[];
  cascade?: HybridCascadeSpec;
  rank?: HybridRank;
}

// ---------------------------------------------------------------------------
// Model descriptor
// ---------------------------------------------------------------------------

/**
 * One side of the hybrid pair. `id` is the resolution key:
 *   * offline (`SHERPA`) — the model id the C model registry resolves so the
 *     engine can load the model files.
 *   * online (`CLOUD`) — the registry id registered via
 *     `CloudSTT.register({ id, provider, model, apiKey })`, which supplies the
 *     provider, model string + credentials.
 *
 * Mirrors Swift's `HybridModel` / Kotlin's `RACModel`.
 */
export interface HybridModelSpec {
  id: string;
  modelType: HybridModelType;
  backend: HybridBackendKind;
  /**
   * Concrete cloud provider when `backend === CLOUD` (e.g. "sarvam"). Empty
   * for non-cloud backends; marshalled into the descriptor's `provider`
   * field (proto tag 4) so the cloud engine selects the HTTP backend.
   */
  provider?: string;
}

/** Convenience for an on-device sherpa model. */
export function offlineSherpa(id: string): HybridModelSpec {
  return {
    id,
    modelType: HybridModelType.HYBRID_MODEL_TYPE_OFFLINE,
    backend: HybridBackendKind.HYBRID_BACKEND_SHERPA,
  };
}

/** Convenience for a cloud model (registered via `CloudSTT.register`). */
export function onlineCloud(
  id: string,
  provider: string = DEFAULT_CLOUD_PROVIDER,
): HybridModelSpec {
  return {
    id,
    modelType: HybridModelType.HYBRID_MODEL_TYPE_ONLINE,
    backend: HybridBackendKind.HYBRID_BACKEND_CLOUD,
    provider,
  };
}

// ---------------------------------------------------------------------------
// Transcribe options + result
// ---------------------------------------------------------------------------

/**
 * STT options carried through the router (mirror of the C `rac_stt_options_t`
 * knobs the router forwards). All optional with backend-default behaviour.
 */
export interface HybridTranscribeOptions {
  /** BCP-47 hint. Empty = backend auto-detect. */
  language?: string;
  /** Sample-rate hint for raw PCM input. 0 = engine default (16000). */
  sampleRate?: number;
  /** `rac_audio_format_enum_t`: 0=PCM, 1=WAV, 2=MP3, 3=OPUS, 4=AAC, 5=FLAC.
   * 0 leaves the format unspecified. */
  audioFormat?: number;
}

/** One transcribe call's outcome through the hybrid STT router. */
export interface HybridTranscribeResult {
  /** Transcript text from the chosen backend. */
  text: string;
  /** BCP-47 language code reported by the backend (empty when none). */
  detectedLanguage: string;
  /** Which side ran, whether it was a fallback, and why the primary failed. */
  routing: HybridRoutedMetadata;
}

// ---------------------------------------------------------------------------
// Proto marshalling (pure: no WASM, no state)
// ---------------------------------------------------------------------------

/** The custom filters in a policy, paired with the name commons looks them up
 * by — extracted so the router can register each predicate with the
 * custom-filter table before installing the policy bytes. */
export interface CustomFilterRegistration {
  name: string;
  check: (modelId: string) => boolean;
}

export function customFiltersOf(
  policy: HybridRoutingPolicySpec,
): CustomFilterRegistration[] {
  return (policy.hardFilters ?? [])
    .filter((f): f is Extract<HybridFilterSpec, { kind: 'custom' }> => f.kind === 'custom')
    .map((f) => ({ name: f.name, check: f.check }));
}

/** Encode a model spec as `runanywhere.v1.HybridModelDescriptor` bytes. */
export function encodeModelDescriptor(model: HybridModelSpec): Uint8Array {
  const descriptor: HybridModelDescriptor = {
    modelId: model.id,
    modelType: model.modelType,
    backend: model.backend,
    provider: model.provider ?? '',
  };
  return HybridModelDescriptor.encode(descriptor).finish();
}

function encodeFilter(filter: HybridFilterSpec): HybridFilter {
  switch (filter.kind) {
    case 'network':
      // Emit `true` explicitly so the oneof case is set on the wire.
      return { network: true };
    case 'quality':
      return { qualityTier: filter.tier ?? 1 };
    case 'battery': {
      const battery: BatteryFilter = { minBatteryPercent: filter.minPercent ?? 20 };
      return { battery };
    }
    case 'custom': {
      const custom: CustomFilter = {
        name: filter.name,
        description: filter.description ?? '',
      };
      return { custom };
    }
  }
}

function encodeCascade(cascade: HybridCascadeSpec): HybridCascade {
  const confidence: ConfidenceCascade = { threshold: cascade.threshold };
  return { confidence };
}

/** Encode a policy spec as `runanywhere.v1.HybridRoutingPolicy` bytes for
 * `rac_stt_hybrid_router_set_policy_proto`. */
export function encodeRoutingPolicy(policy: HybridRoutingPolicySpec): Uint8Array {
  const message: HybridRoutingPolicy = {
    hardFilters: (policy.hardFilters ?? []).map(encodeFilter),
    cascade: policy.cascade ? encodeCascade(policy.cascade) : undefined,
    rank: policy.rank ?? HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST,
  };
  return HybridRoutingPolicy.encode(message).finish();
}

/** Encode a `runanywhere.v1.HybridSttTranscribeRequest`. HybridRoutingContext
 * currently has no fields — device-state lives behind the device-state vtable;
 * the empty (present) message keeps the wire shape stable. */
export function encodeTranscribeRequest(
  audio: Uint8Array,
  options: HybridTranscribeOptions = {},
): Uint8Array {
  const context: HybridRoutingContext = {};
  const sttOptions: HybridSttTranscribeOptions = {
    language: options.language ?? '',
    sampleRate: options.sampleRate ?? 0,
    audioFormat: options.audioFormat ?? 0,
  };
  const request: HybridSttTranscribeRequest = {
    audioBytes: audio,
    context,
    options: sttOptions,
  };
  return HybridSttTranscribeRequest.encode(request).finish();
}

function decodeRoutedMetadata(
  routing: HybridRoutedMetadata | undefined,
): HybridRoutedMetadata {
  // proto3 drops 0.0 on the wire, but commons sends NaN explicitly via the C++
  // encoder when no quality signal exists, so a present 0.0 stays 0.0. When the
  // routing sub-message is entirely absent, default both confidences to NaN.
  return {
    chosenModelId: routing?.chosenModelId ?? '',
    wasFallback: routing?.wasFallback ?? false,
    attemptCount: routing?.attemptCount ?? 0,
    primaryErrorCode: routing?.primaryErrorCode ?? 0,
    primaryErrorMessage: routing?.primaryErrorMessage ?? '',
    confidence: routing?.confidence ?? Number.NaN,
    primaryConfidence: routing?.primaryConfidence ?? Number.NaN,
  };
}

/**
 * Decoded `runanywhere.v1.HybridSttTranscribeResponse`, split into the public
 * result + the native rc/error so the caller can raise an exception on a
 * non-zero rc. Pure: no WASM, no state.
 */
export interface DecodedTranscribeResponse {
  rc: number;
  errorMessage: string;
  result: HybridTranscribeResult;
}

export function decodeTranscribeResponse(bytes: Uint8Array): DecodedTranscribeResponse {
  const response: HybridSttTranscribeResponse = HybridSttTranscribeResponse.decode(bytes);
  return {
    rc: response.rc,
    errorMessage: response.errorMsg ?? '',
    result: {
      text: response.text,
      detectedLanguage: response.detectedLanguage,
      routing: decodeRoutedMetadata(response.routing),
    },
  };
}
