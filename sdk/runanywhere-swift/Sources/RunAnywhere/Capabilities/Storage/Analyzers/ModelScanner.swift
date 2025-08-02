import Foundation

/// Scans for stored models in the file system
public class ModelScanner {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logger = SDKLogger(category: "ModelScanner")

    // MARK: - Public Methods

    /// Scan for models in a directory
    public func scanForModels(in directory: URL) async -> [StoredModel] {
        var models: [StoredModel] = []

        guard fileManager.fileExists(atPath: directory.path) else { return models }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            for url in contents {
                if let model = await scanModelFile(at: url) {
                    models.append(model)
                }
            }

            // Also scan subdirectories
            for url in contents {
                if isDirectory(url) {
                    let subModels = await scanForModels(in: url)
                    models.append(contentsOf: subModels)
                }
            }

        } catch {
            logger.error("Failed to scan directory \(directory.path): \(error)")
        }

        return models
    }

    /// Scan a specific file to see if it's a model
    public func scanModelFile(at url: URL) async -> StoredModel? {
        // Check if it's a model file based on extension
        guard let format = ModelFormat(rawValue: url.pathExtension) else { return nil }

        do {
            let resourceValues = try url.resourceValues(
                forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
            )

            let model = StoredModel(
                name: extractModelName(from: url),
                path: url,
                size: Int64(resourceValues.fileSize ?? 0),
                format: format,
                framework: await detectFramework(from: url, format: format),
                createdDate: resourceValues.creationDate ?? Date(),
                lastUsed: resourceValues.contentModificationDate
            )

            return model

        } catch {
            logger.error("Failed to scan model file at \(url.path): \(error)")
            return nil
        }
    }

    /// Find models by name pattern
    public func findModels(matching pattern: String, in directory: URL) async -> [StoredModel] {
        let allModels = await scanForModels(in: directory)

        return allModels.filter { model in
            model.name.lowercased().contains(pattern.lowercased())
        }
    }

    /// Find models by framework
    public func findModels(framework: LLMFramework, in directory: URL) async -> [StoredModel] {
        let allModels = await scanForModels(in: directory)

        return allModels.filter { model in
            model.framework == framework
        }
    }

    /// Get model metadata if available
    public func getModelMetadata(at modelURL: URL) async -> ModelInfo? {
        let metadataURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent("metadata.json")

        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: metadataURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return parseModelInfoFromJSON(json, url: modelURL)
            }
            return nil
        } catch {
            logger.debug("No metadata found for model at \(modelURL.path)")
            return nil
        }
    }

    // MARK: - Private Methods

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func extractModelName(from url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent

        // Clean up common suffixes
        let cleanedName = filename
            .replacingOccurrences(of: "_model", with: "")
            .replacingOccurrences(of: "-model", with: "")
            .replacingOccurrences(of: ".model", with: "")

        return cleanedName
    }

    private func detectFramework(from url: URL, format: ModelFormat) async -> LLMFramework? {
        // Try to extract framework from directory structure
        let pathComponents = url.pathComponents

        for component in pathComponents {
            if let framework = LLMFramework(rawValue: component) {
                return framework
            }
        }

        // Try to detect from file content or format
        switch format {
        case .mlmodel, .mlpackage:
            return .coreML
        case .tflite:
            return .tensorFlowLite
        case .gguf, .ggml:
            return .llamaCpp
        case .onnx, .ort:
            return .onnx
        case .pte:
            return .execuTorch
        default:
            // Try to infer from metadata
            if let metadata = await getModelMetadata(at: url) {
                return metadata.preferredFramework
            }
            return nil
        }
    }

    /// Parse ModelInfo from JSON dictionary
    private func parseModelInfoFromJSON(_ json: [String: Any], url: URL) -> ModelInfo? {
        guard let id = json["id"] as? String,
              let name = json["name"] as? String,
              let formatString = json["format"] as? String,
              let format = ModelFormat(rawValue: formatString) else {
            return nil
        }

        let downloadURL = (json["downloadURL"] as? String).flatMap { URL(string: $0) }
        let estimatedMemory = json["estimatedMemory"] as? Int64 ?? 1_000_000_000
        let contextLength = json["contextLength"] as? Int ?? 2048
        let downloadSize = json["downloadSize"] as? Int64
        let checksum = json["checksum"] as? String

        let compatibleFrameworks: [LLMFramework] = {
            if let frameworkStrings = json["compatibleFrameworks"] as? [String] {
                return frameworkStrings.compactMap { LLMFramework(rawValue: $0) }
            }
            return []
        }()

        let preferredFramework: LLMFramework? = {
            if let frameworkString = json["preferredFramework"] as? String {
                return LLMFramework(rawValue: frameworkString)
            }
            return nil
        }()

        return ModelInfo(
            id: id,
            name: name,
            format: format,
            downloadURL: downloadURL,
            localPath: url,
            estimatedMemory: estimatedMemory,
            contextLength: contextLength,
            downloadSize: downloadSize,
            checksum: checksum,
            compatibleFrameworks: compatibleFrameworks,
            preferredFramework: preferredFramework,
            additionalProperties: json
        )
    }
}
