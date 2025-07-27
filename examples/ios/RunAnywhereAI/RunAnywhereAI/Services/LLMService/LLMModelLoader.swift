//
//  LLMModelLoader.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

/// Model configuration for loading
struct ModelConfiguration {
    let modelPath: String
    let format: ModelFormat
    let quantization: QuantizationFormat?
    let contextLength: Int
    let batchSize: Int
    let useGPU: Bool
    let customOptions: [String: Any]
    
    static let `default` = ModelConfiguration(
        modelPath: "",
        format: .gguf,
        quantization: nil,
        contextLength: 2048,
        batchSize: 1,
        useGPU: true,
        customOptions: [:]
    )
}

/// Protocol for model loading capabilities
protocol LLMModelLoader {
    /// Load a model from the specified path
    func loadModel(_ path: String) async throws
    
    /// Unload the currently loaded model
    func unloadModel() async throws
    
    /// Preload a model with specific configuration
    func preloadModel(_ config: ModelConfiguration) async throws
    
    /// Get supported model formats
    var supportedFormats: [ModelFormat] { get }
    
    /// Check if a model format is supported
    func isFormatSupported(_ format: ModelFormat) -> Bool
    
    /// Get current model state
    var modelState: ModelState { get }
    
    /// Validate model before loading
    func validateModel(at path: String) async throws -> ModelValidation
}

/// Model loading state
enum ModelState {
    case unloaded
    case loading(progress: Double)
    case loaded(modelInfo: ModelInfo)
    case failed(error: Error)
}

/// Model validation result
struct ModelValidation {
    let isValid: Bool
    let format: ModelFormat?
    let fileSize: Int64
    let estimatedMemory: Int64
    let warnings: [String]
    let metadata: [String: Any]
}