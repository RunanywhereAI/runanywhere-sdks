//
//  ProcessorDetector.swift
//  RunAnywhere SDK
//
//  Detects processor capabilities and information using DeviceKit
//

import Foundation

/// Detects processor information and capabilities
public class ProcessorDetector {

    // MARK: - Properties

    private let logger = SDKLogger(category: "ProcessorDetector")
    private let deviceKitAdapter = DeviceKitAdapter()

    // MARK: - Public Methods

    /// Detect processor information
    public func detectProcessorInfo() -> ProcessorInfo {
        // Use DeviceKit adapter for accurate detection
        return deviceKitAdapter.getProcessorInfo()
    }

    /// Get processor efficiency rating
    public func getProcessorEfficiency() -> ProcessorEfficiency {
        let info = detectProcessorInfo()

        // Use performance tier from ProcessorInfo for accurate assessment
        switch info.performanceTier {
        case .flagship:
            return .high
        case .high:
            return .high
        case .medium:
            return .medium
        case .entry:
            return .low
        }
    }

    /// Get supported processor features
    public func getSupportedFeatures() -> [ProcessorFeature] {
        let info = detectProcessorInfo()
        var features: [ProcessorFeature] = []

        // ARM features
        if info.isAppleSilicon {
            features.append(.neon)
            features.append(.vectorUnit)
            if info.hasNeuralEngine {
                features.append(.neuralEngine)
            }
        }

        // Intel features
        if info.isIntel {
            features.append(.sse)
            features.append(.avx)
            features.append(.avx2)
        }

        return features
    }
}
