import Foundation

/// Centralized utility for calculating model paths and directories.
/// Follows the structure: `Documents/RunAnywhere/Models/{framework.rawValue}/{modelId}/`
///
/// This utility ensures consistent path calculation across the entire SDK,
/// preventing scattered path logic and reducing potential bugs.
public struct ModelPathUtils {

    // MARK: - Base Directories

    /// Get the base RunAnywhere directory in Documents
    /// - Returns: URL to `Documents/RunAnywhere/`
    /// - Throws: If Documents directory is not accessible
    public static func getBaseDirectory() throws -> URL {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RunAnywhereError.storageError("Documents directory not accessible")
        }
        return documentsURL.appendingPathComponent("RunAnywhere", isDirectory: true)
    }

    /// Get the models directory
    /// - Returns: URL to `Documents/RunAnywhere/Models/`
    /// - Throws: If base directory cannot be accessed
    public static func getModelsDirectory() throws -> URL {
        return try getBaseDirectory().appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: - Framework-Specific Paths

    /// Get the folder for a specific framework
    /// - Parameter framework: The ML framework
    /// - Returns: URL to `Documents/RunAnywhere/Models/{framework.rawValue}/`
    /// - Throws: If models directory cannot be accessed
    public static func getFrameworkDirectory(framework: LLMFramework) throws -> URL {
        return try getModelsDirectory().appendingPathComponent(framework.rawValue, isDirectory: true)
    }

    /// Get the folder for a specific model within a framework
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - framework: The ML framework
    /// - Returns: URL to `Documents/RunAnywhere/Models/{framework.rawValue}/{modelId}/`
    /// - Throws: If framework directory cannot be accessed
    public static func getModelFolder(modelId: String, framework: LLMFramework) throws -> URL {
        return try getFrameworkDirectory(framework: framework)
            .appendingPathComponent(modelId, isDirectory: true)
    }

    /// Get the folder for a model (legacy path without framework)
    /// - Parameter modelId: The model identifier
    /// - Returns: URL to `Documents/RunAnywhere/Models/{modelId}/`
    /// - Throws: If models directory cannot be accessed
    public static func getModelFolder(modelId: String) throws -> URL {
        return try getModelsDirectory().appendingPathComponent(modelId, isDirectory: true)
    }

    // MARK: - Model File Paths

    /// Get the full path to a model file
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - framework: The ML framework
    ///   - format: The model file format
    /// - Returns: URL to `Documents/RunAnywhere/Models/{framework.rawValue}/{modelId}/{modelId}.{format.rawValue}`
    /// - Throws: If model folder cannot be accessed
    public static func getModelFilePath(modelId: String, framework: LLMFramework, format: ModelFormat) throws -> URL {
        let fileName = "\(modelId).\(format.rawValue)"
        return try getModelFolder(modelId: modelId, framework: framework)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Get the full path to a model file (legacy path without framework)
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - format: The model file format
    /// - Returns: URL to `Documents/RunAnywhere/Models/{modelId}/{modelId}.{format.rawValue}`
    /// - Throws: If model folder cannot be accessed
    public static func getModelFilePath(modelId: String, format: ModelFormat) throws -> URL {
        let fileName = "\(modelId).\(format.rawValue)"
        return try getModelFolder(modelId: modelId)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Get the expected model path from ModelInfo
    /// - Parameter modelInfo: The model information
    /// - Returns: URL to the expected model path based on framework and format
    /// - Throws: If model folder cannot be accessed
    public static func getModelPath(modelInfo: ModelInfo) throws -> URL {
        // Use preferred framework if available, otherwise use first compatible framework
        if let framework = modelInfo.preferredFramework ?? modelInfo.compatibleFrameworks.first {
            // For directory-based models (e.g., WhisperKit, CoreML packages), return the folder
            if modelInfo.format.isDirectoryBased {
                return try getModelFolder(modelId: modelInfo.id, framework: framework)
            }
            // For single-file models, return the full file path
            return try getModelFilePath(modelId: modelInfo.id, framework: framework, format: modelInfo.format)
        } else {
            // Legacy fallback without framework
            if modelInfo.format.isDirectoryBased {
                return try getModelFolder(modelId: modelInfo.id)
            }
            return try getModelFilePath(modelId: modelInfo.id, format: modelInfo.format)
        }
    }

    /// Get the expected model path from components
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - framework: The ML framework (optional)
    ///   - format: The model file format
    /// - Returns: URL to the expected model path
    /// - Throws: If model folder cannot be accessed
    public static func getExpectedModelPath(modelId: String, framework: LLMFramework?, format: ModelFormat) throws -> URL {
        if let framework = framework {
            if format.isDirectoryBased {
                return try getModelFolder(modelId: modelId, framework: framework)
            }
            return try getModelFilePath(modelId: modelId, framework: framework, format: format)
        } else {
            if format.isDirectoryBased {
                return try getModelFolder(modelId: modelId)
            }
            return try getModelFilePath(modelId: modelId, format: format)
        }
    }

    // MARK: - Other Directories

    /// Get the cache directory
    /// - Returns: URL to `Documents/RunAnywhere/Cache/`
    /// - Throws: If base directory cannot be accessed
    public static func getCacheDirectory() throws -> URL {
        return try getBaseDirectory().appendingPathComponent("Cache", isDirectory: true)
    }

    /// Get the temporary files directory
    /// - Returns: URL to `Documents/RunAnywhere/Temp/`
    /// - Throws: If base directory cannot be accessed
    public static func getTempDirectory() throws -> URL {
        return try getBaseDirectory().appendingPathComponent("Temp", isDirectory: true)
    }

    /// Get the downloads directory
    /// - Returns: URL to `Documents/RunAnywhere/Downloads/`
    /// - Throws: If base directory cannot be accessed
    public static func getDownloadsDirectory() throws -> URL {
        return try getBaseDirectory().appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: - Path Analysis

    /// Extract model ID from a file path
    /// - Parameter path: The file path
    /// - Returns: The model ID if found, nil otherwise
    public static func extractModelId(from path: URL) -> String? {
        let pathComponents = path.pathComponents

        // Check if this is a model in our framework structure
        if let modelsIndex = pathComponents.firstIndex(of: "Models"),
           modelsIndex + 1 < pathComponents.count {

            let nextComponent = pathComponents[modelsIndex + 1]

            // Check if next component is a framework name
            if LLMFramework.allCases.contains(where: { $0.rawValue == nextComponent }),
               modelsIndex + 2 < pathComponents.count {
                // Framework structure: Models/framework/modelId
                return pathComponents[modelsIndex + 2]
            } else {
                // Direct model folder structure: Models/modelId
                return nextComponent
            }
        }

        return nil
    }

    /// Extract framework from a file path
    /// - Parameter path: The file path
    /// - Returns: The framework if found, nil otherwise
    public static func extractFramework(from path: URL) -> LLMFramework? {
        let pathComponents = path.pathComponents

        if let modelsIndex = pathComponents.firstIndex(of: "Models"),
           modelsIndex + 1 < pathComponents.count {
            let nextComponent = pathComponents[modelsIndex + 1]

            // Check if next component is a framework name
            return LLMFramework.allCases.first(where: { $0.rawValue == nextComponent })
        }

        return nil
    }

    /// Check if a path is within the models directory
    /// - Parameter path: The file path to check
    /// - Returns: true if the path is within the models directory
    public static func isModelPath(_ path: URL) -> Bool {
        return path.pathComponents.contains("Models")
    }
}

// MARK: - ModelFormat Extensions

extension ModelFormat {
    /// Whether this format represents a directory-based model
    var isDirectoryBased: Bool {
        switch self {
        case .mlmodel, .mlpackage:
            return true
        default:
            return false
        }
    }
}
