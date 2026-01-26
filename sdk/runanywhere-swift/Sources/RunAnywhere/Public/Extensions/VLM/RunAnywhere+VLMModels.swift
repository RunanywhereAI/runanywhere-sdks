//
//  RunAnywhere+VLMModels.swift
//  RunAnywhere SDK
//
//  VLM model loading helpers.
//

import Foundation

private let vlmLogger = SDKLogger(category: "VLM.Models")

// MARK: - VLM Model Loading

public extension RunAnywhere {

    /// Load a VLM model from a ModelInfo
    /// - Parameter model: The model to load (must have localPath set)
    /// - Throws: SDKError if loading fails
    static func loadVLMModel(_ model: ModelInfo) async throws {
        vlmLogger.info("Loading VLM model: \(model.id)")

        // Use the same model path resolution as LLM loading
        // This properly finds the .gguf file in the model folder
        let modelFolder = try CppBridge.ModelPaths.getModelFolder(modelId: model.id, framework: model.framework)
        vlmLogger.info("Model folder: \(modelFolder.path)")

        // Resolve the actual model file path (same logic as LLM)
        let modelPath = try resolveVLMModelFilePath(modelFolder: modelFolder, model: model)
        vlmLogger.info("Resolved model path: \(modelPath.path)")

        // Get the model directory for finding mmproj
        let modelDir = modelPath.deletingLastPathComponent()

        // Try to find mmproj file in same directory
        let mmprojPath = findMmprojFile(in: modelDir)
        vlmLogger.info("mmproj path: \(mmprojPath ?? "not found")")

        try await loadVLMModel(
            modelPath.path,
            mmprojPath: mmprojPath,
            modelId: model.id,
            modelName: model.name
        )
    }

    /// Resolve VLM model file path (similar to LLM path resolution)
    private static func resolveVLMModelFilePath(modelFolder: URL, model: ModelInfo) throws -> URL {
        let fileManager = FileManager.default

        // Check if model folder exists
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: modelFolder.path, isDirectory: &isDir), isDir.boolValue else {
            vlmLogger.error("Model folder does not exist: \(modelFolder.path)")
            throw SDKError.vlm(.modelLoadFailed, "Model folder does not exist. Please download the model first.")
        }

        // List folder contents for debugging
        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: modelFolder.path)
            vlmLogger.info("Model folder contents (\(contents.count) items): \(contents.joined(separator: ", "))")
        } catch {
            vlmLogger.error("Failed to list model folder: \(error.localizedDescription)")
            throw SDKError.vlm(.modelLoadFailed, "Failed to read model folder: \(error.localizedDescription)")
        }

        // Find .gguf files that are NOT mmproj files (main model)
        let ggufFiles = contents.filter { $0.lowercased().hasSuffix(".gguf") }
        let mainModelFiles = ggufFiles.filter { !$0.lowercased().contains("mmproj") }

        vlmLogger.info("Found \(ggufFiles.count) .gguf files, \(mainModelFiles.count) main model files")

        if let mainModel = mainModelFiles.first {
            let modelPath = modelFolder.appendingPathComponent(mainModel)
            vlmLogger.info("Using main model file: \(modelPath.path)")
            return modelPath
        }

        // No main model file found
        vlmLogger.error("No main model .gguf file found in folder (only found: \(contents.joined(separator: ", ")))")
        throw SDKError.vlm(.modelLoadFailed, "No model file found. The model may not have been downloaded correctly.")
    }

    /// Find the main model .gguf file in a directory (excludes mmproj files)
    private static func findMainModelFile(in directory: URL) -> String? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }

        // Look for .gguf file that is NOT an mmproj file
        // Prefer files without "mmproj" in the name
        let ggufFiles = contents.filter { $0.lowercased().hasSuffix(".gguf") }

        // First try to find a non-mmproj file
        if let mainModel = ggufFiles.first(where: { !$0.lowercased().contains("mmproj") }) {
            return directory.appendingPathComponent(mainModel).path
        }

        // If only mmproj files exist, that's not a valid VLM model directory
        return nil
    }

    /// Find mmproj file in a directory
    private static func findMmprojFile(in directory: URL) -> String? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }

        // Look for mmproj file
        if let mmprojFile = contents.first(where: { $0.lowercased().contains("mmproj") && $0.lowercased().hasSuffix(".gguf") }) {
            return directory.appendingPathComponent(mmprojFile).path
        }

        return nil
    }
}
