//
//  BaseFrameworkAdapter.swift
//  RunAnywhereAI
//
//  Base adapter for framework implementations in the sample app
//

import Foundation
import RunAnywhereSDK

// MARK: - Base Framework Adapter
// This is a sample app implementation that implements SDK's FrameworkAdapter protocol

class BaseFrameworkAdapter {
    let localFramework: LLMFramework
    let localSupportedFormats: [ModelFormat]

    init(framework: LLMFramework, formats: [ModelFormat]) {
        self.localFramework = framework
        self.localSupportedFormats = formats
    }
}

// MARK: - SDK Framework Adapter Protocol Implementation
extension BaseFrameworkAdapter: RunAnywhereSDK.FrameworkAdapter {
    // SDK Framework property
    var framework: RunAnywhereSDK.LLMFramework {
        return self.localFramework.toSDKFramework ?? .coreML
    }

    // SDK Supported formats property
    var supportedFormats: [RunAnywhereSDK.ModelFormat] {
        return self.localSupportedFormats.compactMap { $0.toSDKFormat }
    }

    func canHandle(model: RunAnywhereSDK.ModelInfo) -> Bool {
        // Check if the model format is supported
        guard supportedFormats.contains(model.format) else {
            return false
        }

        // Check if the framework is compatible
        guard model.compatibleFrameworks.contains(framework) else {
            return false
        }

        // Additional framework-specific checks can be added in subclasses
        return true
    }

    func createService() -> RunAnywhereSDK.LLMService {
        // This should be overridden in subclasses to return the appropriate service
        fatalError("createService() must be overridden in subclass")
    }

    func configure(with hardware: RunAnywhereSDK.HardwareConfiguration) async {
        // Base configuration - can be overridden in subclasses
        // Hardware configuration will be applied when creating the service
    }

    func estimateMemoryUsage(for model: RunAnywhereSDK.ModelInfo) -> Int64 {
        // Base estimation - can be refined in subclasses
        return model.estimatedMemory
    }

    func optimalConfiguration(for model: RunAnywhereSDK.ModelInfo) -> RunAnywhereSDK.HardwareConfiguration {
        // Base configuration - can be customized in subclasses
        var config = RunAnywhereSDK.HardwareConfiguration()

        // Determine primary accelerator based on framework
        switch framework {
        case .coreML:
            config.primaryAccelerator = .neuralEngine
            config.fallbackAccelerator = .gpu
        case .tensorFlowLite:
            config.primaryAccelerator = .gpu
            config.fallbackAccelerator = .cpu
        case .mlx:
            config.primaryAccelerator = .gpu
            config.fallbackAccelerator = .cpu
        case .onnx:
            config.primaryAccelerator = .coreML
            config.fallbackAccelerator = .cpu
        default:
            config.primaryAccelerator = .auto
            config.fallbackAccelerator = .cpu
        }

        // Set memory mode based on model size
        if model.estimatedMemory > 4_000_000_000 { // 4GB
            config.memoryMode = .conservative
        } else if model.estimatedMemory > 2_000_000_000 { // 2GB
            config.memoryMode = .balanced
        } else {
            config.memoryMode = .aggressive
        }

        return config
    }
}
