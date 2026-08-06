/**
 * HybridRoutingPolicy.ts
 *
 * Public, structured routing-policy types for the STT hybrid router, plus the
 * proto-byte marshalling the binding hands to commons.
 *
 * The policy is a *declaration* of how the C router should choose between the
 * offline and online candidate; the router (in commons) owns every routing /
 * cascade / rank decision. This file only:
 *   - lets the caller express filters / cascade / rank as TS values, and
 *   - serialises them to `runanywhere.v1.HybridRoutingPolicy` bytes (via the
 *     generated proto-ts codec) for `rac_stt_hybrid_router_set_policy_proto`.
 *
 * Mirrors the Kotlin RACRouter.RoutingPolicy catalog and the Swift
 * HybridRoutingPolicy, using TS discriminated unions instead of a class
 * hierarchy. Custom filters carry only a NAME on the wire; the predicate is
 * registered with commons separately so the router owns the whole filter phase.
 */

import {
  HybridInferenceMode,
  HybridRoutingPolicy as HybridRoutingPolicyProto,
  type HybridFilter as HybridFilterProto,
} from '@runanywhere/proto-ts/hybrid_router';
import { confidenceCascadeDefaults } from '@runanywhere/proto-ts/convenience/hybrid_router_convenience';
import { encodeProtoMessage } from '../../../services/ProtoWire';

/**
 * A caller-supplied eligibility predicate. Registered with commons under
 * `name`; commons resolves it by name and invokes it once per candidate during
 * filtering. Return `true` to keep the candidate eligible.
 *
 * The predicate runs while commons routes a transcribe request — keep it fast.
 * It may be async, but the native side blocks the routing thread on it, so
 * avoid long-running work.
 */
export type CustomFilterCheck = (
  candidateModelId: string
) => boolean | Promise<boolean>;

/**
 * A hard eligibility filter. Every filter in a policy must pass for a candidate
 * to survive the filter phase (filters AND-compose). Semantics are evaluated
 * inside commons (NETWORK / Battery against the device-state vtable snapshot;
 * Custom against the registered named predicate).
 */
export type HybridFilter =
  | {
      /** Drops the online candidate when the host has no network. */
      readonly kind: 'network';
    }
  | {
      /** Drops the online candidate when the device battery is below `minPercent`. */
      readonly kind: 'battery';
      readonly minPercent: number;
    }
  | {
      /** Caller-supplied named predicate (see {@link CustomFilterCheck}). */
      readonly kind: 'custom';
      readonly name: string;
      readonly description: string;
      readonly check: CustomFilterCheck;
    };

/**
 * Filter constructors mirroring the Kotlin RoutingPolicy catalog.
 *
 * `quality(tier)` is removed: `HybridFilter.quality_tier` (the reserved,
 * always-no-op oneof arm it built) is deleted from `hybrid_router.proto`
 * outright — there was never a wire slot to carry it, and now there is none
 * left even for parity.
 */
export const Filters = {
  /** Drops online candidates when the device has no network. */
  network(): HybridFilter {
    return { kind: 'network' };
  },
  /** Drops online candidates when the device is below `minPercent` battery. */
  battery(minPercent = 20): HybridFilter {
    return { kind: 'battery', minPercent };
  },
  /** Caller-supplied named eligibility predicate. */
  custom(name: string, description: string, check: CustomFilterCheck): HybridFilter {
    return { kind: 'custom', name, description, check };
  },
};

/**
 * A mid-request fallback trigger. At most one cascade per policy. Evaluated
 * inside commons on the primary candidate's confidence signal (and on a primary
 * error, treated as "no confidence").
 */
export type HybridCascade = {
  /**
   * Fall back to the secondary candidate when the primary's confidence falls
   * below `threshold` (`[0..1]`), or when the primary errors.
   */
  readonly kind: 'confidence';
  readonly threshold: number;
};

/**
 * Suggested default confidence threshold for an STT confidence cascade.
 *
 * `defaults/pool.ts`'s `hybridDefaults` is deleted outright — its one field
 * duplicated `hybrid_router.ConfidenceCascade.threshold` — so this now reads
 * that field's own generated default directly. The router uses the threshold
 * carried in the installed policy; this is only the recommended value to
 * build it with.
 */
export const HYBRID_STT_CONFIDENCE_THRESHOLD = confidenceCascadeDefaults().threshold;

/** Cascade constructor. */
export const Cascades = {
  confidence(threshold: number = HYBRID_STT_CONFIDENCE_THRESHOLD): HybridCascade {
    return { kind: 'confidence', threshold };
  },
};

/**
 * The full routing policy attached to a model pair: filters (AND-composed), an
 * optional cascade, and a rank preference. Defaults to "prefer local, fall back
 * to online on hard failure" (`preferLocal: true`, no filters or cascade).
 */
export interface HybridRoutingPolicy {
  hardFilters?: HybridFilter[];
  cascade?: HybridCascade;
  /** Prefer the local (offline) candidate first. Defaults to true. */
  preferLocal?: boolean;
}

/** The custom filters in a policy, with their registered name + predicate. */
export function customFiltersOf(
  policy: HybridRoutingPolicy
): Array<{ name: string; check: CustomFilterCheck }> {
  return (policy.hardFilters ?? [])
    .filter((f): f is Extract<HybridFilter, { kind: 'custom' }> => f.kind === 'custom')
    .map((f) => ({ name: f.name, check: f.check }));
}

function filterToProto(filter: HybridFilter): HybridFilterProto {
  switch (filter.kind) {
    case 'network':
      return { network: true } as HybridFilterProto;
    case 'battery':
      return {
        battery: { minBatteryPercent: filter.minPercent },
      } as HybridFilterProto;
    case 'custom':
      return {
        custom: { name: filter.name, description: filter.description },
      } as HybridFilterProto;
  }
}

/**
 * Encode a policy as `runanywhere.v1.HybridRoutingPolicy` bytes for
 * `rac_stt_hybrid_router_set_policy_proto`. Pure: no FFI, no state. The custom
 * filters' predicates are NOT encoded — only their name/description cross the
 * wire; the router resolves the predicate via the commons callback table.
 *
 * The boolean `preferLocal` is deleted from the wire outright, replaced by
 * `HybridInferenceMode` (Firebase AI Logic / Android `InferenceMode`
 * vocabulary): `PREFER_IN_CLOUD` ranks online first, everything else
 * (including the proto3 zero, `UNSPECIFIED`) ranks on-device first — see
 * `rac_stt_hybrid_router_proto.cpp`'s `parse_policy`. The public
 * `preferLocal` knob and its `true` default are kept unchanged; only the
 * internal wire mapping inverts through `mode`.
 */
export function encodeHybridRoutingPolicy(policy: HybridRoutingPolicy): ArrayBuffer {
  const preferLocal = policy.preferLocal ?? true;
  const message = HybridRoutingPolicyProto.fromPartial({
    hardFilters: (policy.hardFilters ?? []).map(filterToProto),
    cascade:
      policy.cascade != null
        ? { confidence: { threshold: policy.cascade.threshold } }
        : undefined,
    mode: preferLocal
      ? HybridInferenceMode.HYBRID_INFERENCE_MODE_PREFER_ON_DEVICE
      : HybridInferenceMode.HYBRID_INFERENCE_MODE_PREFER_IN_CLOUD,
  });
  return encodeProtoMessage(message, HybridRoutingPolicyProto);
}
