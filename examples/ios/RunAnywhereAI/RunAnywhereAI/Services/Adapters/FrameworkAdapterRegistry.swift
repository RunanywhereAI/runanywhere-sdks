//
//  FrameworkAdapterRegistry.swift
//  RunAnywhereAI
//
//  Sample app's registry for framework adapter implementations
//

import Foundation
import RunAnywhereSDK

// MARK: - Framework Adapter Registry
// This is a sample app component that manages framework adapters

class FrameworkAdapterRegistry {
    static let shared = FrameworkAdapterRegistry()

    // This will store our custom framework adapter implementations
    private var adapters: [LLMFramework: BaseFrameworkAdapter] = [:]

    private init() {
        registerDefaultAdapters()
    }

    private func registerDefaultAdapters() {
        // Register all framework adapters
        register(CoreMLFrameworkAdapter())
        register(TFLiteFrameworkAdapter())
        register(MLXFrameworkAdapter())
        register(SwiftTransformersAdapter())
        register(ONNXFrameworkAdapter())
        register(ExecuTorchAdapter())
        register(LlamaCppFrameworkAdapter())

        if #available(iOS 18.0, *) {
            register(FoundationModelsAdapter())
        }

        register(PicoLLMAdapter())
        register(MLCAdapter())
    }

    func register(_ adapter: BaseFrameworkAdapter) {
        adapters[adapter.framework] = adapter
    }

    func getAdapter(for framework: LLMFramework) -> BaseFrameworkAdapter? {
        return adapters[framework]
    }

    func getAllAdapters() -> [BaseFrameworkAdapter] {
        return Array(adapters.values)
    }

    // Find best adapter for a model considering hardware capabilities
    func findBestAdapter(for model: ModelInfo) -> BaseFrameworkAdapter? {
        // Get all compatible adapters
        let compatibleAdapters = adapters.values.filter { adapter in
            // Check if adapter supports the model format
            adapter.localSupportedFormats.contains(model.format)
        }

        // If only one compatible adapter, return it
        if compatibleAdapters.count == 1 {
            return compatibleAdapters.first
        }

        // Score each adapter based on various factors
        let scoredAdapters = compatibleAdapters.map { adapter -> (adapter: BaseFrameworkAdapter, score: Double) in
            var score = 0.0

            // Prefer the model's preferred framework if specified
            if adapter.localFramework == model.framework {
                score += 10.0
            }

            // Score based on framework capabilities
            switch adapter.localFramework {
            case .coreML:
                // CoreML is great for Apple Neural Engine
                if model.size.contains("B") { // Large models
                    score += 8.0
                }
            case .mlx:
                // MLX is optimized for Apple Silicon
                score += 7.0
            case .tensorFlowLite:
                // TFLite has good delegate support
                score += 6.0
            case .onnxRuntime:
                // ONNX has wide compatibility
                score += 5.0
            default:
                score += 3.0
            }

            return (adapter, score)
        }

        // Return the highest scoring adapter
        return scoredAdapters.max(by: { $0.score < $1.score })?.adapter
    }
}

// MARK: - SDK Protocol Implementation
extension FrameworkAdapterRegistry: RunAnywhereSDK.FrameworkAdapterRegistry {
    func getAdapter(for framework: RunAnywhereSDK.LLMFramework) -> RunAnywhereSDK.FrameworkAdapter? {
        // Convert SDK framework to local framework
        guard let localFramework = LLMFramework.fromSDK(framework) else { return nil }

        // Get local adapter
        guard let localAdapter = getAdapter(for: localFramework) else { return nil }

        // Return adapter that implements SDK protocol
        // BaseFrameworkAdapter now implements RunAnywhereSDK.FrameworkAdapter
        return localAdapter as? RunAnywhereSDK.FrameworkAdapter
    }

    func findBestAdapter(for model: RunAnywhereSDK.ModelInfo) -> RunAnywhereSDK.FrameworkAdapter? {
        // Convert SDK ModelInfo to local ModelInfo
        guard let localModel = ModelInfo.fromSDK(model) else { return nil }

        // Find best adapter using local logic
        guard let bestAdapter = findBestAdapter(for: localModel) else { return nil }

        // Return as SDK adapter
        return bestAdapter as? RunAnywhereSDK.FrameworkAdapter
    }

    func register(_ adapter: RunAnywhereSDK.FrameworkAdapter) {
        // This would register SDK adapters
        // For now, we only support registering our local adapters
        // In the future, we could wrap SDK adapters in a local adapter class
    }
}
