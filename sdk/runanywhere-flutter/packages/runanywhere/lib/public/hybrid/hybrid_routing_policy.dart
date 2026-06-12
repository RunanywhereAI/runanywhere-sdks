// SPDX-License-Identifier: Apache-2.0
//
// hybrid_routing_policy.dart — Public, structured routing-policy types for the
// STT hybrid router, plus the proto marshalling the binding hands to commons.
//
// The policy is a DECLARATION of how the C router should choose between the
// offline and online candidate; the router (in commons) owns every routing /
// cascade / rank decision. This file only:
//   * lets the caller express filters / cascade / rank as Dart values, and
//   * serializes them to `runanywhere.v1.HybridRoutingPolicy` bytes (via the
//     generated Dart proto) for rac_stt_hybrid_router_set_policy_proto.
//
// Mirrors the Kotlin RACRouter.RoutingPolicy catalog + HybridRouterProto and
// the Swift HybridRoutingPolicy enums, using Dart sealed classes.

import 'dart:typed_data';

import 'package:runanywhere/generated/hybrid_router.pb.dart' as pb;
import 'package:runanywhere/generated/hybrid_router.pbenum.dart'
    show HybridRank;

/// Suggested default confidence threshold for an STT confidence cascade.
/// Mirrors `RAC_HYBRID_STT_CONFIDENCE_THRESHOLD` in rac_hybrid_types.h — the
/// router uses the threshold carried in the installed policy; this is only the
/// recommended value to build it with.
const double kHybridSttConfidenceThreshold = 0.5;

/// A hard eligibility predicate. Every filter in a policy must pass for a
/// candidate to survive the filter phase (filters AND-compose). Concrete
/// semantics are evaluated inside commons (NETWORK / Battery against the
/// device-state vtable snapshot; Custom against the registered named predicate).
sealed class HybridFilter {
  const HybridFilter();

  /// Drops the online candidate when the host has no network. The offline
  /// candidate is unaffected. Network state is read from the device-state
  /// vtable on every request — never passed in per-call.
  const factory HybridFilter.network() = HybridNetworkFilter;

  /// Requires the candidate to declare at least [tier]. Reserved: v1
  /// descriptors carry no quality tier, so commons treats this as a no-op
  /// today. Kept for wire/API parity with Kotlin/Swift.
  const factory HybridFilter.quality({int tier}) = HybridQualityFilter;

  /// Drops the online candidate when the device battery is below [minPercent]
  /// (0–100). The offline candidate is unaffected.
  const factory HybridFilter.battery({int minPercent}) = HybridBatteryFilter;

  /// A caller-supplied named predicate. The closure is registered with commons
  /// under [name] via `rac_hybrid_register_custom_filter`; commons resolves it
  /// by name and invokes it once per candidate during filtering. Return `true`
  /// to keep the candidate eligible.
  ///
  /// The closure runs synchronously on the router's request thread and may be
  /// invoked concurrently — keep it fast, reentrant, and side-effect-free.
  const factory HybridFilter.custom({
    required String name,
    required bool Function(String modelId) check,
    String description,
  }) = HybridCustomFilter;
}

/// NETWORK hard filter. See [HybridFilter.network].
class HybridNetworkFilter extends HybridFilter {
  /// Build a NETWORK filter.
  const HybridNetworkFilter();
}

/// QUALITY hard filter. See [HybridFilter.quality].
class HybridQualityFilter extends HybridFilter {
  /// Build a QUALITY filter requiring at least [tier].
  const HybridQualityFilter({this.tier = 1});

  /// Minimum tier the candidate must declare.
  final int tier;
}

/// BATTERY hard filter. See [HybridFilter.battery].
class HybridBatteryFilter extends HybridFilter {
  /// Build a BATTERY filter dropping cloud candidates below [minPercent].
  const HybridBatteryFilter({this.minPercent = 20});

  /// Minimum battery percentage (0–100) to keep the online candidate eligible.
  final int minPercent;
}

/// CUSTOM hard filter. See [HybridFilter.custom].
class HybridCustomFilter extends HybridFilter {
  /// Build a CUSTOM filter; [name] doubles as the wire identity.
  const HybridCustomFilter({
    required this.name,
    required this.check,
    this.description = '',
  });

  /// Wire identity + log label; must be non-empty and unique within a policy.
  final String name;

  /// Human-readable purpose for the filter.
  final String description;

  /// Predicate `(modelId) -> bool` deciding eligibility for the given candidate.
  final bool Function(String modelId) check;
}

/// A mid-request fallback trigger. At most one cascade per policy. Evaluated
/// inside commons on the primary candidate's confidence signal (and on a
/// primary error, treated as "no confidence").
sealed class HybridCascade {
  const HybridCascade();

  /// Fall back to the secondary candidate when the primary's confidence falls
  /// below [threshold] (`[0..1]`), or when the primary errors.
  const factory HybridCascade.confidence(double threshold) =
      HybridConfidenceCascade;
}

/// Confidence cascade. See [HybridCascade.confidence].
class HybridConfidenceCascade extends HybridCascade {
  /// Build a confidence cascade firing below [threshold].
  const HybridConfidenceCascade(this.threshold);

  /// Confidence value `[0..1]` below which the cascade fires.
  final double threshold;
}

/// Comparator that orders eligible candidates. Exactly one rank per policy.
/// Wire values match `HybridRank` in hybrid_router.proto.
enum HybridRankOrder {
  /// Prefer the offline candidate when both are eligible.
  preferLocalFirst(HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST),

  /// Prefer the online candidate when both are eligible.
  preferOnlineFirst(HybridRank.HYBRID_RANK_PREFER_ONLINE_FIRST);

  const HybridRankOrder(this.proto);

  /// The generated proto enum this maps to on the wire.
  final HybridRank proto;
}

/// The full routing policy attached to a model pair: filters (AND-composed),
/// an optional cascade, and a rank. Defaults to [HybridRankOrder.preferLocalFirst]
/// with no filters or cascade — i.e. "use the local candidate, fall back to
/// online on hard failure".
class HybridRoutingPolicy {
  /// Build a composed policy. Mirrors Kotlin's AdvanceRouterPolicy.
  const HybridRoutingPolicy({
    this.hardFilters = const <HybridFilter>[],
    this.cascade,
    this.rank = HybridRankOrder.preferLocalFirst,
  });

  /// Filters AND-composed against every candidate.
  final List<HybridFilter> hardFilters;

  /// Optional mid-request fallback trigger.
  final HybridCascade? cascade;

  /// Comparator (defaults to prefer-local-first).
  final HybridRankOrder rank;

  /// One-filter policy. Mirrors Kotlin's `SimpleRouterPolicy(filter)`.
  static HybridRoutingPolicy filter(HybridFilter filter) =>
      HybridRoutingPolicy(hardFilters: <HybridFilter>[filter]);

  /// One-cascade policy (no filters, default rank).
  static HybridRoutingPolicy cascadeOnly(HybridCascade cascade) =>
      HybridRoutingPolicy(cascade: cascade);

  /// Rank-only policy.
  static HybridRoutingPolicy ranked(HybridRankOrder rank) =>
      HybridRoutingPolicy(rank: rank);

  /// The custom filters in this policy, paired with the name commons looks them
  /// up by. Extracted so the router can register each predicate with
  /// `rac_hybrid_register_custom_filter` before installing the policy bytes.
  /// (The closure itself never crosses the FFI; only the name does, on the wire.)
  List<HybridCustomFilter> get customFilters =>
      hardFilters.whereType<HybridCustomFilter>().toList(growable: false);

  /// Encode this policy as `runanywhere.v1.HybridRoutingPolicy` bytes for
  /// `rac_stt_hybrid_router_set_policy_proto`. Pure: no FFI, no state.
  Uint8List toProtoBytes() {
    final policy = pb.HybridRoutingPolicy(
      hardFilters: hardFilters.map(_encodeFilter),
      cascade: cascade == null ? null : _encodeCascade(cascade!),
      rank: rank.proto,
    );
    return policy.writeToBuffer();
  }

  static pb.HybridFilter _encodeFilter(HybridFilter filter) {
    switch (filter) {
      case HybridNetworkFilter():
        return pb.HybridFilter(network: true);
      case HybridQualityFilter(:final tier):
        return pb.HybridFilter(qualityTier: tier);
      case HybridBatteryFilter(:final minPercent):
        return pb.HybridFilter(
          battery: pb.BatteryFilter(minBatteryPercent: minPercent),
        );
      case HybridCustomFilter(:final name, :final description):
        return pb.HybridFilter(
          custom: pb.CustomFilter(name: name, description: description),
        );
    }
  }

  static pb.HybridCascade _encodeCascade(HybridCascade cascade) {
    switch (cascade) {
      case HybridConfidenceCascade(:final threshold):
        return pb.HybridCascade(
          confidence: pb.ConfidenceCascade(threshold: threshold),
        );
    }
  }
}
