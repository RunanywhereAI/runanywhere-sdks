import Foundation

/// SDK error codes
public enum ErrorCode: Int {
    // General errors (1000-1099)
    case unknown = 1000
    case invalidInput = 1001
    case notInitialized = 1002
    case alreadyInitialized = 1003
    case operationCancelled = 1004

    // Model errors (1100-1199)
    case modelNotFound = 1100
    case modelLoadFailed = 1101
    case modelValidationFailed = 1102
    case modelFormatUnsupported = 1103
    case modelCorrupted = 1104
    case modelIncompatible = 1105

    // Network errors (1200-1299)
    case networkUnavailable = 1200
    case networkTimeout = 1201
    case downloadFailed = 1202
    case uploadFailed = 1203
    case apiError = 1204

    // Storage errors (1300-1399)
    case insufficientStorage = 1300
    case storageFull = 1301
    case fileNotFound = 1302
    case fileAccessDenied = 1303
    case fileCorrupted = 1304

    // Hardware errors (1500-1599)
    case hardwareUnsupported = 1500
    case hardwareUnavailable = 1501

    // Authentication errors (1600-1699)
    case authenticationFailed = 1600
    case authenticationExpired = 1601
    case authorizationDenied = 1602
    case apiKeyInvalid = 1603

    // Generation errors (1700-1799)
    case generationFailed = 1700
    case generationTimeout = 1701
    case tokenLimitExceeded = 1702
    case costLimitExceeded = 1703
    case contextTooLong = 1704

    /// Get user-friendly error message
    public var message: String {
        switch self {
        case .unknown: return "An unknown error occurred"
        case .invalidInput: return "Invalid input provided"
        case .notInitialized: return "SDK not initialized"
        case .alreadyInitialized: return "SDK already initialized"
        case .operationCancelled: return "Operation was cancelled"

        case .modelNotFound: return "Model not found"
        case .modelLoadFailed: return "Failed to load model"
        case .modelValidationFailed: return "Model validation failed"
        case .modelFormatUnsupported: return "Model format not supported"
        case .modelCorrupted: return "Model file is corrupted"
        case .modelIncompatible: return "Model incompatible with device"

        case .networkUnavailable: return "Network unavailable"
        case .networkTimeout: return "Network request timed out"
        case .downloadFailed: return "Download failed"
        case .uploadFailed: return "Upload failed"
        case .apiError: return "API request failed"

        case .insufficientStorage: return "Insufficient storage space"
        case .storageFull: return "Storage is full"
        case .fileNotFound: return "File not found"
        case .fileAccessDenied: return "File access denied"
        case .fileCorrupted: return "File is corrupted"

        case .hardwareUnsupported: return "Hardware not supported"
        case .hardwareUnavailable: return "Hardware unavailable"

        case .authenticationFailed: return "Authentication failed"
        case .authenticationExpired: return "Authentication expired"
        case .authorizationDenied: return "Authorization denied"
        case .apiKeyInvalid: return "Invalid API key"

        case .generationFailed: return "Text generation failed"
        case .generationTimeout: return "Generation timed out"
        case .tokenLimitExceeded: return "Token limit exceeded"
        case .costLimitExceeded: return "Cost limit exceeded"
        case .contextTooLong: return "Context too long"
        }
    }
}
