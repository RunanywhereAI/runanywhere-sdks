//
//  CapabilityAnalyzer.swift
//  RunAnywhere SDK
//
//  Analyzes and aggregates hardware capabilities
//

import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Analyzes hardware capabilities and makes optimization recommendations
public class CapabilityAnalyzer: @unchecked Sendable {

    // MARK: - Properties

    private let processorDetector: ProcessorDetector
    private let neuralEngineDetector: NeuralEngineDetector
    private let gpuDetector: GPUDetector
    private let logger = SDKLogger(category: "CapabilityAnalyzer")

    // MARK: - Initialization

    public init(
        processorDetector: ProcessorDetector? = nil,
        neuralEngineDetector: NeuralEngineDetector? = nil,
        gpuDetector: GPUDetector? = nil
    ) {
        self.processorDetector = processorDetector ?? ProcessorDetector()
        self.neuralEngineDetector = neuralEngineDetector ?? NeuralEngineDetector()
        self.gpuDetector = gpuDetector ?? GPUDetector()
    }

    // MARK: - Public Methods

    /// Analyze complete device capabilities
    public func analyzeCapabilities() -> DeviceCapabilities {
        logger.debug("Analyzing device capabilities")

        let processorInfo = processorDetector.detectProcessorInfo()
        let hasNeuralEngine = neuralEngineDetector.hasNeuralEngine()
        let hasGPU = gpuDetector.hasGPU()

        let totalMemory = getTotalMemory()
        let availableMemory = getAvailableMemory()

        let supportedAccelerators = determineSupportedAccelerators(
            hasNeuralEngine: hasNeuralEngine,
            hasGPU: hasGPU
        )

        let capabilities = DeviceCapabilities(
            totalMemory: totalMemory,
            availableMemory: availableMemory,
            hasNeuralEngine: hasNeuralEngine,
            hasGPU: hasGPU,
            processorCount: processorInfo.coreCount,
            processorType: mapToProcessorType(processorInfo: processorInfo),
            supportedAccelerators: supportedAccelerators,
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            modelIdentifier: getDeviceIdentifier()
        )

        logger.info(
            "Device capabilities: \(processorInfo.coreCount) cores, " +
            "\(hasNeuralEngine ? "Neural Engine" : "No Neural Engine"), " +
            "\(hasGPU ? "GPU" : "No GPU")"
        )

        return capabilities
    }

    /// Get optimal hardware configuration for a model
    public func getOptimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        let capabilities = analyzeCapabilities()

        var config = HardwareConfiguration()

        // Determine primary accelerator
        config.primaryAccelerator = selectPrimaryAccelerator(
            for: model,
            capabilities: capabilities
        )

        // Configure memory mode
        config.memoryMode = selectMemoryMode(
            for: model,
            capabilities: capabilities
        )

        // Set thread count
        config.threadCount = selectThreadCount(
            for: model,
            capabilities: capabilities
        )

        return config
    }

    // MARK: - Private Methods

    private func getTotalMemory() -> Int64 {
        return Int64(ProcessInfo.processInfo.physicalMemory)
    }

    private func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }

        let used = result == KERN_SUCCESS ? Int64(info.resident_size) : 0
        return getTotalMemory() - used
    }

    private func determineSupportedAccelerators(hasNeuralEngine: Bool, hasGPU: Bool) -> [HardwareAcceleration] {
        var accelerators: [HardwareAcceleration] = [.cpu]

        if hasGPU {
            accelerators.append(.gpu)
            accelerators.append(.metal)
        }

        if hasNeuralEngine {
            accelerators.append(.neuralEngine)
            accelerators.append(.coreML)
        }

        return accelerators
    }

    private func mapToProcessorType(processorInfo: ProcessorInfo) -> ProcessorType {
        if processorInfo.architecture.contains("ARM") || processorInfo.architecture.contains("arm") {
            return .arm
        } else if processorInfo.architecture.contains("x86") {
            return .intel
        } else {
            return .unknown
        }
    }

    private func getDeviceIdentifier() -> String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.model + "-" + ProcessInfo.processInfo.operatingSystemVersionString
        #elseif os(macOS)
        return "Mac-" + ProcessInfo.processInfo.operatingSystemVersionString
        #else
        return "Unknown-" + ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private func selectPrimaryAccelerator(
        for model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> HardwareAcceleration {
        // Large models with Neural Engine support
        if model.memoryRequired ?? 0 > 3_000_000_000 && capabilities.hasNeuralEngine {
            if model.format == .mlmodel || model.format == .mlpackage {
                return .neuralEngine
            }
        }

        // GPU for medium to large models
        if capabilities.hasGPU && model.memoryRequired ?? 0 > 1_000_000_000 {
            return .gpu
        }

        // Check framework preferences
        if let preferred = model.preferredFramework {
            switch preferred {
            case .coreML where capabilities.hasNeuralEngine:
                return .neuralEngine
            case .tensorFlowLite where capabilities.hasGPU:
                return .gpu
            case .mlx where capabilities.hasGPU:
                return .metal
            default:
                break
            }
        }

        return .auto
    }

    private func selectFallbackAccelerator(
        primary: HardwareAcceleration,
        capabilities: DeviceCapabilities
    ) -> HardwareAcceleration {
        switch primary {
        case .neuralEngine:
            return capabilities.hasGPU ? .gpu : .cpu
        case .gpu, .metal:
            return .cpu
        case .coreML:
            return .cpu
        case .cpu:
            return .cpu
        case .auto:
            return .cpu
        }
    }

    private func selectMemoryMode(
        for model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> HardwareConfiguration.MemoryMode {
        let availableMemory = capabilities.availableMemory
        let modelMemory = model.memoryRequired ?? 0

        if availableMemory < modelMemory * 2 {
            return .conservative
        }

        if availableMemory > modelMemory * 4 && capabilities.totalMemory > 8_000_000_000 {
            return .aggressive
        }

        return .balanced
    }

    private func selectThreadCount(
        for model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> Int {
        let processorCount = capabilities.processorCount

        if model.memoryRequired ?? 0 > 2_000_000_000 {
            return processorCount
        }

        if model.memoryRequired ?? 0 < 500_000_000 {
            return max(1, processorCount / 2)
        }

        return max(1, Int(Double(processorCount) * 0.75))
    }
}
