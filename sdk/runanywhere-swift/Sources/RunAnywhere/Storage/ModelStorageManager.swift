import Foundation
import Files

/// Simple storage manager for organizing models by framework type
public class SimpleModelStorageManager {
    private let rootFolder: Folder

    /// Supported AI frameworks
    public enum Framework: String, CaseIterable {
        case gguf = "GGUF"
        case coreML = "CoreML"
        case onnx = "ONNX"
        case tensorFlowLite = "TensorFlowLite"
        case mlx = "MLX"
    }

    /// Initialize storage manager with RunAnywhere folder in Documents
    public init() throws {
        guard let documentsFolder = Folder.documents else {
            throw NSError(domain: "SimpleModelStorageManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access Documents folder"])
        }

        // Create or get existing RunAnywhere folder
        if let existingFolder = try? documentsFolder.subfolder(named: "RunAnywhere") {
            self.rootFolder = existingFolder
        } else {
            self.rootFolder = try documentsFolder.createSubfolder(named: "RunAnywhere")
        }
    }

    /// Get or create folder for a specific model
    public func getModelFolder(framework: Framework, modelId: String) throws -> Folder {
        // Create or get Models folder
        let modelsFolder: Folder
        if let existingModels = try? rootFolder.subfolder(named: "Models") {
            modelsFolder = existingModels
        } else {
            modelsFolder = try rootFolder.createSubfolder(named: "Models")
        }

        // Create or get framework folder
        let frameworkFolder: Folder
        if let existingFramework = try? modelsFolder.subfolder(named: framework.rawValue) {
            frameworkFolder = existingFramework
        } else {
            frameworkFolder = try modelsFolder.createSubfolder(named: framework.rawValue)
        }

        // Create or get model folder
        if let existingModel = try? frameworkFolder.subfolder(named: modelId) {
            return existingModel
        } else {
            return try frameworkFolder.createSubfolder(named: modelId)
        }
    }

    /// Get path to model file if it exists
    public func getModelPath(framework: Framework, modelId: String) throws -> URL? {
        let modelFolder = try getModelFolder(framework: framework, modelId: modelId)

        // Find the model file in the folder
        for file in modelFolder.files {
            if isModelFile(file, framework: framework) {
                return file.url
            }
        }

        return nil
    }

    /// Check if file is a valid model file for the framework
    private func isModelFile(_ file: File, framework: Framework) -> Bool {
        switch framework {
        case .gguf:
            return file.extension == "gguf"
        case .coreML:
            return file.extension == "mlmodel" || file.extension == "mlpackage"
        case .onnx:
            return file.extension == "onnx"
        case .tensorFlowLite:
            return file.extension == "tflite"
        case .mlx:
            return file.extension == "safetensors"
        }
    }

    /// List all models for a specific framework
    public func listModels(for framework: Framework) throws -> [String] {
        let modelsFolder = try rootFolder.subfolder(named: "Models")
        guard let frameworkFolder = try? modelsFolder.subfolder(named: framework.rawValue) else {
            return []
        }

        return frameworkFolder.subfolders.map { $0.name }
    }

    /// Delete a model
    public func deleteModel(framework: Framework, modelId: String) throws {
        if let modelFolder = try? getModelFolder(framework: framework, modelId: modelId) {
            try modelFolder.delete()
        }
    }

    /// Check if model exists
    public func modelExists(framework: Framework, modelId: String) -> Bool {
        return (try? getModelPath(framework: framework, modelId: modelId)) != nil
    }

    /// Get total size of all models for a framework
    public func getFrameworkSize(framework: Framework) throws -> Int64 {
        let modelsFolder = try rootFolder.subfolder(named: "Models")
        guard let frameworkFolder = try? modelsFolder.subfolder(named: framework.rawValue) else {
            return 0
        }

        var totalSize: Int64 = 0
        for modelFolder in frameworkFolder.subfolders {
            for file in modelFolder.files {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        totalSize += fileSize
                    }
                } catch {
                    // Skip files that can't be read
                    continue
                }
            }
        }

        return totalSize
    }

    /// Get root RunAnywhere folder
    public func getRootFolder() -> Folder {
        return rootFolder
    }

    /// Clean up any temporary files
    public func cleanupTempFiles() throws {
        let tempFolder = try? rootFolder.subfolder(named: "Temp")
        try tempFolder?.delete()
    }
}
