import Foundation

/// Validator for ONNX models
public class ONNXValidator {

    // MARK: - Properties

    private let logger = SDKLogger(category: "ONNXValidator")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Validates an ONNX model
    /// - Parameter url: The URL of the model file
    /// - Returns: Array of validation errors, nil if valid
    public func validate(at url: URL) async throws -> [ValidationError]? {
        logger.debug("Validating ONNX model: \(url.lastPathComponent)")

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return [.corruptedFile(reason: "Cannot read model file")]
        }

        // ONNX files are protobuf format
        // Basic validation: check if it starts with valid protobuf data
        guard data.count >= 8 else {
            return [.corruptedFile(reason: "File too small to be a valid ONNX model")]
        }

        // ONNX models typically start with 0x08 (protobuf field header)
        // This is a simplified check - full validation would require protobuf parsing
        let firstByte = data[0]
        if firstByte != 0x08 && firstByte != 0x0A {
            logger.warning("File doesn't appear to be a valid ONNX protobuf")
            return [.invalidFormat(expected: .onnx, actual: "unknown")]
        }

        // Check for "onnx" string in the first 100 bytes (common in ONNX files)
        let headerData = data.prefix(100)
        if let headerString = String(data: headerData, encoding: .ascii),
           !headerString.contains("onnx") && !headerString.contains("ONNX") {
            logger.warning("ONNX identifier not found in header")
        }

        logger.info("ONNX model validated successfully")
        return nil
    }
}
