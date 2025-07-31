//
//  HardwareAcceleration.swift
//  RunAnywhereAI
//
//  Abstract protocol for hardware acceleration across different frameworks
//

import Foundation

// MARK: - Hardware Acceleration Protocol

/// Abstract protocol for hardware acceleration support
protocol HardwareAccelerated {
    /// Available acceleration modes for the service
    var supportedAccelerationModes: [AccelerationMode] { get }
    
    /// Currently active acceleration mode
    var currentAccelerationMode: AccelerationMode { get }
    
    /// Configure hardware acceleration based on device capabilities
    func configureAcceleration(mode: AccelerationMode) async throws
    
    /// Get performance metrics for current acceleration
    func getAccelerationMetrics() -> AccelerationMetrics
}

// MARK: - Acceleration Types

/// Generic acceleration modes applicable across frameworks
enum AccelerationMode: String, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case neuralEngine = "Neural Engine"
    case auto = "Auto"
    
    var description: String {
        switch self {
        case .cpu:
            return "CPU-only execution"
        case .gpu:
            return "GPU acceleration (Metal/CUDA)"
        case .neuralEngine:
            return "Neural Engine/NPU acceleration"
        case .auto:
            return "Automatic selection based on device"
        }
    }
}

// MARK: - Acceleration Metrics

/// Performance metrics for hardware acceleration
struct AccelerationMetrics {
    let mode: AccelerationMode
    let isActive: Bool
    let utilizationPercentage: Double?
    let estimatedSpeedup: Double?
    let powerEfficiency: PowerEfficiency?
    
    enum PowerEfficiency: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }
}

// MARK: - Hardware Capability Detection

/// Abstract hardware capability detection
protocol HardwareCapabilityDetector {
    /// Check if a specific acceleration mode is available
    func isAccelerationAvailable(_ mode: AccelerationMode) -> Bool
    
    /// Get the recommended acceleration mode for current device
    func recommendedAccelerationMode() -> AccelerationMode
    
    /// Get detailed hardware information
    func getHardwareInfo() -> HardwareInfo
}

/// Hardware information structure
struct HardwareInfo {
    let deviceModel: String
    let processorType: String
    let coreCount: Int
    let memorySize: Int64
    let hasNeuralEngine: Bool
    let hasHighPerformanceGPU: Bool
    let supportedAccelerationModes: [AccelerationMode]
}

// MARK: - Default Implementation

/// Default implementation for services that don't support acceleration
extension HardwareAccelerated {
    var supportedAccelerationModes: [AccelerationMode] {
        [.cpu]
    }
    
    var currentAccelerationMode: AccelerationMode {
        .cpu
    }
    
    func configureAcceleration(mode: AccelerationMode) async throws {
        guard mode == .cpu else {
            throw LLMError.custom("Only CPU mode is supported")
        }
    }
    
    func getAccelerationMetrics() -> AccelerationMetrics {
        AccelerationMetrics(
            mode: .cpu,
            isActive: true,
            utilizationPercentage: nil,
            estimatedSpeedup: 1.0,
            powerEfficiency: .medium
        )
    }
}

// MARK: - Framework-Specific Acceleration Protocols

/// Protocol for TensorFlow Lite specific acceleration
protocol TFLiteAccelerated: HardwareAccelerated {
    /// Configure TFLite-specific delegates
    func configureTFLiteDelegate(for mode: AccelerationMode) throws -> Any?
}

/// Protocol for Core ML specific acceleration
protocol CoreMLAccelerated: HardwareAccelerated {
    /// Configure Core ML compute units
    func configureCoreMLComputeUnits(for mode: AccelerationMode) -> Any
}

/// Protocol for MLX specific acceleration
protocol MLXAccelerated: HardwareAccelerated {
    /// Configure MLX device selection
    func configureMLXDevice(for mode: AccelerationMode) -> String
}