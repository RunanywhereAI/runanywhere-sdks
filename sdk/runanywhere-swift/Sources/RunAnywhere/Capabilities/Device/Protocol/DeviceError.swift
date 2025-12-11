//
//  DeviceError.swift
//  RunAnywhere SDK
//
//  Typed errors for device operations
//

import Foundation

/// Errors that can occur during device operations
public enum DeviceError: Error, LocalizedError, Sendable {

    // MARK: - Identity Errors

    /// Failed to generate device UUID
    case uuidGenerationFailed(reason: String)

    /// Invalid UUID format
    case invalidUUIDFormat(uuid: String)

    // MARK: - Keychain Errors

    /// Failed to store data in keychain
    case keychainStoreFailed(reason: String)

    /// Failed to retrieve data from keychain
    case keychainRetrieveFailed(reason: String)

    // MARK: - Fingerprint Errors

    /// Failed to generate device fingerprint
    case fingerprintGenerationFailed(reason: String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .uuidGenerationFailed(let reason):
            return "Failed to generate device UUID: \(reason)"
        case .invalidUUIDFormat(let uuid):
            return "Invalid UUID format: \(uuid)"
        case .keychainStoreFailed(let reason):
            return "Failed to store in keychain: \(reason)"
        case .keychainRetrieveFailed(let reason):
            return "Failed to retrieve from keychain: \(reason)"
        case .fingerprintGenerationFailed(let reason):
            return "Failed to generate device fingerprint: \(reason)"
        }
    }
}
