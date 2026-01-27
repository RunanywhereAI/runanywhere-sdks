//
//  RunAnywhere+VLMModels.swift
//  RunAnywhere SDK
//
//  VLM model loading helpers with automatic framework routing.
//  Supports both llama.cpp (GGUF) and MLX (safetensors) backends.
//

import Foundation

// MARK: - VLM Model Loading

public extension RunAnywhere {

    /// Load a VLM model from a ModelInfo
    ///
    /// Automatically routes to the correct backend based on the model's framework:
    /// - `.llamaCpp` → Uses C++ llama.cpp backend (GGUF models)
    /// - `.mlx` → Uses MLX Swift backend (HuggingFace safetensors)
    ///
    /// - Parameter model: The model to load
    /// - Throws: SDKError if loading fails
    static func loadVLMModel(_ model: ModelInfo) async throws {
        switch model.framework {
        case .mlx:
            // MLX framework - use MLXVLMAdapter
            try await loadMLXVLMModel(model)

        case .llamaCpp:
            // llama.cpp framework - use C++ backend
            try await loadLlamaCppVLMModel(model)

        default:
            // Default to llama.cpp for unknown frameworks with local paths
            if model.localPath != nil {
                try await loadLlamaCppVLMModel(model)
            } else {
                throw SDKError.vlm(.modelLoadFailed, "Unsupported framework for VLM: \(model.framework.displayName)")
            }
        }
    }

    // MARK: - MLX VLM Loading

    /// Load an MLX VLM model from a ModelInfo
    @available(iOS 16.0, macOS 14.0, *)
    private static func loadMLXVLMModel(_ model: ModelInfo) async throws {
        // MLX models can be loaded from HuggingFace ID or local path
        let modelPath: String

        if let localPath = model.localPath {
            // Use local path if available
            modelPath = localPath.path
        } else if let downloadURL = model.downloadURL,
                  downloadURL.host?.contains("huggingface") == true {
            // Extract HuggingFace model ID from URL
            // e.g., https://huggingface.co/mlx-community/Qwen2.5-VL-3B-Instruct-4bit
            let pathComponents = downloadURL.pathComponents.filter { $0 != "/" }
            if pathComponents.count >= 2 {
                modelPath = "\(pathComponents[0])/\(pathComponents[1])"
            } else {
                throw SDKError.vlm(.modelLoadFailed, "Invalid HuggingFace URL: \(downloadURL)")
            }
        } else {
            throw SDKError.vlm(.modelLoadFailed, "MLX model requires local path or HuggingFace URL")
        }

        try await MLXVLMAdapter.shared.loadModel(modelPath, modelId: model.id)
    }

    /// Load an MLX VLM model from the predefined catalog
    ///
    /// - Parameter model: Predefined MLX VLM model from the catalog
    /// - Throws: SDKError if loading fails
    @available(iOS 16.0, macOS 14.0, *)
    static func loadMLXVLMModel(_ model: MLXVLMModel) async throws {
        try await MLXVLMAdapter.shared.loadModel(model.huggingFaceId, modelId: model.rawValue)
    }

    /// Load an MLX VLM model from a custom HuggingFace ID or local path
    ///
    /// - Parameters:
    ///   - path: HuggingFace model ID (e.g., "mlx-community/Qwen2.5-VL-3B-Instruct-4bit") or local directory path
    ///   - modelId: Unique identifier for telemetry
    /// - Throws: SDKError if loading fails
    @available(iOS 16.0, macOS 14.0, *)
    static func loadMLXVLMModel(path: String, modelId: String) async throws {
        try await MLXVLMAdapter.shared.loadModel(path, modelId: modelId)
    }

    /// Unload the MLX VLM model
    @available(iOS 16.0, macOS 14.0, *)
    static func unloadMLXVLMModel() async {
        await MLXVLMAdapter.shared.unloadModel()
    }

    /// Check if an MLX VLM model is loaded
    @available(iOS 16.0, macOS 14.0, *)
    static var isMLXVLMModelLoaded: Bool {
        get async { await MLXVLMAdapter.shared.isLoaded }
    }

    /// Get the currently loaded MLX VLM model ID
    @available(iOS 16.0, macOS 14.0, *)
    static var currentMLXVLMModelId: String? {
        get async { await MLXVLMAdapter.shared.currentModelId }
    }

    // MARK: - llama.cpp VLM Loading

    /// Load a llama.cpp VLM model from a ModelInfo
    private static func loadLlamaCppVLMModel(_ model: ModelInfo) async throws {
        guard let localPath = model.localPath else {
            throw SDKError.vlm(.modelLoadFailed, "Model not downloaded")
        }

        let modelPath = localPath.path
        let modelDir = localPath.deletingLastPathComponent()

        // Try to find mmproj file in same directory
        let mmprojPath = findMmprojFile(in: modelDir)

        try await loadVLMModel(
            modelPath,
            mmprojPath: mmprojPath,
            modelId: model.id,
            modelName: model.name
        )
    }

    /// Find mmproj file in a directory
    private static func findMmprojFile(in directory: URL) -> String? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }

        // Look for mmproj file (vision projector for llama.cpp VLM)
        if let mmprojFile = contents.first(where: { $0.contains("mmproj") && $0.hasSuffix(".gguf") }) {
            return directory.appendingPathComponent(mmprojFile).path
        }

        return nil
    }

    // MARK: - Framework Detection

    /// Detect the appropriate VLM framework based on model path or URL
    ///
    /// - Parameter path: Model path or URL string
    /// - Returns: Detected inference framework
    static func detectVLMFramework(from path: String) -> InferenceFramework {
        let lowercased = path.lowercased()

        // MLX indicators
        if lowercased.contains("mlx-community") ||
           lowercased.contains("safetensors") ||
           lowercased.hasPrefix("huggingfacetb/") ||
           lowercased.contains("4bit") && !lowercased.hasSuffix(".gguf") {
            return .mlx
        }

        // llama.cpp indicators
        if lowercased.hasSuffix(".gguf") ||
           lowercased.contains("mmproj") {
            return .llamaCpp
        }

        // Default to llama.cpp
        return .llamaCpp
    }
}
