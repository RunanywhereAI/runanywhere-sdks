//
//  GPUDetector.swift
//  RunAnywhere SDK
//
//  Detects GPU availability and capabilities
//

import Foundation
#if canImport(Metal)
import Metal
#endif

/// Detects GPU capabilities
public class GPUDetector {

    // MARK: - Properties

    private let logger = SDKLogger(category: "GPUDetector")

    // MARK: - Public Methods

    /// Check if GPU is available
    public func hasGPU() -> Bool {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }

    /// Get GPU capabilities
    public func getGPUCapabilities() -> GPUCapabilities? {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        return GPUCapabilities(
            name: device.name,
            family: detectGPUFamily(device: device),
            maxBufferLength: Int(device.maxBufferLength),
            supportsComputeShaders: true,
            supportsMetalPerformanceShaders: true,
            recommendedMaxWorkingSetSize: Int(device.recommendedMaxWorkingSetSize)
        )
        #else
        return nil
        #endif
    }

    /// Get GPU family name
    public func getGPUFamily() -> String? {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return detectGPUFamily(device: device)
        #else
        return nil
        #endif
    }

    /// Check if GPU supports machine learning operations
    public func supportsML() -> Bool {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else { return false }

        // Check for Metal Performance Shaders support
        if #available(iOS 11.0, macOS 10.13, tvOS 11.0, *) {
            return true
        }

        return false
        #else
        return false
        #endif
    }

    /// Get estimated GPU memory
    public func getGPUMemory() -> Int64 {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else { return 0 }

        // On unified memory systems, GPU shares system memory
        #if os(iOS) || os(tvOS) || (os(macOS) && arch(arm64))
        return Int64(ProcessInfo.processInfo.physicalMemory)
        #else
        // Discrete GPU - estimate based on device capabilities
        return estimateDiscreteGPUMemory(device: device)
        #endif
        #else
        return 0
        #endif
    }

    // MARK: - Private Methods

    #if canImport(Metal)
    private func detectGPUFamily(device: MTLDevice) -> String {
        #if os(iOS) || os(tvOS)
        return "Apple GPU"
        #elseif os(macOS)
        if device.name.contains("Apple") {
            return "Apple GPU"
        } else {
            return "Metal GPU"
        }
        #else
        return "Unknown GPU"
        #endif
    }

    private func estimateDiscreteGPUMemory(device: MTLDevice) -> Int64 {
        // This is a rough estimate for discrete GPUs
        // In practice, you'd need platform-specific code to get actual VRAM
        let recommendedMaxWorkingSetSize = device.recommendedMaxWorkingSetSize

        if recommendedMaxWorkingSetSize > 0 {
            return Int64(recommendedMaxWorkingSetSize)
        }

        // Fallback estimate
        return 2_000_000_000 // 2GB
    }
    #endif
}

// MARK: - Supporting Types

/// GPU capabilities information
public struct GPUCapabilities {
    public let name: String
    public let family: String
    public let maxBufferLength: Int
    public let supportsComputeShaders: Bool
    public let supportsMetalPerformanceShaders: Bool
    public let recommendedMaxWorkingSetSize: Int

    /// Estimated performance tier
    public var performanceTier: GPUPerformanceTier {
        // Simple heuristic based on max buffer length
        if maxBufferLength > 1_000_000_000 {
            return .high
        } else if maxBufferLength > 256_000_000 {
            return .medium
        } else {
            return .low
        }
    }
}

/// GPU performance tiers
public enum GPUPerformanceTier {
    case low
    case medium
    case high
}
