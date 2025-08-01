//
//  CoreMLFrameworkAdapter.swift
//  RunAnywhereAI
//
//  Sample app's Core ML framework adapter implementation
//

import Foundation
import CoreML
import RunAnywhereSDK

// MARK: - Core ML Framework Adapter
// This adapter will implement SDK's FrameworkAdapter protocol when SDK is available

class CoreMLFrameworkAdapter: BaseFrameworkAdapter {
    init() {
        super.init(
            framework: .coreML,
            formats: [.mlmodel, .mlpackage]
        )
    }

    override func createService() -> RunAnywhereSDK.LLMService {
        if #available(iOS 17.0, *) {
            return UnifiedCoreMLService()
        } else {
            // For older iOS versions, we could provide a fallback or throw an error
            fatalError("CoreML adapter requires iOS 17.0 or later")
        }
    }

    override func canHandle(model: RunAnywhereSDK.ModelInfo) -> Bool {
        // First check base implementation
        guard super.canHandle(model: model) else { return false }

        // Additional Core ML specific checks
        // Check if Neural Engine is available for large models
        if model.estimatedMemory > 3_000_000_000 { // 3GB
            // Use SDK's HardwareCapabilityManager
            let hardware = RunAnywhereSDK.HardwareCapabilityManager.shared
            return hardware.capabilities.hasNeuralEngine
        }

        return true
    }

    override func configure(with hardware: RunAnywhereSDK.HardwareConfiguration) async {
        // Core ML specific hardware configuration
        // This configuration would be passed to the CoreMLService
        await super.configure(with: hardware)
    }

    override func optimalConfiguration(for model: RunAnywhereSDK.ModelInfo) -> RunAnywhereSDK.HardwareConfiguration {
        var config = super.optimalConfiguration(for: model)

        // Core ML specific optimizations
        if #available(iOS 17.0, *) {
            // Prefer Neural Engine for Core ML models on newer devices
            config.primaryAccelerator = .neuralEngine
            config.fallbackAccelerator = .gpu
        } else {
            // Fallback to GPU on older devices
            config.primaryAccelerator = .gpu
            config.fallbackAccelerator = .cpu
        }

        return config
    }
}

// MARK: - Unified Core ML Service
// This wraps the existing CoreMLService to implement SDK's LLMService protocol

@available(iOS 17.0, *)
class UnifiedCoreMLService: RunAnywhereSDK.LLMService {
    private let coreMLService: CoreMLService

    init() {
        self.coreMLService = CoreMLService()
    }
    func initialize(modelPath: String) async throws {
        // Initialize the existing CoreMLService
        try await coreMLService.initialize(modelPath: modelPath)
    }

    func generate(prompt: String, options: RunAnywhereSDK.GenerationOptions) async throws -> String {
        // Convert SDK options to sample app options
        let localOptions = GenerationOptions(
            temperature: options.temperature,
            topK: options.topK,
            topP: options.topP,
            maxTokens: options.maxTokens ?? 100,
            repetitionPenalty: options.repetitionPenalty
        )

        return try await coreMLService.generate(prompt: prompt, options: localOptions)
    }

    func streamGenerate(prompt: String, options: RunAnywhereSDK.GenerationOptions, onToken: @escaping (String) -> Void) async throws {
        // Convert SDK options to sample app options
        let localOptions = GenerationOptions(
            temperature: options.temperature,
            topK: options.topK,
            topP: options.topP,
            maxTokens: options.maxTokens ?? 100,
            repetitionPenalty: options.repetitionPenalty
        )

        try await coreMLService.streamGenerate(prompt: prompt, options: localOptions, onToken: onToken)
    }

    func cleanup() async {
        await coreMLService.cleanup()
    }

    func getModelMemoryUsage() async throws -> Int64 {
        return coreMLService.estimatedMemoryUsage
    }

    var isReady: Bool {
        return coreMLService.isReady
    }

    var modelInfo: RunAnywhereSDK.LoadedModelInfo? {
        // Convert sample app's model info to SDK's LoadedModelInfo
        guard let model = coreMLService.modelInfo else { return nil }

        return RunAnywhereSDK.LoadedModelInfo(
            id: model.id,
            name: model.name,
            framework: .coreML
        )
    }

    func setContext(_ context: RunAnywhereSDK.Context) async {
        // Convert SDK context to sample app format if needed
        // Currently CoreMLService doesn't support context, but this is where it would be set
    }

    func clearContext() async {
        // Clear any stored context
    }
}
