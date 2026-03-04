//
//  RunAnywhere+VLMModels.swift
//  RunAnywhere SDK
//
//  VLM model loading helpers.
//  Model file resolution (main model + mmproj) is handled in C++ commons.
//

import Foundation

private let vlmLogger = SDKLogger(category: "VLM.Models")

// MARK: - VLM Model Loading

public extension RunAnywhere {

    /// Load a VLM model from a ModelInfo using the C++ model registry.
    ///
    /// The C++ layer handles resolving the model folder, finding the main .gguf
    /// and mmproj .gguf files automatically.
    ///
    /// - Parameter model: The model to load (must be registered in the global registry)
    /// - Throws: SDKError if loading fails
    static func loadVLMModel(_ model: ModelInfo) async throws {
        vlmLogger.info("Loading VLM model by ID: \(model.id)")
        try await CppBridge.VLM.shared.loadModelById(model.id)
        vlmLogger.info("VLM model loaded successfully: \(model.id)")
    }

    /// Load a VLM model by ID string using the C++ model registry.
    ///
    /// - Parameter modelId: Model identifier (must be registered in the global registry)
    /// - Throws: SDKError if loading fails
    static func loadVLMModelById(_ modelId: String) async throws {
        vlmLogger.info("Loading VLM model by ID: \(modelId)")
        try await CppBridge.VLM.shared.loadModelById(modelId)
        vlmLogger.info("VLM model loaded successfully: \(modelId)")
    }
}
