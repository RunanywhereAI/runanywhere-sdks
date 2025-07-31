//
//  FrameworkAdapterRegistry.swift
//  RunAnywhereAI
//
//  Sample app's registry for framework adapter implementations
//

import Foundation
// Import SDK when available
// import RunAnywhere

// MARK: - Framework Adapter Registry
// This is a sample app component that will register custom framework adapters

class FrameworkAdapterRegistry {
    static let shared = FrameworkAdapterRegistry()
    
    // This will store our custom framework adapter implementations
    // When SDK is available, these will be registered with the SDK
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
        
        // When SDK is available:
        // RunAnywhereSDK.shared.registerFrameworkAdapter(adapter)
    }
    
    func getAdapter(for framework: LLMFramework) -> BaseFrameworkAdapter? {
        return adapters[framework]
    }
    
    func getAllAdapters() -> [BaseFrameworkAdapter] {
        return Array(adapters.values)
    }
}