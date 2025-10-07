import Foundation

/// Validator for GGUF (GPT-Generated Unified Format) models
public class GGUFValidator {

    // MARK: - Properties

    private let logger = SDKLogger(category: "GGUFValidator")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Validates a GGUF model
    /// - Parameter url: The URL of the model file
    /// - Returns: Array of validation errors, nil if valid
    public func validate(at url: URL) async throws -> [ValidationError]? {
        logger.debug("Validating GGUF model: \(url.lastPathComponent)")

        guard let file = try? FileHandle(forReadingFrom: url) else {
            return [.corruptedFile(reason: "Cannot open model file")]
        }
        defer { try? file.close() }

        // Check GGUF magic bytes
        let magic = file.readData(ofLength: 4)
        guard String(data: magic, encoding: .utf8) == "GGUF" else {
            logger.error("Invalid GGUF magic bytes")
            return [.invalidFormat(expected: .gguf, actual: "unknown")]
        }

        // Read version
        let versionData = file.readData(ofLength: 4)
        guard versionData.count == 4 else {
            return [.corruptedFile(reason: "Cannot read GGUF version")]
        }

        let version = versionData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        logger.debug("GGUF version: \(version)")

        // Currently support GGUF v2 and v3
        guard version >= 2 && version <= 3 else {
            return [.incompatibleVersion(required: "2-3", found: String(version))]
        }

        // Read tensor count
        let tensorCountData = file.readData(ofLength: 8)
        guard tensorCountData.count == 8 else {
            return [.corruptedFile(reason: "Cannot read tensor count")]
        }

        let tensorCount = tensorCountData.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        logger.debug("Tensor count: \(tensorCount)")

        // Sanity check tensor count
        guard tensorCount > 0 && tensorCount < 100000 else {
            return [.corruptedFile(reason: "Invalid tensor count: \(tensorCount)")]
        }

        logger.info("GGUF model validated successfully")
        return nil
    }
}
