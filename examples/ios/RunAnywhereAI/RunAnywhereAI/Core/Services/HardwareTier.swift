//
//  HardwareTier.swift
//  RunAnywhereAI
//
//  Display-only device capability label. Commons does not publish a typed
//  capability tier on DeviceInfo, so the example surfaces `.unknown` rather
//  than inventing RAM / Neural Engine thresholds or memory budgets.
//

import Foundation
import RunAnywhere

/// Coarse capability label for UI copy. Only `.unknown` is produced today —
/// typed tiers would come from an SDK/commons field when one exists.
enum HardwareTier: Int, CaseIterable, Comparable {
    /// No typed capability tier from the SDK/commons.
    case unknown
    /// Reserved for a future commons-owned low-end tier.
    case lowEnd
    /// Reserved for a future commons-owned mid-range tier.
    case midRange
    /// Reserved for a future commons-owned high-end tier.
    case highEnd

    static func < (lhs: HardwareTier, rhs: HardwareTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Consumer-facing headline describing the tier.
    var displayName: String {
        switch self {
        case .unknown: return "Capabilities unknown"
        case .lowEnd: return "Efficient device"
        case .midRange: return "Balanced device"
        case .highEnd: return "High-performance device"
        }
    }

    /// Short tagline shown under the headline.
    var tagline: String {
        switch self {
        case .unknown: return "Model fit uses SDK compatibility when available"
        case .lowEnd: return "Tuned for small, fast models"
        case .midRange: return "Runs balanced models smoothly"
        case .highEnd: return "Runs larger, smarter models"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .lowEnd: return "bolt"
        case .midRange: return "gauge.with.dots.needle.50percent"
        case .highEnd: return "sparkles"
        }
    }
}

/// Resolves display tier + Apple Foundation availability. Detection never
/// invents RAM/ANE thresholds; tier stays `.unknown` until commons owns one.
struct HardwareTierResolver {
    /// No typed `capability_tier` on DeviceInfo / commons today — surface
    /// unknown instead of local memory/ANE policy.
    func resolve(from device: SystemDeviceInfo?) -> HardwareTier {
        _ = device
        return .unknown
    }

    /// Whether Apple's built-in Foundation model is available as the default
    /// chat model on this runtime (iOS/macOS 26+ with Apple Intelligence).
    var appleFoundationAvailable: Bool {
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemFoundationModels.isAvailable
        }
        #endif
        return false
    }
}
