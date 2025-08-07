//
//  ProcessorInfo.swift
//  RunAnywhere SDK
//
//  Extensions for ProcessorInfo defined in HardwareDetector protocol
//

import Foundation

/// Processor efficiency ratings
public enum ProcessorEfficiency {
    case low
    case medium
    case high
    case unknown
}

/// Processor features that affect ML performance
public enum ProcessorFeature {
    case neon              // ARM NEON instructions
    case avx               // Intel AVX instructions
    case avx2              // Intel AVX2 instructions
    case sse               // Intel SSE instructions
    case vectorUnit        // Generic vector processing unit
    case dedicatedCache    // Dedicated cache for ML operations
    case neuralEngine      // Apple Neural Engine
    case unknown(String)   // Other features
}

// Extensions to existing ProcessorInfo struct
public extension ProcessorInfo {
    /// Get processor efficiency rating
    var efficiency: ProcessorEfficiency {
        // Simple heuristic based on core count and architecture
        if coreCount >= 8 {
            return .high
        } else if coreCount >= 4 {
            return .medium
        } else {
            return .low
        }
    }

    /// Get supported processor features
    var features: [ProcessorFeature] {
        var features: [ProcessorFeature] = []

        if hasARM64E || architecture.contains("arm") || architecture.contains("ARM") {
            features.append(.neon)
            features.append(.vectorUnit)
            features.append(.dedicatedCache)
        } else if architecture.contains("x86") {
            features.append(.sse)
            features.append(.avx)
            features.append(.vectorUnit)
        }

        return features
    }
}
