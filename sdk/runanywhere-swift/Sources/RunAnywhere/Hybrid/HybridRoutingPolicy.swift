//
//  HybridRoutingPolicy.swift
//  RunAnywhere
//
//  Public, structured routing-policy types for the STT hybrid router, plus
//  the proto-byte marshalling the binding hands to commons.
//
//  The policy is a *declaration* of how the C router should choose between the
//  offline and online candidate; the router (in commons) owns every routing /
//  cascade / rank decision. This file only:
//    * lets the caller express filters / cascade / rank as Swift values, and
//    * serializes them to `runanywhere.v1.HybridRoutingPolicy` bytes for
//      `rac_stt_hybrid_router_set_policy_proto`.
//
//  Mirrors the Kotlin RACRouter.RoutingPolicy catalog (sdk/runanywhere-kotlin/
//  .../public/hybrid/RACRouter.kt) so the two SDKs expose the same routing
//  vocabulary, but uses Swift enums-with-associated-values instead of a class
//  hierarchy.
//

import Foundation
import SwiftProtobuf

// MARK: - Filter

/// A hard eligibility predicate. Every filter in a policy must pass for a
/// candidate to survive the filter phase (filters AND-compose). Concrete
/// semantics are evaluated inside commons (NETWORK / Battery against the
/// device-state vtable snapshot; Custom against the registered named
/// predicate).
public enum HybridFilter: Sendable {
    /// Drops the online candidate when the host has no network. The offline
    /// candidate is unaffected. Network state is read from the device-state
    /// vtable on every request — never passed in per-call.
    case network

    /// Requires the candidate to declare at least `tier`. Reserved: v1
    /// descriptors carry no quality tier, so commons treats this as a no-op
    /// today. Kept for wire/API parity with Kotlin.
    case quality(tier: Int32 = 1)

    /// Drops the online candidate when the device battery is below
    /// `minPercent` (0–100). The offline candidate is unaffected.
    case battery(minPercent: Int32 = 20)

    /// A caller-supplied named predicate. The closure is registered with
    /// commons under `name` via `rac_hybrid_register_custom_filter`; commons
    /// resolves it by name and invokes it once per candidate during filtering.
    /// Return `true` to keep the candidate eligible.
    ///
    /// The closure runs synchronously on the router's request thread and may
    /// be invoked concurrently — keep it fast, reentrant, and side-effect-free.
    case custom(name: String, description: String = "", check: @Sendable (_ modelId: String) -> Bool)
}

// MARK: - Cascade

/// A mid-request fallback trigger. At most one cascade per policy. Evaluated
/// inside commons on the primary candidate's confidence signal (and on a
/// primary error, treated as "no confidence").
public enum HybridCascade: Sendable {
    /// Fall back to the secondary candidate when the primary's confidence
    /// falls below `threshold` (`[0..1]`), or when the primary errors.
    case confidence(threshold: Float)
}

/// Suggested default confidence threshold for an STT confidence cascade.
/// Mirrors `RAC_HYBRID_STT_CONFIDENCE_THRESHOLD` in rac_hybrid_types.h — the
/// router uses the threshold carried in the installed policy; this is only the
/// recommended value to build it with.
public let RAHybridSTTConfidenceThreshold: Float = 0.5

// MARK: - Rank

/// Comparator that orders eligible candidates. Exactly one rank per policy.
/// Backed by the generated `RAHybridRank` (wire values match
/// `HybridRank` in hybrid_router.proto): `.preferLocalFirst` (1) prefers the
/// offline candidate, `.preferOnlineFirst` (2) prefers the online candidate.
public typealias HybridRank = RAHybridRank

// MARK: - Routing policy

/// The full routing policy attached to a model pair: filters (AND-composed),
/// an optional cascade, and a rank. Defaults to `.preferLocalFirst` with no
/// filters or cascade — i.e. "use the local candidate, fall back to online on
/// hard failure".
public struct HybridRoutingPolicy: Sendable {
    public var hardFilters: [HybridFilter]
    public var cascade: HybridCascade?
    public var rank: HybridRank

    public init(
        hardFilters: [HybridFilter] = [],
        cascade: HybridCascade? = nil,
        rank: HybridRank = .preferLocalFirst
    ) {
        self.hardFilters = hardFilters
        self.cascade = cascade
        self.rank = rank
    }

    // MARK: Convenience constructors (mirror Kotlin SimpleRouterPolicy)

    /// One-filter policy.
    public static func filter(_ filter: HybridFilter) -> HybridRoutingPolicy {
        HybridRoutingPolicy(hardFilters: [filter])
    }

    /// One-cascade policy (no filters, default rank).
    public static func cascade(_ cascade: HybridCascade) -> HybridRoutingPolicy {
        HybridRoutingPolicy(cascade: cascade)
    }

    /// Rank-only policy.
    public static func rank(_ rank: HybridRank) -> HybridRoutingPolicy {
        HybridRoutingPolicy(rank: rank)
    }
}

// MARK: - Proto marshalling

extension HybridRoutingPolicy {
    /// The custom filters in this policy, paired with the name commons looks
    /// them up by. Extracted so the router can register each predicate with
    /// `rac_hybrid_register_custom_filter` before installing the policy bytes.
    /// (The closure itself never crosses the FFI; only the name does, on the
    /// wire.)
    var customFilters: [(name: String, check: @Sendable (String) -> Bool)] {
        hardFilters.compactMap { filter in
            if case let .custom(name, _, check) = filter {
                return (name, check)
            }
            return nil
        }
    }

    /// Encode this policy as `runanywhere.v1.HybridRoutingPolicy` bytes for
    /// `rac_stt_hybrid_router_set_policy_proto`, via the generated SwiftProtobuf
    /// message. Pure: no FFI, no state. The generated encoder emits the same
    /// canonical proto3 wire bytes the C++/JNI router parses.
    func serializedBytes() throws -> [UInt8] {
        var message = RAHybridRoutingPolicy()
        message.hardFilters = hardFilters.map(encodeFilter)
        if let cascade {
            message.cascade = encodeCascade(cascade)
        }
        message.rank = rank
        return try [UInt8](message.serializedData())
    }

    private func encodeFilter(_ filter: HybridFilter) -> RAHybridFilter {
        var proto = RAHybridFilter()
        switch filter {
        case .network:
            // bool network = 1. Setting the oneof case emits field 1 even when
            // the value is the proto default, matching the prior encoder.
            proto.network = true
        case let .quality(tier):
            proto.qualityTier = tier
        case let .battery(minPercent):
            var battery = RABatteryFilter()
            battery.minBatteryPercent = minPercent
            proto.battery = battery
        case let .custom(name, description, _):
            var custom = RACustomFilter()
            custom.name = name
            custom.description_p = description
            proto.custom = custom
        }
        return proto
    }

    private func encodeCascade(_ cascade: HybridCascade) -> RAHybridCascade {
        var proto = RAHybridCascade()
        switch cascade {
        case let .confidence(threshold):
            var confidence = RAConfidenceCascade()
            confidence.threshold = threshold
            proto.confidence = confidence
        }
        return proto
    }
}
