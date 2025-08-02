//
//  ProcessorDetector.swift
//  RunAnywhere SDK
//
//  Detects processor capabilities and information
//

import Foundation

/// Detects processor information and capabilities
public class ProcessorDetector {

    // MARK: - Properties

    private let logger = SDKLogger(category: "ProcessorDetector")

    // MARK: - Public Methods

    /// Detect processor information
    public func detectProcessorInfo() -> ProcessorInfo {
        let coreCount = ProcessInfo.processInfo.processorCount

        #if arch(arm64)
        return detectARMProcessor(coreCount: coreCount)
        #elseif arch(x86_64)
        return detectIntelProcessor(coreCount: coreCount)
        #else
        return ProcessorInfo(
            name: "Unknown",
            architecture: "Unknown",
            coreCount: coreCount,
            performanceCoreCount: coreCount,
            efficiencyCoreCount: 0,
            frequencyHz: nil,
            hasARM64E: false
        )
        #endif
    }

    /// Get processor efficiency rating
    public func getProcessorEfficiency() -> ProcessorEfficiency {
        let info = detectProcessorInfo()

        // Simple heuristic based on core count and architecture
        #if arch(arm64)
        // ARM processors are generally more efficient
        if info.coreCount >= 8 {
            return .high
        } else if info.coreCount >= 4 {
            return .medium
        } else {
            return .low
        }
        #elseif arch(x86_64)
        // Intel processors
        if info.coreCount >= 8 {
            return .medium
        } else if info.coreCount >= 4 {
            return .medium
        } else {
            return .low
        }
        #else
        return .unknown
        #endif
    }

    /// Get supported processor features
    public func getSupportedFeatures() -> [ProcessorFeature] {
        var features: [ProcessorFeature] = []

        #if arch(arm64)
        features.append(.neon)
        features.append(.vectorUnit)
        #elseif arch(x86_64)
        // These would require runtime CPU feature detection
        // For now, assume modern Intel processors support these
        if ProcessInfo.processInfo.processorCount >= 4 {
            features.append(.sse)
            features.append(.avx)
            features.append(.avx2)
        }
        #endif

        return features
    }

    // MARK: - Private Methods

    #if arch(arm64)
    private func detectARMProcessor(coreCount: Int) -> ProcessorInfo {
        // Detect Apple Silicon variants
        let name = detectAppleSiliconName(coreCount: coreCount)

        return ProcessorInfo(
            name: name,
            architecture: "ARM64",
            coreCount: coreCount,
            performanceCoreCount: max(2, coreCount / 2),
            efficiencyCoreCount: max(2, coreCount / 2),
            frequencyHz: nil,
            hasARM64E: true
        )
    }

    private func detectAppleSiliconName(coreCount: Int) -> String {
        // Simple heuristic based on core count
        // In production, would use IOKit to get actual chip info
        if coreCount >= 10 {
            return "Apple M2 Pro/Max"
        } else if coreCount >= 8 {
            return "Apple M1 Pro/M2"
        } else if coreCount >= 4 {
            return "Apple M1/A14+"
        } else {
            return "Apple A-series"
        }
    }
    #endif

    #if arch(x86_64)
    private func detectIntelProcessor(coreCount: Int) -> ProcessorInfo {
        return ProcessorInfo(
            name: "Intel x86_64",
            architecture: "x86_64",
            coreCount: coreCount,
            performanceCoreCount: coreCount,
            efficiencyCoreCount: 0,
            frequencyHz: nil,
            hasARM64E: false
        )
    }
    #endif
}
