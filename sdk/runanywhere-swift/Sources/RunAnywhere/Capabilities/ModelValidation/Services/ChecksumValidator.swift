import Foundation
import CryptoKit

/// Service for validating file checksums
public class ChecksumValidator {

    // MARK: - Properties

    private let logger = SDKLogger(category: "ChecksumValidator")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Validates the checksum of a file
    /// - Parameters:
    ///   - file: The URL of the file to validate
    ///   - expected: The expected checksum value
    ///   - algorithm: The checksum algorithm to use (default: SHA256)
    /// - Returns: True if the checksum matches, false otherwise
    /// - Throws: An error if the file cannot be read
    public func validate(_ file: URL, expected: String, algorithm: ChecksumAlgorithm = .sha256) async throws -> Bool {
        logger.debug("Validating checksum for file: \(file.lastPathComponent)")

        let calculated = try await calculateChecksum(for: file, using: algorithm)
        let isValid = calculated.lowercased() == expected.lowercased()

        if !isValid {
            logger.warning("Checksum mismatch - expected: \(expected), calculated: \(calculated)")
        }

        return isValid
    }

    /// Calculates the checksum of a file
    /// - Parameters:
    ///   - url: The URL of the file
    ///   - algorithm: The checksum algorithm to use
    /// - Returns: The calculated checksum as a hex string
    /// - Throws: An error if the file cannot be read
    public func calculateChecksum(for url: URL, using algorithm: ChecksumAlgorithm) async throws -> String {
        let data = try Data(contentsOf: url)

        switch algorithm {
        case .sha256:
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        case .sha512:
            let hash = SHA512.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        case .md5:
            // MD5 is deprecated but still used by some models
            let hash = Insecure.MD5.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }
    }
}

// MARK: - Supporting Types

/// Supported checksum algorithms
public enum ChecksumAlgorithm {
    case sha256
    case sha512
    case md5
}
