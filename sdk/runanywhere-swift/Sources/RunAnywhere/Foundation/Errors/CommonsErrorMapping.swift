import CRACommons
import Foundation

// MARK: - Commons Error Mapping

/// Maps RAC_ERROR_* codes from runanywhere-commons to Swift SDKError.
///
/// This is the single source of truth for C++ ↔ Swift error code translation.
/// C++ error codes are defined in `rac_error.h` and mirror Swift's `ErrorCode` enum.
///
/// ## Error Code Ranges (C++)
/// - Initialization: -100 to -109
/// - Model: -110 to -129
/// - Generation: -130 to -149
/// - Network: -150 to -179
/// - Storage: -180 to -219
/// - Hardware: -220 to -229
/// - Component State: -230 to -249
/// - Validation: -250 to -279
/// - Audio: -280 to -299
/// - Language/Voice: -300 to -319
/// - Authentication: -320 to -329
/// - Security: -330 to -349
/// - Extraction: -350 to -369
/// - Calibration: -370 to -379
/// - Cancellation: -380 to -389
/// - Module/Service: -400 to -499
/// - Platform Adapter: -500 to -599
/// - Backend: -600 to -699
/// - Event: -700 to -799
/// - Other: -800 to -899
public enum CommonsErrorMapping {

    // MARK: - C++ to Swift

    /// Converts a rac_result_t error code to SDKError.
    ///
    /// - Parameter result: The C error code from runanywhere-commons
    /// - Returns: Corresponding SDKError, or nil if result is RAC_SUCCESS
    public static func toSDKError(_ result: rac_result_t) -> SDKError? {
        guard result != RAC_SUCCESS else { return nil }

        let (errorCode, errorMessage) = mapErrorCode(result)
        return SDKError.general(errorCode, errorMessage)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func mapErrorCode(_ result: rac_result_t) -> (ErrorCode, String) {
        // Delegate to category-specific mappers to reduce cyclomatic complexity
        if let mapped = mapInitializationError(result) { return mapped }
        if let mapped = mapModelError(result) { return mapped }
        if let mapped = mapGenerationError(result) { return mapped }
        if let mapped = mapNetworkError(result) { return mapped }
        if let mapped = mapStorageError(result) { return mapped }
        if let mapped = mapHardwareError(result) { return mapped }
        if let mapped = mapComponentStateError(result) { return mapped }
        if let mapped = mapValidationError(result) { return mapped }
        if let mapped = mapAudioError(result) { return mapped }
        if let mapped = mapLanguageVoiceError(result) { return mapped }
        if let mapped = mapAuthenticationError(result) { return mapped }
        if let mapped = mapSecurityError(result) { return mapped }
        if let mapped = mapExtractionError(result) { return mapped }
        if let mapped = mapCalibrationError(result) { return mapped }
        if let mapped = mapCancellationError(result) { return mapped }
        if let mapped = mapModuleServiceError(result) { return mapped }
        if let mapped = mapPlatformAdapterError(result) { return mapped }
        if let mapped = mapBackendError(result) { return mapped }
        if let mapped = mapEventError(result) { return mapped }
        if let mapped = mapOtherError(result) { return mapped }
        return (.unknown, "Unknown error code: \(result)")
    }

    // MARK: - Initialization Errors (-100 to -109)

    private static func mapInitializationError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_NOT_INITIALIZED: return (.notInitialized, "Component not initialized")
        case RAC_ERROR_ALREADY_INITIALIZED: return (.alreadyInitialized, "Already initialized")
        case RAC_ERROR_INITIALIZATION_FAILED: return (.initializationFailed, "Initialization failed")
        case RAC_ERROR_INVALID_CONFIGURATION: return (.invalidConfiguration, "Invalid configuration")
        case RAC_ERROR_INVALID_API_KEY: return (.invalidAPIKey, "Invalid API key")
        case RAC_ERROR_ENVIRONMENT_MISMATCH: return (.environmentMismatch, "Environment mismatch")
        case RAC_ERROR_INVALID_PARAMETER: return (.invalidConfiguration, "Invalid parameter")
        default: return nil
        }
    }

    // MARK: - Model Errors (-110 to -129)

    private static func mapModelError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_MODEL_NOT_FOUND: return (.modelNotFound, "Model not found")
        case RAC_ERROR_MODEL_LOAD_FAILED: return (.modelLoadFailed, "Model load failed")
        case RAC_ERROR_MODEL_VALIDATION_FAILED: return (.modelValidationFailed, "Model validation failed")
        case RAC_ERROR_MODEL_INCOMPATIBLE: return (.modelIncompatible, "Model incompatible")
        case RAC_ERROR_INVALID_MODEL_FORMAT: return (.invalidModelFormat, "Invalid model format")
        case RAC_ERROR_MODEL_STORAGE_CORRUPTED: return (.modelStorageCorrupted, "Model storage corrupted")
        case RAC_ERROR_MODEL_NOT_LOADED: return (.notInitialized, "Model not loaded")
        default: return nil
        }
    }

    // MARK: - Generation Errors (-130 to -149)

    private static func mapGenerationError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_GENERATION_FAILED: return (.generationFailed, "Generation failed")
        case RAC_ERROR_GENERATION_TIMEOUT: return (.generationTimeout, "Generation timed out")
        case RAC_ERROR_CONTEXT_TOO_LONG: return (.contextTooLong, "Context too long")
        case RAC_ERROR_TOKEN_LIMIT_EXCEEDED: return (.tokenLimitExceeded, "Token limit exceeded")
        case RAC_ERROR_COST_LIMIT_EXCEEDED: return (.costLimitExceeded, "Cost limit exceeded")
        case RAC_ERROR_INFERENCE_FAILED: return (.generationFailed, "Inference failed")
        default: return nil
        }
    }

    // MARK: - Network Errors (-150 to -179)

    private static func mapNetworkError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_NETWORK_UNAVAILABLE: return (.networkUnavailable, "Network unavailable")
        case RAC_ERROR_NETWORK_ERROR: return (.networkError, "Network error")
        case RAC_ERROR_REQUEST_FAILED: return (.requestFailed, "Request failed")
        case RAC_ERROR_DOWNLOAD_FAILED: return (.downloadFailed, "Download failed")
        case RAC_ERROR_SERVER_ERROR: return (.serverError, "Server error")
        case RAC_ERROR_TIMEOUT: return (.timeout, "Request timed out")
        case RAC_ERROR_INVALID_RESPONSE: return (.invalidResponse, "Invalid response")
        case RAC_ERROR_HTTP_ERROR: return (.httpError, "HTTP error")
        case RAC_ERROR_CONNECTION_LOST: return (.connectionLost, "Connection lost")
        case RAC_ERROR_PARTIAL_DOWNLOAD: return (.partialDownload, "Partial download")
        case RAC_ERROR_HTTP_REQUEST_FAILED: return (.requestFailed, "HTTP request failed")
        case RAC_ERROR_HTTP_NOT_SUPPORTED: return (.notSupported, "HTTP not supported")
        default: return nil
        }
    }

    // MARK: - Storage Errors (-180 to -219)

    private static func mapStorageError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_INSUFFICIENT_STORAGE: return (.insufficientStorage, "Insufficient storage")
        case RAC_ERROR_STORAGE_FULL: return (.storageFull, "Storage full")
        case RAC_ERROR_STORAGE_ERROR: return (.storageError, "Storage error")
        case RAC_ERROR_FILE_NOT_FOUND: return (.fileNotFound, "File not found")
        case RAC_ERROR_FILE_READ_FAILED: return (.fileReadFailed, "File read failed")
        case RAC_ERROR_FILE_WRITE_FAILED: return (.fileWriteFailed, "File write failed")
        case RAC_ERROR_PERMISSION_DENIED: return (.permissionDenied, "Permission denied")
        case RAC_ERROR_DELETE_FAILED: return (.deleteFailed, "Delete failed")
        case RAC_ERROR_MOVE_FAILED: return (.moveFailed, "Move failed")
        case RAC_ERROR_DIRECTORY_CREATION_FAILED: return (.directoryCreationFailed, "Directory creation failed")
        case RAC_ERROR_DIRECTORY_NOT_FOUND: return (.directoryNotFound, "Directory not found")
        case RAC_ERROR_INVALID_PATH: return (.invalidPath, "Invalid path")
        case RAC_ERROR_INVALID_FILE_NAME: return (.invalidFileName, "Invalid file name")
        case RAC_ERROR_TEMP_FILE_CREATION_FAILED: return (.tempFileCreationFailed, "Temp file creation failed")
        default: return nil
        }
    }

    // MARK: - Hardware Errors (-220 to -229)

    private static func mapHardwareError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_HARDWARE_UNSUPPORTED: return (.hardwareUnsupported, "Hardware unsupported")
        case RAC_ERROR_INSUFFICIENT_MEMORY: return (.insufficientMemory, "Insufficient memory")
        default: return nil
        }
    }

    // MARK: - Component State Errors (-230 to -249)

    private static func mapComponentStateError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_COMPONENT_NOT_READY: return (.componentNotReady, "Component not ready")
        case RAC_ERROR_INVALID_STATE: return (.invalidState, "Invalid state")
        case RAC_ERROR_SERVICE_NOT_AVAILABLE: return (.serviceNotAvailable, "Service not available")
        case RAC_ERROR_SERVICE_BUSY: return (.serviceBusy, "Service busy")
        case RAC_ERROR_PROCESSING_FAILED: return (.processingFailed, "Processing failed")
        case RAC_ERROR_START_FAILED: return (.startFailed, "Start failed")
        case RAC_ERROR_NOT_SUPPORTED: return (.notSupported, "Not supported")
        default: return nil
        }
    }

    // MARK: - Validation Errors (-250 to -279)

    private static func mapValidationError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_VALIDATION_FAILED: return (.validationFailed, "Validation failed")
        case RAC_ERROR_INVALID_INPUT: return (.invalidInput, "Invalid input")
        case RAC_ERROR_INVALID_FORMAT: return (.invalidFormat, "Invalid format")
        case RAC_ERROR_EMPTY_INPUT: return (.emptyInput, "Empty input")
        case RAC_ERROR_TEXT_TOO_LONG: return (.textTooLong, "Text too long")
        case RAC_ERROR_INVALID_SSML: return (.invalidSSML, "Invalid SSML")
        case RAC_ERROR_INVALID_SPEAKING_RATE: return (.invalidSpeakingRate, "Invalid speaking rate")
        case RAC_ERROR_INVALID_PITCH: return (.invalidPitch, "Invalid pitch")
        case RAC_ERROR_INVALID_VOLUME: return (.invalidVolume, "Invalid volume")
        case RAC_ERROR_INVALID_ARGUMENT: return (.invalidInput, "Invalid argument")
        case RAC_ERROR_NULL_POINTER: return (.invalidInput, "Null pointer")
        case RAC_ERROR_BUFFER_TOO_SMALL: return (.invalidInput, "Buffer too small")
        default: return nil
        }
    }

    // MARK: - Audio Errors (-280 to -299)

    private static func mapAudioError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED: return (.audioFormatNotSupported, "Audio format not supported")
        case RAC_ERROR_AUDIO_SESSION_FAILED: return (.audioSessionFailed, "Audio session failed")
        case RAC_ERROR_MICROPHONE_PERMISSION_DENIED: return (.microphonePermissionDenied, "Microphone permission denied")
        case RAC_ERROR_INSUFFICIENT_AUDIO_DATA: return (.insufficientAudioData, "Insufficient audio data")
        case RAC_ERROR_EMPTY_AUDIO_BUFFER: return (.emptyAudioBuffer, "Empty audio buffer")
        case RAC_ERROR_AUDIO_SESSION_ACTIVATION_FAILED: return (.audioSessionActivationFailed, "Audio session activation failed")
        default: return nil
        }
    }

    // MARK: - Language/Voice Errors (-300 to -319)

    private static func mapLanguageVoiceError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_LANGUAGE_NOT_SUPPORTED: return (.languageNotSupported, "Language not supported")
        case RAC_ERROR_VOICE_NOT_AVAILABLE: return (.voiceNotAvailable, "Voice not available")
        case RAC_ERROR_STREAMING_NOT_SUPPORTED: return (.streamingNotSupported, "Streaming not supported")
        case RAC_ERROR_STREAM_CANCELLED: return (.streamCancelled, "Stream cancelled")
        default: return nil
        }
    }

    // MARK: - Authentication Errors (-320 to -329)

    private static func mapAuthenticationError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_AUTHENTICATION_FAILED: return (.authenticationFailed, "Authentication failed")
        case RAC_ERROR_UNAUTHORIZED: return (.unauthorized, "Unauthorized")
        case RAC_ERROR_FORBIDDEN: return (.forbidden, "Forbidden")
        default: return nil
        }
    }

    // MARK: - Security Errors (-330 to -349)

    private static func mapSecurityError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_KEYCHAIN_ERROR: return (.keychainError, "Keychain error")
        case RAC_ERROR_ENCODING_ERROR: return (.encodingError, "Encoding error")
        case RAC_ERROR_DECODING_ERROR: return (.decodingError, "Decoding error")
        case RAC_ERROR_SECURE_STORAGE_FAILED: return (.keychainError, "Secure storage failed")
        default: return nil
        }
    }

    // MARK: - Extraction Errors (-350 to -369)

    private static func mapExtractionError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_EXTRACTION_FAILED: return (.extractionFailed, "Extraction failed")
        case RAC_ERROR_CHECKSUM_MISMATCH: return (.checksumMismatch, "Checksum mismatch")
        case RAC_ERROR_UNSUPPORTED_ARCHIVE: return (.unsupportedArchive, "Unsupported archive")
        default: return nil
        }
    }

    // MARK: - Calibration Errors (-370 to -379)

    private static func mapCalibrationError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_CALIBRATION_FAILED: return (.calibrationFailed, "Calibration failed")
        case RAC_ERROR_CALIBRATION_TIMEOUT: return (.calibrationTimeout, "Calibration timed out")
        default: return nil
        }
    }

    // MARK: - Cancellation (-380 to -389)

    private static func mapCancellationError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_CANCELLED: return (.cancelled, "Operation cancelled")
        default: return nil
        }
    }

    // MARK: - Module/Service Errors (-400 to -499)

    private static func mapModuleServiceError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_MODULE_NOT_FOUND: return (.frameworkNotAvailable, "Module not found")
        case RAC_ERROR_MODULE_ALREADY_REGISTERED: return (.alreadyInitialized, "Module already registered")
        case RAC_ERROR_MODULE_LOAD_FAILED: return (.initializationFailed, "Module load failed")
        case RAC_ERROR_SERVICE_NOT_FOUND: return (.serviceNotAvailable, "Service not found")
        case RAC_ERROR_SERVICE_ALREADY_REGISTERED: return (.alreadyInitialized, "Service already registered")
        case RAC_ERROR_SERVICE_CREATE_FAILED: return (.initializationFailed, "Service creation failed")
        case RAC_ERROR_CAPABILITY_NOT_FOUND: return (.featureNotAvailable, "Capability not found")
        case RAC_ERROR_PROVIDER_NOT_FOUND: return (.serviceNotAvailable, "Provider not found")
        case RAC_ERROR_NO_CAPABLE_PROVIDER: return (.serviceNotAvailable, "No capable provider")
        case RAC_ERROR_NOT_FOUND: return (.modelNotFound, "Not found")
        default: return nil
        }
    }

    // MARK: - Platform Adapter Errors (-500 to -599)

    private static func mapPlatformAdapterError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_ADAPTER_NOT_SET: return (.notInitialized, "Platform adapter not set")
        default: return nil
        }
    }

    // MARK: - Backend Errors (-600 to -699)

    private static func mapBackendError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_BACKEND_NOT_FOUND: return (.frameworkNotAvailable, "Backend not found")
        case RAC_ERROR_BACKEND_NOT_READY: return (.componentNotReady, "Backend not ready")
        case RAC_ERROR_BACKEND_INIT_FAILED: return (.initializationFailed, "Backend initialization failed")
        case RAC_ERROR_BACKEND_BUSY: return (.serviceBusy, "Backend busy")
        case RAC_ERROR_INVALID_HANDLE: return (.invalidState, "Invalid handle")
        default: return nil
        }
    }

    // MARK: - Event Errors (-700 to -799)

    private static func mapEventError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_EVENT_INVALID_CATEGORY: return (.invalidInput, "Invalid event category")
        case RAC_ERROR_EVENT_SUBSCRIPTION_FAILED: return (.unknown, "Event subscription failed")
        case RAC_ERROR_EVENT_PUBLISH_FAILED: return (.unknown, "Event publish failed")
        default: return nil
        }
    }

    // MARK: - Other Errors (-800 to -899)

    private static func mapOtherError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_NOT_IMPLEMENTED: return (.notImplemented, "Not implemented")
        case RAC_ERROR_FEATURE_NOT_AVAILABLE: return (.featureNotAvailable, "Feature not available")
        case RAC_ERROR_FRAMEWORK_NOT_AVAILABLE: return (.frameworkNotAvailable, "Framework not available")
        case RAC_ERROR_UNSUPPORTED_MODALITY: return (.unsupportedModality, "Unsupported modality")
        case RAC_ERROR_UNKNOWN: return (.unknown, "Unknown error")
        case RAC_ERROR_INTERNAL: return (.unknown, "Internal error")
        default: return nil
        }
    }

    // MARK: - Swift to C++

    // Converts an SDKError to rac_result_t for passing errors back to C++.
    // Parameter error: The SDK error
    // Returns: Corresponding rac_result_t code
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public static func fromSDKError(_ error: SDKError) -> rac_result_t {
        switch error.code {
        // Initialization
        case .notInitialized: return RAC_ERROR_NOT_INITIALIZED
        case .alreadyInitialized: return RAC_ERROR_ALREADY_INITIALIZED
        case .initializationFailed: return RAC_ERROR_INITIALIZATION_FAILED
        case .invalidConfiguration: return RAC_ERROR_INVALID_CONFIGURATION
        case .invalidAPIKey: return RAC_ERROR_INVALID_API_KEY
        case .environmentMismatch: return RAC_ERROR_ENVIRONMENT_MISMATCH

        // Model
        case .modelNotFound: return RAC_ERROR_MODEL_NOT_FOUND
        case .modelLoadFailed: return RAC_ERROR_MODEL_LOAD_FAILED
        case .modelValidationFailed: return RAC_ERROR_MODEL_VALIDATION_FAILED
        case .modelIncompatible: return RAC_ERROR_MODEL_INCOMPATIBLE
        case .invalidModelFormat: return RAC_ERROR_INVALID_MODEL_FORMAT
        case .modelStorageCorrupted: return RAC_ERROR_MODEL_STORAGE_CORRUPTED

        // Generation
        case .generationFailed: return RAC_ERROR_GENERATION_FAILED
        case .generationTimeout: return RAC_ERROR_GENERATION_TIMEOUT
        case .contextTooLong: return RAC_ERROR_CONTEXT_TOO_LONG
        case .tokenLimitExceeded: return RAC_ERROR_TOKEN_LIMIT_EXCEEDED
        case .costLimitExceeded: return RAC_ERROR_COST_LIMIT_EXCEEDED

        // Network
        case .networkUnavailable: return RAC_ERROR_NETWORK_UNAVAILABLE
        case .networkError: return RAC_ERROR_NETWORK_ERROR
        case .requestFailed: return RAC_ERROR_REQUEST_FAILED
        case .downloadFailed: return RAC_ERROR_DOWNLOAD_FAILED
        case .serverError: return RAC_ERROR_SERVER_ERROR
        case .timeout: return RAC_ERROR_TIMEOUT
        case .invalidResponse: return RAC_ERROR_INVALID_RESPONSE
        case .httpError: return RAC_ERROR_HTTP_ERROR
        case .connectionLost: return RAC_ERROR_CONNECTION_LOST
        case .partialDownload: return RAC_ERROR_PARTIAL_DOWNLOAD

        // Storage
        case .insufficientStorage: return RAC_ERROR_INSUFFICIENT_STORAGE
        case .storageFull: return RAC_ERROR_STORAGE_FULL
        case .storageError: return RAC_ERROR_STORAGE_ERROR
        case .fileNotFound: return RAC_ERROR_FILE_NOT_FOUND
        case .fileReadFailed: return RAC_ERROR_FILE_READ_FAILED
        case .fileWriteFailed: return RAC_ERROR_FILE_WRITE_FAILED
        case .permissionDenied: return RAC_ERROR_PERMISSION_DENIED
        case .deleteFailed: return RAC_ERROR_DELETE_FAILED
        case .moveFailed: return RAC_ERROR_MOVE_FAILED
        case .directoryCreationFailed: return RAC_ERROR_DIRECTORY_CREATION_FAILED
        case .directoryNotFound: return RAC_ERROR_DIRECTORY_NOT_FOUND
        case .invalidPath: return RAC_ERROR_INVALID_PATH
        case .invalidFileName: return RAC_ERROR_INVALID_FILE_NAME
        case .tempFileCreationFailed: return RAC_ERROR_TEMP_FILE_CREATION_FAILED

        // Hardware
        case .hardwareUnsupported: return RAC_ERROR_HARDWARE_UNSUPPORTED
        case .insufficientMemory: return RAC_ERROR_INSUFFICIENT_MEMORY

        // Component State
        case .componentNotReady: return RAC_ERROR_COMPONENT_NOT_READY
        case .invalidState: return RAC_ERROR_INVALID_STATE
        case .serviceNotAvailable: return RAC_ERROR_SERVICE_NOT_AVAILABLE
        case .serviceBusy: return RAC_ERROR_SERVICE_BUSY
        case .processingFailed: return RAC_ERROR_PROCESSING_FAILED
        case .startFailed: return RAC_ERROR_START_FAILED
        case .notSupported: return RAC_ERROR_NOT_SUPPORTED

        // Validation
        case .validationFailed: return RAC_ERROR_VALIDATION_FAILED
        case .invalidInput: return RAC_ERROR_INVALID_INPUT
        case .invalidFormat: return RAC_ERROR_INVALID_FORMAT
        case .emptyInput: return RAC_ERROR_EMPTY_INPUT
        case .textTooLong: return RAC_ERROR_TEXT_TOO_LONG
        case .invalidSSML: return RAC_ERROR_INVALID_SSML
        case .invalidSpeakingRate: return RAC_ERROR_INVALID_SPEAKING_RATE
        case .invalidPitch: return RAC_ERROR_INVALID_PITCH
        case .invalidVolume: return RAC_ERROR_INVALID_VOLUME

        // Audio
        case .audioFormatNotSupported: return RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED
        case .audioSessionFailed: return RAC_ERROR_AUDIO_SESSION_FAILED
        case .microphonePermissionDenied: return RAC_ERROR_MICROPHONE_PERMISSION_DENIED
        case .insufficientAudioData: return RAC_ERROR_INSUFFICIENT_AUDIO_DATA
        case .emptyAudioBuffer: return RAC_ERROR_EMPTY_AUDIO_BUFFER
        case .audioSessionActivationFailed: return RAC_ERROR_AUDIO_SESSION_ACTIVATION_FAILED

        // Language/Voice
        case .languageNotSupported: return RAC_ERROR_LANGUAGE_NOT_SUPPORTED
        case .voiceNotAvailable: return RAC_ERROR_VOICE_NOT_AVAILABLE
        case .streamingNotSupported: return RAC_ERROR_STREAMING_NOT_SUPPORTED
        case .streamCancelled: return RAC_ERROR_STREAM_CANCELLED

        // Authentication
        case .authenticationFailed: return RAC_ERROR_AUTHENTICATION_FAILED
        case .unauthorized: return RAC_ERROR_UNAUTHORIZED
        case .forbidden: return RAC_ERROR_FORBIDDEN

        // Security
        case .keychainError: return RAC_ERROR_KEYCHAIN_ERROR
        case .encodingError: return RAC_ERROR_ENCODING_ERROR
        case .decodingError: return RAC_ERROR_DECODING_ERROR

        // Extraction
        case .extractionFailed: return RAC_ERROR_EXTRACTION_FAILED
        case .checksumMismatch: return RAC_ERROR_CHECKSUM_MISMATCH
        case .unsupportedArchive: return RAC_ERROR_UNSUPPORTED_ARCHIVE

        // Calibration
        case .calibrationFailed: return RAC_ERROR_CALIBRATION_FAILED
        case .calibrationTimeout: return RAC_ERROR_CALIBRATION_TIMEOUT

        // Cancellation
        case .cancelled: return RAC_ERROR_CANCELLED

        // Other
        case .notImplemented: return RAC_ERROR_NOT_IMPLEMENTED
        case .featureNotAvailable: return RAC_ERROR_FEATURE_NOT_AVAILABLE
        case .frameworkNotAvailable: return RAC_ERROR_FRAMEWORK_NOT_AVAILABLE
        case .unsupportedModality: return RAC_ERROR_UNSUPPORTED_MODALITY
        case .unknown: return RAC_ERROR_UNKNOWN
        }
    }

    // MARK: - Utility Methods

    /// Throws an SDKError if the result indicates failure.
    ///
    /// - Parameter result: The rac_result_t to check
    /// - Throws: SDKError if result != RAC_SUCCESS
    public static func throwIfError(_ result: rac_result_t) throws {
        if let error = toSDKError(result) {
            throw error
        }
    }

    /// Maps a C error code to an SDKError.
    /// Always returns a non-nil error (even for RAC_SUCCESS, returns a generic success error).
    ///
    /// - Parameter result: The C error code
    /// - Returns: The corresponding SDKError
    public static func mapCommonsError(_ result: rac_result_t) -> SDKError {
        let (errorCode, errorMessage) = mapErrorCode(result)
        return SDKError.general(errorCode, errorMessage)
    }
}
