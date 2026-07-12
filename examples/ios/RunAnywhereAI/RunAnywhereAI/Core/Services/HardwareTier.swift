//
//  HardwareTier.swift
//  RunAnywhereAI
//
//  Pure, testable classification of the device's on-device inference capability.
//  Consumed by the hardware-aware model recommendation engine.
//

import Foundation
import RunAnywhere

/// Coarse capability class of the current device, derived only from
/// `SystemDeviceInfo`. Single responsibility: map raw device facts to a tier
/// plus the memory budget we are willing to spend on a model.
enum HardwareTier: Int, CaseIterable, Comparable {
    /// < ~4 GB RAM. Prefer the smallest quantized / ONNX variants.
    case lowEnd
    /// ~4-8 GB RAM. Balanced small-to-mid models.
    case midRange
    /// >= ~8 GB RAM with Neural Engine / Apple Silicon. Full spread including
    /// larger "genius" models.
    case highEnd

    static func < (lhs: HardwareTier, rhs: HardwareTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Consumer-facing headline describing the tier.
    var displayName: String {
        switch self {
        case .lowEnd: return "Efficient device"
        case .midRange: return "Balanced device"
        case .highEnd: return "High-performance device"
        }
    }

    /// Short tagline shown under the headline.
    var tagline: String {
        switch self {
        case .lowEnd: return "Tuned for small, fast models"
        case .midRange: return "Runs balanced models smoothly"
        case .highEnd: return "Runs larger, smarter models"
        }
    }

    var systemImage: String {
        switch self {
        case .lowEnd: return "bolt"
        case .midRange: return "gauge.with.dots.needle.50percent"
        case .highEnd: return "sparkles"
        }
    }

    /// Largest model (by required bytes) we recommend downloading on this tier.
    /// Kept well under total RAM to leave headroom for the OS and runtime.
    var memoryBudgetBytes: Int64 {
        switch self {
        case .lowEnd: return 700_000_000       // ~0.7 GB
        case .midRange: return 2_000_000_000   // ~2 GB
        case .highEnd: return 5_000_000_000    // ~5 GB
        }
    }
}

/// Value type that resolves a `HardwareTier` from a `SystemDeviceInfo`.
/// Detection reads only from already-collected device facts; it performs no
/// new native calls (Single Responsibility / Open-Closed friendly).
struct HardwareTierResolver {
    /// GB expressed in bytes for readable thresholds.
    private static let gigabyte: Int64 = 1_073_741_824

    /// Resolve a tier from the given device info. Falls back to `.midRange`
    /// when memory is unknown so the UI never shows an empty recommendation.
    func resolve(from device: SystemDeviceInfo?) -> HardwareTier {
        guard let device, device.totalMemory > 0 else { return .midRange }

        let totalGB = Double(device.totalMemory) / Double(Self.gigabyte)

        if totalGB >= 8 && device.neuralEngineAvailable {
            return .highEnd
        }
        if totalGB >= 4 {
            return .midRange
        }
        return .lowEnd
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
