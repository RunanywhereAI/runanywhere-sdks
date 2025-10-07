import Foundation

/// Validator for TensorFlow Lite models
public class TFLiteValidator {

    // MARK: - Properties

    private let logger = SDKLogger(category: "TFLiteValidator")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Validates a TensorFlow Lite model
    /// - Parameter url: The URL of the model file
    /// - Returns: Array of validation errors, nil if valid
    public func validate(at url: URL) async throws -> [ValidationError]? {
        logger.debug("Validating TFLite model: \(url.lastPathComponent)")

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return [.corruptedFile(reason: "Cannot read model file")]
        }

        // TFLite files have a specific header structure
        guard data.count >= 20 else {
            return [.corruptedFile(reason: "File too small to be a valid TFLite model")]
        }

        // Check TFLite magic bytes (offset 4-7 should contain "TFL3")
        let magicBytes = data.subdata(in: 4..<8)
        let magic = String(data: magicBytes, encoding: .ascii)

        guard magic == "TFL3" else {
            logger.error("Invalid TFLite magic bytes: \(magic ?? "nil")")
            return [.invalidFormat(expected: .tflite, actual: "unknown")]
        }

        // Basic structure validation
        let identifier = data.subdata(in: 0..<4)
        if identifier != Data([0x18, 0x00, 0x00, 0x00]) &&
           identifier != Data([0x1C, 0x00, 0x00, 0x00]) {
            logger.warning("Unexpected TFLite identifier")
        }

        logger.info("TFLite model validated successfully")
        return nil
    }
}
