import Foundation

/// Validation error types
public enum ValidationError: LocalizedError {
    case checksumMismatch(expected: String, actual: String)
    case invalidFormat(expected: ModelFormat, actual: String?)
    case missingDependencies([MissingDependency])
    case corruptedFile(reason: String)
    case incompatibleVersion(required: String, found: String)
    case invalidMetadata(reason: String)
    case fileSizeMismatch(expected: Int64, actual: Int64)
    case missingRequiredFiles([String])
    case unsupportedArchitecture(String)
    case invalidSignature

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch: expected \(expected), got \(actual)"
        case .invalidFormat(let expected, let actual):
            return "Invalid format: expected \(expected.rawValue), got \(actual ?? "unknown")"
        case .missingDependencies(let deps):
            return "Missing dependencies: \(deps.map { $0.name }.joined(separator: ", "))"
        case .corruptedFile(let reason):
            return "File corrupted: \(reason)"
        case .incompatibleVersion(let required, let found):
            return "Incompatible version: requires \(required), found \(found)"
        case .invalidMetadata(let reason):
            return "Invalid metadata: \(reason)"
        case .fileSizeMismatch(let expected, let actual):
            return "File size mismatch: expected \(expected) bytes, got \(actual) bytes"
        case .missingRequiredFiles(let files):
            return "Missing required files: \(files.joined(separator: ", "))"
        case .unsupportedArchitecture(let arch):
            return "Unsupported architecture: \(arch)"
        case .invalidSignature:
            return "Invalid model signature"
        }
    }
}
