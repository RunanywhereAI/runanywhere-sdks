import CRACommons
import Foundation

/// Maps RAC_ERROR_* codes from runanywhere-commons to Swift SDKError.
public enum CommonsErrorMapping {

    /// Converts a rac_result_t error code to SDKError.
    ///
    /// - Parameter result: The C error code from runanywhere-commons
    /// - Returns: Corresponding SDKError, or nil if result is RAC_SUCCESS
    public static func toSDKError(_ result: rac_result_t) -> SDKError? {
        guard result != RAC_SUCCESS else { return nil }

        // Map commons error codes to SDK errors
        let (errorCode, errorMessage) = mapErrorCode(result)

        return SDKError.general(errorCode, errorMessage)
    }

    private static func mapErrorCode(_ result: rac_result_t) -> (ErrorCode, String) {
        // Delegate to category-specific mappers to reduce cyclomatic complexity
        if let mapped = mapGeneralError(result) { return mapped }
        if let mapped = mapModuleServiceError(result) { return mapped }
        if let mapped = mapPlatformAdapterError(result) { return mapped }
        if let mapped = mapBackendError(result) { return mapped }
        if let mapped = mapModelError(result) { return mapped }
        if let mapped = mapInferenceError(result) { return mapped }
        if let mapped = mapEventError(result) { return mapped }
        return (.unknown, "Unknown error code: \(result)")
    }

    // MARK: - Error Category Mappers

    private static func mapGeneralError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_UNKNOWN: return (.unknown, "Unknown error")
        case RAC_ERROR_INVALID_ARGUMENT: return (.invalidInput, "Invalid argument")
        case RAC_ERROR_NULL_POINTER: return (.invalidInput, "Null pointer")
        case RAC_ERROR_OUT_OF_MEMORY: return (.insufficientMemory, "Out of memory")
        case RAC_ERROR_NOT_INITIALIZED: return (.notInitialized, "Not initialized")
        case RAC_ERROR_ALREADY_INITIALIZED: return (.alreadyInitialized, "Already initialized")
        case RAC_ERROR_NOT_SUPPORTED: return (.notSupported, "Not supported")
        case RAC_ERROR_TIMEOUT: return (.timeout, "Operation timed out")
        case RAC_ERROR_CANCELLED: return (.cancelled, "Operation cancelled")
        case RAC_ERROR_INTERNAL: return (.unknown, "Internal error")
        case RAC_ERROR_BUFFER_TOO_SMALL: return (.invalidInput, "Buffer too small")
        case RAC_ERROR_INVALID_STATE: return (.invalidState, "Invalid state")
        case RAC_ERROR_PERMISSION_DENIED: return (.permissionDenied, "Permission denied")
        default: return nil
        }
    }

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

    private static func mapPlatformAdapterError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_ADAPTER_NOT_SET: return (.notInitialized, "Platform adapter not set")
        case RAC_ERROR_FILE_NOT_FOUND: return (.fileNotFound, "File not found")
        case RAC_ERROR_FILE_READ_FAILED: return (.fileReadFailed, "File read failed")
        case RAC_ERROR_FILE_WRITE_FAILED: return (.fileWriteFailed, "File write failed")
        case RAC_ERROR_FILE_DELETE_FAILED: return (.deleteFailed, "File delete failed")
        case RAC_ERROR_SECURE_STORAGE_FAILED: return (.keychainError, "Secure storage failed")
        case RAC_ERROR_HTTP_NOT_SUPPORTED: return (.networkUnavailable, "HTTP not supported")
        case RAC_ERROR_HTTP_REQUEST_FAILED: return (.requestFailed, "HTTP request failed")
        default: return nil
        }
    }

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

    private static func mapModelError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_MODEL_NOT_FOUND: return (.modelNotFound, "Model not found")
        case RAC_ERROR_MODEL_LOAD_FAILED: return (.modelLoadFailed, "Model load failed")
        case RAC_ERROR_MODEL_NOT_LOADED: return (.notInitialized, "Model not loaded")
        case RAC_ERROR_MODEL_VALIDATION_FAILED: return (.invalidModelFormat, "Invalid model format")
        case RAC_ERROR_MODEL_INCOMPATIBLE: return (.modelIncompatible, "Model incompatible")
        case RAC_ERROR_MODEL_STORAGE_CORRUPTED: return (.modelStorageCorrupted, "Model corrupted")
        default: return nil
        }
    }

    private static func mapInferenceError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_INFERENCE_FAILED: return (.generationFailed, "Inference failed")
        case RAC_ERROR_GENERATION_FAILED: return (.generationFailed, "Generation failed")
        default: return nil
        }
    }

    private static func mapEventError(_ result: rac_result_t) -> (ErrorCode, String)? {
        switch result {
        case RAC_ERROR_EVENT_INVALID_CATEGORY: return (.invalidInput, "Invalid event category")
        case RAC_ERROR_EVENT_SUBSCRIPTION_FAILED: return (.unknown, "Event subscription failed")
        case RAC_ERROR_EVENT_PUBLISH_FAILED: return (.unknown, "Event publish failed")
        default: return nil
        }
    }

    /// Converts an SDKError to rac_result_t for passing errors back to C++.
    ///
    /// - Parameter error: The SDK error
    /// - Returns: Corresponding rac_result_t code
    static func fromSDKError(_ error: SDKError) -> rac_result_t {
        switch error.code {
        case .invalidInput:
            return RAC_ERROR_INVALID_ARGUMENT
        case .notInitialized:
            return RAC_ERROR_NOT_INITIALIZED
        case .cancelled:
            return RAC_ERROR_CANCELLED
        case .timeout:
            return RAC_ERROR_TIMEOUT
        case .modelLoadFailed:
            return RAC_ERROR_MODEL_LOAD_FAILED
        case .modelNotFound:
            return RAC_ERROR_MODEL_NOT_FOUND
        case .generationFailed:
            return RAC_ERROR_GENERATION_FAILED
        case .fileNotFound:
            return RAC_ERROR_FILE_NOT_FOUND
        default:
            return RAC_ERROR_INTERNAL
        }
    }

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
