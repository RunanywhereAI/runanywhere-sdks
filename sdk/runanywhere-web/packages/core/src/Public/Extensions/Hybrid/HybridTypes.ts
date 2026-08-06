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
  HybridInferenceMode,
  HybridModelDescriptor,
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
  HybridSttTranscribeOptions,
} from '@runanywhere/proto-ts/hybrid_router';

/**
 * Plugin-registry engine name for a hybrid candidate — a free-form string
 * (`rac_plugin_find_for_engine`'s lookup key), not a closed enum.
 * `HybridBackendKind` was deleted outright (idl/hybrid_router.proto):
 * `HybridModelDescriptor.backend` + `.provider` were replaced by a single
 * `engine: string` field so a new backend name is not a proto change. Kept
 * as a type alias (not a re-exported proto enum) so existing call sites that
 * imported `HybridBackendKind` as a type keep compiling; the members below
 * are the only values commons currently pins on.
 */
export type HybridBackendKind = string;
export const HybridBackendKind = {
  UNSPECIFIED: '' as HybridBackendKind,
  LLAMACPP: 'llamacpp' as HybridBackendKind,
  /** On-device speech (sherpa-onnx Whisper / Zipformer / Paraformer). */
  SHERPA: 'sherpa' as HybridBackendKind,
  /**
   * Generic cloud speech (the "cloud" engine). The concrete HTTP provider
   * (Sarvam first) is resolved by the cloud engine from its own config, not
   * carried on the descriptor anymore.
   */
  CLOUD: 'cloud' as HybridBackendKind,
} as const;

// Re-export the generated routing metadata so downstream consumers keep a
// stable `HybridRoutedMetadata` import path from this module. The hand-written
// copy was field-for-field identical to the proto type, so it was deleted in
// favour of the generated one (idl/hybrid_router.proto).
export { HybridRoutedMetadata };

/** Default cloud STT provider when a caller omits one. Mirrors
 * `Cloud.defaultProvider` (Swift) / `BACKEND.DEFAULT_PROVIDER` (Kotlin). */
export const DEFAULT_CLOUD_PROVIDER = 'sarvam';

/** Suggested default confidence threshold for an STT confidence cascade.
 * Mirrors `RAC_HYBRID_STT_CONFIDENCE_THRESHOLD` in rac_hybrid_types.h — the
 * router uses the threshold carried in the installed policy; this is only the
 * recommended value to build it with. There is no longer a generated
 * `hybridDefaults` pool entry for this (idl/hybrid_router.proto's
 * `ConfidenceCascade.threshold` carries an annotated default of 0.5, but
 * `idl/codegen` does not emit a JS defaults pool for this message), so the
 * commons header constant is inlined here directly, matching Swift's
 * `RAHybridSTTConfidenceThreshold`. */
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
 *
 * The `'quality'` case is reserved: `HybridFilter`'s proto oneof only has
 * network/battery/custom arms (idl/hybrid_router.proto) -- there has never
 * been a wire slot for a quality tier. Commons treats it as a no-op today;
 * kept for wire/API parity with Kotlin/Swift (`.quality(tier:)`).
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
 * an optional cascade, and a rank. `preferLocal` defaults to `true` (prefer the
 * local candidate first) with no filters or cascade — i.e. "use the local
 * candidate, fall back to online on hard failure". Mirrors Swift's
 * `HybridRoutingPolicy` / Kotlin's `SimpleRouterPolicy` + `AdvanceRouterPolicy`.
 *
 * `preferLocal` keeps its pre-realignment public name/semantics; only the
 * proto-building step below maps it onto the wire's `HybridInferenceMode`
 * (idl/hybrid_router.proto renamed the boolean `prefer_local` to a 4-value
 * `mode` enum plus an ordered `models` list). Commons
 * (rac_stt_hybrid_router_proto.cpp) has not wired up a `models` consumer yet
 * -- it still drives routing off the two separately registered
 * offline/online service descriptors (`setPair`'s two `_set_*_service_proto`
 * calls) and reads only `mode` from this policy to decide rank direction.
 * Anything other than PREFER_IN_CLOUD/ONLY_IN_CLOUD is treated as
 * local-first, so `preferLocal: true` maps to `PREFER_ON_DEVICE` and `false`
 * to `PREFER_IN_CLOUD`, preserving the exact pre-realignment behavior.
 */
export interface HybridRoutingPolicySpec {
  hardFilters?: HybridFilterSpec[];
  cascade?: HybridCascadeSpec;
  /** Prefer the local candidate first when true (the default). */
  preferLocal?: boolean;
}

// ---------------------------------------------------------------------------
// Model descriptor
// ---------------------------------------------------------------------------

/**
 * One side of the hybrid pair. `id` is the resolution key:
 *   * offline (`SHERPA`) — the model id the C model registry resolves so the
 *     engine can load the model files.
 *   * online (`CLOUD`) — the registry id registered via
 *     `Cloud.register({ id, provider, model, apiKey })`, which supplies the
 *     provider, model string + credentials.
 *
 * Mirrors Swift's `HybridModel` / Kotlin's `RACModel`.
 */
export interface HybridModelSpec {
  id: string;
  /**
   * True for an on-device (offline) model, false for a cloud (online) one.
   * Marshalled into the descriptor's `isOnDevice` field (idl/hybrid_router.proto
   * renamed `is_local` -> `is_on_device`).
   */
  isLocal: boolean;
  backend: HybridBackendKind;
}

/** Convenience for an on-device sherpa model. */
export function offlineSherpa(id: string): HybridModelSpec {
  return {
    id,
    isLocal: true,
    backend: HybridBackendKind.SHERPA,
  };
}

/**
 * Convenience for a cloud model (registered via `Cloud.register`). The
 * concrete HTTP provider (Sarvam first) is resolved by the cloud engine from
 * the config the caller registered — it no longer rides on this descriptor
 * (idl/hybrid_router.proto deleted `HybridModelDescriptor.provider` outright).
 */
export function onlineCloud(id: string): HybridModelSpec {
  return {
    id,
    isLocal: false,
    backend: HybridBackendKind.CLOUD,
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
  /**
   * Container the bytes are already in
   * (`@runanywhere/proto-ts/model_types` `AudioFormat` numeric value).
   * `HybridSttTranscribeOptions.audioFormat` was retyped from an untyped
   * int32 to the shared `AudioFormat` enum (idl/hybrid_router.proto); the
   * numeric values are unchanged. 0 leaves the format unspecified (headerless
   * PCM16, which commons wraps in a WAV container).
   */
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

/**
 * Encode a model spec as `runanywhere.v1.HybridModelDescriptor` bytes.
 * `HybridModelDescriptor.provider` was deleted outright and `.backend`
 * (the closed `HybridBackendKind` enum) was replaced by a single free-form
 * `engine: string` field carrying the same plugin-registry lookup key
 * (idl/hybrid_router.proto).
 */
export function encodeModelDescriptor(model: HybridModelSpec): Uint8Array {
  const descriptor: HybridModelDescriptor = {
    modelId: model.id,
    isOnDevice: model.isLocal,
    engine: model.backend,
  };
  return HybridModelDescriptor.encode(descriptor).finish();
}

function encodeFilter(filter: HybridFilterSpec): HybridFilter {
  switch (filter.kind) {
    case 'network':
      // Emit `true` explicitly so the oneof case is set on the wire.
      return { network: true };
    case 'quality':
      // HybridFilter's oneof only has network/battery/custom arms -- there
      // has never been a wire slot for a quality tier. No-op, matching
      // Swift's `.quality` encode case.
      return {};
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
    // preferLocal -> mode: see the HybridRoutingPolicySpec doc comment above.
    mode: (policy.preferLocal ?? true)
      ? HybridInferenceMode.HYBRID_INFERENCE_MODE_PREFER_ON_DEVICE
      : HybridInferenceMode.HYBRID_INFERENCE_MODE_PREFER_IN_CLOUD,
    attemptTimeoutMs: 0,
    models: [],
  };
  return HybridRoutingPolicy.encode(message).finish();
}

/**
 * Encode a `runanywhere.v1.HybridSttTranscribeRequest`. `HybridRoutingContext`
 * / `HybridSttTranscribeRequest.context` were deleted outright
 * (idl/hybrid_router.proto): device-state still lives entirely behind the
 * `rac_hybrid_device_state` vtable, so there is no per-call context left to
 * set.
 */
export function encodeTranscribeRequest(
  audio: Uint8Array,
  options: HybridTranscribeOptions = {},
): Uint8Array {
  const sttOptions: HybridSttTranscribeOptions = {
    language: options.language ?? '',
    sampleRate: options.sampleRate ?? 0,
    audioFormat: options.audioFormat ?? 0,
  };
  const request: HybridSttTranscribeRequest = {
    audioBytes: audio,
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
    servedOnDevice: routing?.servedOnDevice ?? false,
  };
}

/**
 * Decoded `runanywhere.v1.HybridSttTranscribeResponse`, split into the public
 * result + the native rc so the caller can raise an exception on a non-zero
 * rc. Pure: no WASM, no state.
 *
 * `HybridSttTranscribeResponse.errorMsg` was deleted outright
 * (idl/hybrid_router.proto): the response now carries only the bare `rc` on
 * failure, with no human-readable message field.
 */
export interface DecodedTranscribeResponse {
  rc: number;
  result: HybridTranscribeResult;
}

export function decodeTranscribeResponse(bytes: Uint8Array): DecodedTranscribeResponse {
  const response: HybridSttTranscribeResponse = HybridSttTranscribeResponse.decode(bytes);
  return {
    rc: response.rc,
    result: {
      text: response.text,
      detectedLanguage: response.detectedLanguage,
      routing: decodeRoutedMetadata(response.routing),
    },
  };
}
