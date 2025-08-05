//
//  NeuralEngineDetector.swift
//  RunAnywhere SDK
//
//  Detects Neural Engine availability and capabilities
//

import Foundation

/// Detects Neural Engine capabilities
public class NeuralEngineDetector {

    // MARK: - Properties

    private let logger = SDKLogger(category: "NeuralEngineDetector")

    // MARK: - Public Methods

    /// Check if Neural Engine is available
    public func hasNeuralEngine() -> Bool {
        #if os(iOS) || os(tvOS)
        return hasAppleNeuralEngine()
        #elseif os(macOS)
        return hasMacNeuralEngine()
        #else
        return false
        #endif
    }

    /// Get Neural Engine capabilities
    public func getNeuralEngineCapabilities() -> NeuralEngineCapabilities? {
        guard hasNeuralEngine() else { return nil }

        return NeuralEngineCapabilities(
            version: detectNeuralEngineVersion(),
            operationsPerSecond: estimateOperationsPerSecond(),
            supportedPrecisions: getSupportedPrecisions(),
            maxModelSize: getMaxModelSize()
        )
    }

    /// Check if model format is compatible with Neural Engine
    public func isCompatible(format: ModelFormat) -> Bool {
        guard hasNeuralEngine() else { return false }

        switch format {
        case .mlmodel, .mlpackage:
            return true
        default:
            return false
        }
    }

    // MARK: - Private Methods

    #if os(iOS) || os(tvOS)
    private func hasAppleNeuralEngine() -> Bool {
        // Check for A12 Bionic or later (iPhone XS and newer)
        // This is simplified - in production would check actual chip
        let processorCount = ProcessInfo.processInfo.processorCount

        // A12 and later typically have 6+ cores
        if processorCount >= 6 {
            return true
        }

        // Additional check based on iOS version
        if #available(iOS 12.0, tvOS 12.0, *) {
            return true
        }

        return false
    }
    #endif

    #if os(macOS)
    private func hasMacNeuralEngine() -> Bool {
        // Check for M1 or later on Mac
        // M1 Macs typically have 8+ cores
        let processorCount = ProcessInfo.processInfo.processorCount

        if processorCount >= 8 {
            // Additional check for Apple Silicon
            #if arch(arm64)
            return true
            #else
            return false
            #endif
        }

        return false
    }
    #endif

    private func detectNeuralEngineVersion() -> NeuralEngineVersion {
        let processorCount = ProcessInfo.processInfo.processorCount

        // Simple heuristic based on processor count
        if processorCount >= 10 {
            return .generation3  // M2 Pro/Max
        } else if processorCount >= 8 {
            return .generation2  // M1 series
        } else {
            return .generation1  // A12-A15
        }
    }

    private func estimateOperationsPerSecond() -> Int64 {
        let version = detectNeuralEngineVersion()

        switch version {
        case .generation1:
            return 5_000_000_000_000  // 5 TOPS
        case .generation2:
            return 11_000_000_000_000 // 11 TOPS
        case .generation3:
            return 15_000_000_000_000 // 15+ TOPS
        }
    }

    private func getSupportedPrecisions() -> [NeuralEnginePrecision] {
        return [.int8, .float16]
    }

    private func getMaxModelSize() -> Int64 {
        // Typical maximum model size for Neural Engine
        return 1_000_000_000 // 1GB
    }
}

// MARK: - Supporting Types

/// Neural Engine capabilities information
public struct NeuralEngineCapabilities {
    public let version: NeuralEngineVersion
    public let operationsPerSecond: Int64
    public let supportedPrecisions: [NeuralEnginePrecision]
    public let maxModelSize: Int64
}

/// Neural Engine generations
public enum NeuralEngineVersion {
    case generation1  // A12-A15
    case generation2  // M1 series
    case generation3  // M2 series and later
}

/// Supported precisions for Neural Engine
public enum NeuralEnginePrecision {
    case int8
    case float16
    case float32
}
