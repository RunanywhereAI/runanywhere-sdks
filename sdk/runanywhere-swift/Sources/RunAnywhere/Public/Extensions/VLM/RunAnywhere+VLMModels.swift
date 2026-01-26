//
//  RunAnywhere+VLMModels.swift
//  RunAnywhere SDK
//
//  VLM model loading helpers.
//

import Foundation

// MARK: - VLM Model Loading

public extension RunAnywhere {

    /// Load a VLM model from a ModelInfo
    /// - Parameter model: The model to load (must have localPath set)
    /// - Throws: SDKError if loading fails
    static func loadVLMModel(_ model: ModelInfo) async throws {
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

        // Look for mmproj file
        if let mmprojFile = contents.first(where: { $0.contains("mmproj") && $0.hasSuffix(".gguf") }) {
            return directory.appendingPathComponent(mmprojFile).path
        }

        return nil
    }
}
