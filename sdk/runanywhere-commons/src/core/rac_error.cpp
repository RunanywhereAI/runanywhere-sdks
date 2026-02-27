/**
 * @file rac_error.cpp
 * @brief RunAnywhere Commons - Error Handling Implementation
 *
 * C port of Swift's ErrorCode enum messages from Foundation/Errors/ErrorCode.swift.
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add error messages not present in the Swift code.
 */

#include "rac/core/rac_error.h"

#include <cstring>
#include <string>

// Thread-local storage for detailed error messages
// Matches Swift's per-operation error context pattern
static thread_local std::string s_error_details;

extern "C" {

const char* rac_error_message(rac_result_t error_code) {
    // Success
    if (error_code == RAC_SUCCESS) {
        return "Success";
    }

    switch (error_code) {
        // =================================================================
        // INITIALIZATION ERRORS (-100 to -109)
        // =================================================================
        case RAC_ERROR_NOT_INITIALIZED:
            return "Component or service has not been initialized";
        case RAC_ERROR_ALREADY_INITIALIZED:
            return "Component or service is already initialized";
        case RAC_ERROR_INITIALIZATION_FAILED:
            return "Initialization failed";
        case RAC_ERROR_INVALID_CONFIGURATION:
            return "Configuration is invalid";
        case RAC_ERROR_INVALID_API_KEY:
            return "API key is invalid or missing";
        case RAC_ERROR_ENVIRONMENT_MISMATCH:
            return "Environment mismatch";
        case RAC_ERROR_INVALID_PARAMETER:
            return "Invalid parameter value";

        // =================================================================
        // MODEL ERRORS (-110 to -129)
        // =================================================================
        case RAC_ERROR_MODEL_NOT_FOUND:
            return "Requested model was not found";
        case RAC_ERROR_MODEL_LOAD_FAILED:
            return "Failed to load the model";
        case RAC_ERROR_MODEL_VALIDATION_FAILED:
            return "Model validation failed";
        case RAC_ERROR_MODEL_INCOMPATIBLE:
            return "Model is incompatible with current runtime";
        case RAC_ERROR_INVALID_MODEL_FORMAT:
            return "Model format is invalid";
        case RAC_ERROR_MODEL_STORAGE_CORRUPTED:
            return "Model storage is corrupted";
        case RAC_ERROR_MODEL_NOT_LOADED:
            return "Model not loaded";

        // =================================================================
        // GENERATION ERRORS (-130 to -149)
        // =================================================================
        case RAC_ERROR_GENERATION_FAILED:
            return "Text/audio generation failed";
        case RAC_ERROR_GENERATION_TIMEOUT:
            return "Generation timed out";
        case RAC_ERROR_CONTEXT_TOO_LONG:
            return "Context length exceeded maximum";
        case RAC_ERROR_TOKEN_LIMIT_EXCEEDED:
            return "Token limit exceeded";
        case RAC_ERROR_COST_LIMIT_EXCEEDED:
            return "Cost limit exceeded";
        case RAC_ERROR_INFERENCE_FAILED:
            return "Inference failed";

        // =================================================================
        // NETWORK ERRORS (-150 to -179)
        // =================================================================
        case RAC_ERROR_NETWORK_UNAVAILABLE:
            return "Network is unavailable";
        case RAC_ERROR_NETWORK_ERROR:
            return "Network error";
        case RAC_ERROR_REQUEST_FAILED:
            return "Request failed";
        case RAC_ERROR_DOWNLOAD_FAILED:
            return "Download failed";
        case RAC_ERROR_SERVER_ERROR:
            return "Server returned an error";
        case RAC_ERROR_TIMEOUT:
            return "Request timed out";
        case RAC_ERROR_INVALID_RESPONSE:
            return "Invalid response from server";
        case RAC_ERROR_HTTP_ERROR:
            return "HTTP error";
        case RAC_ERROR_CONNECTION_LOST:
            return "Connection was lost";
        case RAC_ERROR_PARTIAL_DOWNLOAD:
            return "Partial download (incomplete)";
        case RAC_ERROR_HTTP_REQUEST_FAILED:
            return "HTTP request failed";
        case RAC_ERROR_HTTP_NOT_SUPPORTED:
            return "HTTP not supported";

        // =================================================================
        // STORAGE ERRORS (-180 to -219)
        // =================================================================
        case RAC_ERROR_INSUFFICIENT_STORAGE:
            return "Insufficient storage space";
        case RAC_ERROR_STORAGE_FULL:
            return "Storage is full";
        case RAC_ERROR_STORAGE_ERROR:
            return "Storage error";
        case RAC_ERROR_FILE_NOT_FOUND:
            return "File was not found";
        case RAC_ERROR_FILE_READ_FAILED:
            return "Failed to read file";
        case RAC_ERROR_FILE_WRITE_FAILED:
            return "Failed to write file";
        case RAC_ERROR_PERMISSION_DENIED:
            return "Permission denied for file operation";
        case RAC_ERROR_DELETE_FAILED:
            return "Failed to delete file or directory";
        case RAC_ERROR_MOVE_FAILED:
            return "Failed to move file";
        case RAC_ERROR_DIRECTORY_CREATION_FAILED:
            return "Failed to create directory";
        case RAC_ERROR_DIRECTORY_NOT_FOUND:
            return "Directory not found";
        case RAC_ERROR_INVALID_PATH:
            return "Invalid file path";
        case RAC_ERROR_INVALID_FILE_NAME:
            return "Invalid file name";
        case RAC_ERROR_TEMP_FILE_CREATION_FAILED:
            return "Failed to create temporary file";

        // =================================================================
        // HARDWARE ERRORS (-220 to -229)
        // =================================================================
        case RAC_ERROR_HARDWARE_UNSUPPORTED:
            return "Hardware is unsupported";
        case RAC_ERROR_INSUFFICIENT_MEMORY:
            return "Insufficient memory";

        // =================================================================
        // COMPONENT STATE ERRORS (-230 to -249)
        // =================================================================
        case RAC_ERROR_COMPONENT_NOT_READY:
            return "Component is not ready";
        case RAC_ERROR_INVALID_STATE:
            return "Component is in invalid state";
        case RAC_ERROR_SERVICE_NOT_AVAILABLE:
            return "Service is not available";
        case RAC_ERROR_SERVICE_BUSY:
            return "Service is busy";
        case RAC_ERROR_PROCESSING_FAILED:
            return "Processing failed";
        case RAC_ERROR_START_FAILED:
            return "Start operation failed";
        case RAC_ERROR_NOT_SUPPORTED:
            return "Feature/operation is not supported";

        // =================================================================
        // VALIDATION ERRORS (-250 to -279)
        // =================================================================
        case RAC_ERROR_VALIDATION_FAILED:
            return "Validation failed";
        case RAC_ERROR_INVALID_INPUT:
            return "Input is invalid";
        case RAC_ERROR_INVALID_FORMAT:
            return "Format is invalid";
        case RAC_ERROR_EMPTY_INPUT:
            return "Input is empty";
        case RAC_ERROR_TEXT_TOO_LONG:
            return "Text is too long";
        case RAC_ERROR_INVALID_SSML:
            return "Invalid SSML markup";
        case RAC_ERROR_INVALID_SPEAKING_RATE:
            return "Invalid speaking rate";
        case RAC_ERROR_INVALID_PITCH:
            return "Invalid pitch";
        case RAC_ERROR_INVALID_VOLUME:
            return "Invalid volume";
        case RAC_ERROR_INVALID_ARGUMENT:
            return "Invalid argument";
        case RAC_ERROR_NULL_POINTER:
            return "Null pointer";
        case RAC_ERROR_BUFFER_TOO_SMALL:
            return "Buffer too small";

        // =================================================================
        // AUDIO ERRORS (-280 to -299)
        // =================================================================
        case RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED:
            return "Audio format is not supported";
        case RAC_ERROR_AUDIO_SESSION_FAILED:
            return "Audio session configuration failed";
        case RAC_ERROR_MICROPHONE_PERMISSION_DENIED:
            return "Microphone permission denied";
        case RAC_ERROR_INSUFFICIENT_AUDIO_DATA:
            return "Insufficient audio data";
        case RAC_ERROR_EMPTY_AUDIO_BUFFER:
            return "Audio buffer is empty";
        case RAC_ERROR_AUDIO_SESSION_ACTIVATION_FAILED:
            return "Audio session activation failed";

        // =================================================================
        // LANGUAGE/VOICE ERRORS (-300 to -319)
        // =================================================================
        case RAC_ERROR_LANGUAGE_NOT_SUPPORTED:
            return "Language is not supported";
        case RAC_ERROR_VOICE_NOT_AVAILABLE:
            return "Voice is not available";
        case RAC_ERROR_STREAMING_NOT_SUPPORTED:
            return "Streaming is not supported";
        case RAC_ERROR_STREAM_CANCELLED:
            return "Stream was cancelled";

        // =================================================================
        // AUTHENTICATION ERRORS (-320 to -329)
        // =================================================================
        case RAC_ERROR_AUTHENTICATION_FAILED:
            return "Authentication failed";
        case RAC_ERROR_UNAUTHORIZED:
            return "Unauthorized access";
        case RAC_ERROR_FORBIDDEN:
            return "Access forbidden";

        // =================================================================
        // SECURITY ERRORS (-330 to -349)
        // =================================================================
        case RAC_ERROR_KEYCHAIN_ERROR:
            return "Keychain operation failed";
        case RAC_ERROR_ENCODING_ERROR:
            return "Encoding error";
        case RAC_ERROR_DECODING_ERROR:
            return "Decoding error";
        case RAC_ERROR_SECURE_STORAGE_FAILED:
            return "Secure storage operation failed";

        // =================================================================
        // EXTRACTION ERRORS (-350 to -369)
        // =================================================================
        case RAC_ERROR_EXTRACTION_FAILED:
            return "Extraction failed";
        case RAC_ERROR_CHECKSUM_MISMATCH:
            return "Checksum mismatch";
        case RAC_ERROR_UNSUPPORTED_ARCHIVE:
            return "Unsupported archive format";

        // =================================================================
        // CALIBRATION ERRORS (-370 to -379)
        // =================================================================
        case RAC_ERROR_CALIBRATION_FAILED:
            return "Calibration failed";
        case RAC_ERROR_CALIBRATION_TIMEOUT:
            return "Calibration timed out";

        // =================================================================
        // CANCELLATION (-380 to -389)
        // =================================================================
        case RAC_ERROR_CANCELLED:
            return "Operation was cancelled";

        // =================================================================
        // MODULE/SERVICE ERRORS (-400 to -499)
        // =================================================================
        case RAC_ERROR_MODULE_NOT_FOUND:
            return "Module not found";
        case RAC_ERROR_MODULE_ALREADY_REGISTERED:
            return "Module already registered";
        case RAC_ERROR_MODULE_LOAD_FAILED:
            return "Module load failed";
        case RAC_ERROR_SERVICE_NOT_FOUND:
            return "Service not found";
        case RAC_ERROR_SERVICE_ALREADY_REGISTERED:
            return "Service already registered";
        case RAC_ERROR_SERVICE_CREATE_FAILED:
            return "Service creation failed";
        case RAC_ERROR_CAPABILITY_NOT_FOUND:
            return "Capability not found";
        case RAC_ERROR_PROVIDER_NOT_FOUND:
            return "Provider not found";
        case RAC_ERROR_NO_CAPABLE_PROVIDER:
            return "No provider can handle the request";
        case RAC_ERROR_NOT_FOUND:
            return "Not found";

        // =================================================================
        // PLATFORM ADAPTER ERRORS (-500 to -599)
        // =================================================================
        case RAC_ERROR_ADAPTER_NOT_SET:
            return "Platform adapter not set";

        // =================================================================
        // BACKEND ERRORS (-600 to -699)
        // =================================================================
        case RAC_ERROR_BACKEND_NOT_FOUND:
            return "Backend not found";
        case RAC_ERROR_BACKEND_NOT_READY:
            return "Backend not ready";
        case RAC_ERROR_BACKEND_INIT_FAILED:
            return "Backend initialization failed";
        case RAC_ERROR_BACKEND_BUSY:
            return "Backend busy";
        case RAC_ERROR_INVALID_HANDLE:
            return "Invalid handle";

        // =================================================================
        // EVENT ERRORS (-700 to -799)
        // =================================================================
        case RAC_ERROR_EVENT_INVALID_CATEGORY:
            return "Invalid event category";
        case RAC_ERROR_EVENT_SUBSCRIPTION_FAILED:
            return "Event subscription failed";
        case RAC_ERROR_EVENT_PUBLISH_FAILED:
            return "Event publish failed";

        // =================================================================
        // OTHER ERRORS (-800 to -899)
        // =================================================================
        case RAC_ERROR_NOT_IMPLEMENTED:
            return "Feature is not implemented";
        case RAC_ERROR_FEATURE_NOT_AVAILABLE:
            return "Feature is not available";
        case RAC_ERROR_FRAMEWORK_NOT_AVAILABLE:
            return "Framework is not available";
        case RAC_ERROR_UNSUPPORTED_MODALITY:
            return "Unsupported modality";
        case RAC_ERROR_UNKNOWN:
            return "Unknown error";
        case RAC_ERROR_INTERNAL:
            return "Internal error";

        default:
            return "Unknown error code";
    }
}

const char* rac_error_get_details(void) {
    if (s_error_details.empty()) {
        return nullptr;
    }
    return s_error_details.c_str();
}

void rac_error_set_details(const char* details) {
    if (details != nullptr) {
        s_error_details = details;
        return;
    }
    s_error_details.clear();
}

void rac_error_clear_details(void) {
    s_error_details.clear();
}

rac_bool_t rac_error_is_commons_error(rac_result_t error_code) {
    // Commons errors are in range -100 to -999
    return (error_code <= -100 && error_code >= -999) ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_error_is_core_error(rac_result_t error_code) {
    // Core errors are in range -1 to -99
    return (error_code <= -1 && error_code >= -99) ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_error_is_expected(rac_result_t error_code) {
    // Mirrors Swift's ErrorCode.isExpected property
    // Expected errors are routine and shouldn't be logged as errors
    switch (error_code) {
        case RAC_ERROR_CANCELLED:
        case RAC_ERROR_STREAM_CANCELLED:
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

}  // extern "C"
