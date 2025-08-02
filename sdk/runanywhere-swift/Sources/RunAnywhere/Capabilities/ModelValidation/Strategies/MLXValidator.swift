import Foundation

/// Validator for MLX models
public class MLXValidator {

    // MARK: - Properties

    private let logger = SDKLogger(category: "MLXValidator")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Validates an MLX model
    /// - Parameter url: The URL of the model file
    /// - Returns: Array of validation errors, nil if valid
    public func validate(at url: URL) async throws -> [ValidationError]? {
        logger.debug("Validating MLX model: \(url.lastPathComponent)")

        // MLX models are typically directories containing safetensors files
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return [.corruptedFile(reason: "Model path does not exist")]
        }

        if isDirectory.boolValue {
            return validateMLXDirectory(at: url)
        } else {
            return validateMLXFile(at: url)
        }
    }

    // MARK: - Private Methods

    private func validateMLXDirectory(at url: URL) -> [ValidationError]? {
        var errors: [ValidationError] = []

        // Check for required files in MLX model directory
        let requiredFiles = ["config.json", "model.safetensors"]
        var missingFiles: [String] = []

        for file in requiredFiles {
            let filePath = url.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: filePath.path) {
                // Check for alternative names
                if file == "model.safetensors" {
                    // Could be split into multiple files
                    let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    let hasSafetensors = contents?.contains { $0.pathExtension == "safetensors" } ?? false
                    if !hasSafetensors {
                        missingFiles.append(file)
                    }
                } else {
                    missingFiles.append(file)
                }
            }
        }

        if !missingFiles.isEmpty {
            errors.append(.missingRequiredFiles(missingFiles))
            logger.error("Missing required files: \(missingFiles)")
        }

        // Validate config.json if present
        let configPath = url.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configPath.path) {
            if let configData = try? Data(contentsOf: configPath),
               let _ = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                logger.debug("Valid config.json found")
            } else {
                errors.append(.invalidMetadata(reason: "Invalid or corrupted config.json"))
            }
        }

        return errors.isEmpty ? nil : errors
    }

    private func validateMLXFile(at url: URL) -> [ValidationError]? {
        // For single MLX files, check if it's a valid safetensors file
        guard url.pathExtension == "safetensors" else {
            return [.invalidFormat(expected: .safetensors, actual: url.pathExtension)]
        }

        // Basic safetensors validation
        guard let file = try? FileHandle(forReadingFrom: url) else {
            return [.corruptedFile(reason: "Cannot open model file")]
        }
        defer { try? file.close() }

        // First 8 bytes contain header size
        let headerSizeData = file.readData(ofLength: 8)
        guard headerSizeData.count == 8 else {
            return [.corruptedFile(reason: "Invalid safetensors header")]
        }

        logger.info("MLX model validated successfully")
        return nil
    }
}
