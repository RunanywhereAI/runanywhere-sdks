/**
 * @file rac_error.h
 * @brief RunAnywhere Commons - Error Codes and Error Handling
 *
 * C port of Swift's ErrorCode enum from Foundation/Errors/ErrorCode.swift.
 *
 * Error codes for runanywhere-commons use the range -100 to -999 to avoid
 * collision with runanywhere-core error codes (0 to -99).
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add error codes not present in the Swift code.
 */

#ifndef RAC_ERROR_H
#define RAC_ERROR_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// ERROR CODE RANGES
// =============================================================================
//
// runanywhere-core (ra_*):    0 to -99
// runanywhere-commons (rac_*): -100 to -999
//   - Initialization errors:    -100 to -109
//   - Model errors:             -110 to -129
//   - Generation errors:        -130 to -149
//   - Network errors:           -150 to -179
//   - Storage errors:           -180 to -219
//   - Hardware errors:          -220 to -229
//   - Component state errors:   -230 to -249
//   - Validation errors:        -250 to -279
//   - Audio errors:             -280 to -299
//   - Language/Voice errors:    -300 to -319
//   - Authentication errors:    -320 to -329
//   - Security errors:          -330 to -349
//   - Extraction errors:        -350 to -369
//   - Calibration errors:       -370 to -379
//   - Module/Service errors:    -400 to -499
//   - Platform adapter errors:  -500 to -509
//   - QNN/NPU errors:           -510 to -549
//   - Backend errors:           -600 to -699
//   - Event errors:             -700 to -799
//   - Other errors:             -800 to -899
//   - Reserved:                 -900 to -999

// =============================================================================
// INITIALIZATION ERRORS (-100 to -109)
// Mirrors Swift's ErrorCode: Initialization Errors
// =============================================================================

/** Component or service has not been initialized */
#define RAC_ERROR_NOT_INITIALIZED ((rac_result_t) - 100)
/** Component or service is already initialized */
#define RAC_ERROR_ALREADY_INITIALIZED ((rac_result_t) - 101)
/** Initialization failed */
#define RAC_ERROR_INITIALIZATION_FAILED ((rac_result_t) - 102)
/** Configuration is invalid */
#define RAC_ERROR_INVALID_CONFIGURATION ((rac_result_t) - 103)
/** API key is invalid or missing */
#define RAC_ERROR_INVALID_API_KEY ((rac_result_t) - 104)
/** Environment mismatch (e.g., dev vs prod) */
#define RAC_ERROR_ENVIRONMENT_MISMATCH ((rac_result_t) - 105)
/** Invalid parameter value passed to a function */
#define RAC_ERROR_INVALID_PARAMETER ((rac_result_t) - 106)

// =============================================================================
// MODEL ERRORS (-110 to -129)
// Mirrors Swift's ErrorCode: Model Errors
// =============================================================================

/** Requested model was not found */
#define RAC_ERROR_MODEL_NOT_FOUND ((rac_result_t) - 110)
/** Failed to load the model */
#define RAC_ERROR_MODEL_LOAD_FAILED ((rac_result_t) - 111)
/** Model validation failed */
#define RAC_ERROR_MODEL_VALIDATION_FAILED ((rac_result_t) - 112)
/** Model is incompatible with current runtime */
#define RAC_ERROR_MODEL_INCOMPATIBLE ((rac_result_t) - 113)
/** Model format is invalid */
#define RAC_ERROR_INVALID_MODEL_FORMAT ((rac_result_t) - 114)
/** Model storage is corrupted */
#define RAC_ERROR_MODEL_STORAGE_CORRUPTED ((rac_result_t) - 115)
/** Model not loaded (alias for backward compatibility) */
#define RAC_ERROR_MODEL_NOT_LOADED ((rac_result_t) - 116)

// =============================================================================
// GENERATION ERRORS (-130 to -149)
// Mirrors Swift's ErrorCode: Generation Errors
// =============================================================================

/** Text/audio generation failed */
#define RAC_ERROR_GENERATION_FAILED ((rac_result_t) - 130)
/** Generation timed out */
#define RAC_ERROR_GENERATION_TIMEOUT ((rac_result_t) - 131)
/** Context length exceeded maximum */
#define RAC_ERROR_CONTEXT_TOO_LONG ((rac_result_t) - 132)
/** Token limit exceeded */
#define RAC_ERROR_TOKEN_LIMIT_EXCEEDED ((rac_result_t) - 133)
/** Cost limit exceeded */
#define RAC_ERROR_COST_LIMIT_EXCEEDED ((rac_result_t) - 134)
/** Inference failed */
#define RAC_ERROR_INFERENCE_FAILED ((rac_result_t) - 135)

// =============================================================================
// NETWORK ERRORS (-150 to -179)
// Mirrors Swift's ErrorCode: Network Errors
// =============================================================================

/** Network is unavailable */
#define RAC_ERROR_NETWORK_UNAVAILABLE ((rac_result_t) - 150)
/** Generic network error */
#define RAC_ERROR_NETWORK_ERROR ((rac_result_t) - 151)
/** Request failed */
#define RAC_ERROR_REQUEST_FAILED ((rac_result_t) - 152)
/** Download failed */
#define RAC_ERROR_DOWNLOAD_FAILED ((rac_result_t) - 153)
/** Server returned an error */
#define RAC_ERROR_SERVER_ERROR ((rac_result_t) - 154)
/** Request timed out */
#define RAC_ERROR_TIMEOUT ((rac_result_t) - 155)
/** Invalid response from server */
#define RAC_ERROR_INVALID_RESPONSE ((rac_result_t) - 156)
/** HTTP error with status code */
#define RAC_ERROR_HTTP_ERROR ((rac_result_t) - 157)
/** Connection was lost */
#define RAC_ERROR_CONNECTION_LOST ((rac_result_t) - 158)
/** Partial download (incomplete) */
#define RAC_ERROR_PARTIAL_DOWNLOAD ((rac_result_t) - 159)
/** HTTP request failed */
#define RAC_ERROR_HTTP_REQUEST_FAILED ((rac_result_t) - 160)
/** HTTP not supported */
#define RAC_ERROR_HTTP_NOT_SUPPORTED ((rac_result_t) - 161)

// =============================================================================
// STORAGE ERRORS (-180 to -219)
// Mirrors Swift's ErrorCode: Storage Errors
// =============================================================================

/** Insufficient storage space */
#define RAC_ERROR_INSUFFICIENT_STORAGE ((rac_result_t) - 180)
/** Storage is full */
#define RAC_ERROR_STORAGE_FULL ((rac_result_t) - 181)
/** Generic storage error */
#define RAC_ERROR_STORAGE_ERROR ((rac_result_t) - 182)
/** File was not found */
#define RAC_ERROR_FILE_NOT_FOUND ((rac_result_t) - 183)
/** Failed to read file */
#define RAC_ERROR_FILE_READ_FAILED ((rac_result_t) - 184)
/** Failed to write file */
#define RAC_ERROR_FILE_WRITE_FAILED ((rac_result_t) - 185)
/** Permission denied for file operation */
#define RAC_ERROR_PERMISSION_DENIED ((rac_result_t) - 186)
/** Failed to delete file or directory */
#define RAC_ERROR_DELETE_FAILED ((rac_result_t) - 187)
/** Failed to move file */
#define RAC_ERROR_MOVE_FAILED ((rac_result_t) - 188)
/** Failed to create directory */
#define RAC_ERROR_DIRECTORY_CREATION_FAILED ((rac_result_t) - 189)
/** Directory not found */
#define RAC_ERROR_DIRECTORY_NOT_FOUND ((rac_result_t) - 190)
/** Invalid file path */
#define RAC_ERROR_INVALID_PATH ((rac_result_t) - 191)
/** Invalid file name */
#define RAC_ERROR_INVALID_FILE_NAME ((rac_result_t) - 192)
/** Failed to create temporary file */
#define RAC_ERROR_TEMP_FILE_CREATION_FAILED ((rac_result_t) - 193)
/** File delete failed (alias) */
#define RAC_ERROR_FILE_DELETE_FAILED ((rac_result_t) - 187)

// =============================================================================
// HARDWARE ERRORS (-220 to -229)
// Mirrors Swift's ErrorCode: Hardware Errors
// =============================================================================

/** Hardware is unsupported */
#define RAC_ERROR_HARDWARE_UNSUPPORTED ((rac_result_t) - 220)
/** Insufficient memory */
#define RAC_ERROR_INSUFFICIENT_MEMORY ((rac_result_t) - 221)
/** Out of memory (alias) */
#define RAC_ERROR_OUT_OF_MEMORY ((rac_result_t) - 221)

// =============================================================================
// COMPONENT STATE ERRORS (-230 to -249)
// Mirrors Swift's ErrorCode: Component State Errors
// =============================================================================

/** Component is not ready */
#define RAC_ERROR_COMPONENT_NOT_READY ((rac_result_t) - 230)
/** Component is in invalid state */
#define RAC_ERROR_INVALID_STATE ((rac_result_t) - 231)
/** Service is not available */
#define RAC_ERROR_SERVICE_NOT_AVAILABLE ((rac_result_t) - 232)
/** Service is busy */
#define RAC_ERROR_SERVICE_BUSY ((rac_result_t) - 233)
/** Processing failed */
#define RAC_ERROR_PROCESSING_FAILED ((rac_result_t) - 234)
/** Start operation failed */
#define RAC_ERROR_START_FAILED ((rac_result_t) - 235)
/** Feature/operation is not supported */
#define RAC_ERROR_NOT_SUPPORTED ((rac_result_t) - 236)

// =============================================================================
// VALIDATION ERRORS (-250 to -279)
// Mirrors Swift's ErrorCode: Validation Errors
// =============================================================================

/** Validation failed */
#define RAC_ERROR_VALIDATION_FAILED ((rac_result_t) - 250)
/** Input is invalid */
#define RAC_ERROR_INVALID_INPUT ((rac_result_t) - 251)
/** Format is invalid */
#define RAC_ERROR_INVALID_FORMAT ((rac_result_t) - 252)
/** Input is empty */
#define RAC_ERROR_EMPTY_INPUT ((rac_result_t) - 253)
/** Text is too long */
#define RAC_ERROR_TEXT_TOO_LONG ((rac_result_t) - 254)
/** Invalid SSML markup */
#define RAC_ERROR_INVALID_SSML ((rac_result_t) - 255)
/** Invalid speaking rate */
#define RAC_ERROR_INVALID_SPEAKING_RATE ((rac_result_t) - 256)
/** Invalid pitch */
#define RAC_ERROR_INVALID_PITCH ((rac_result_t) - 257)
/** Invalid volume */
#define RAC_ERROR_INVALID_VOLUME ((rac_result_t) - 258)
/** Invalid argument */
#define RAC_ERROR_INVALID_ARGUMENT ((rac_result_t) - 259)
/** Null pointer */
#define RAC_ERROR_NULL_POINTER ((rac_result_t) - 260)
/** Buffer too small */
#define RAC_ERROR_BUFFER_TOO_SMALL ((rac_result_t) - 261)

// =============================================================================
// AUDIO ERRORS (-280 to -299)
// Mirrors Swift's ErrorCode: Audio Errors
// =============================================================================

/** Audio format is not supported */
#define RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED ((rac_result_t) - 280)
/** Audio session configuration failed */
#define RAC_ERROR_AUDIO_SESSION_FAILED ((rac_result_t) - 281)
/** Microphone permission denied */
#define RAC_ERROR_MICROPHONE_PERMISSION_DENIED ((rac_result_t) - 282)
/** Insufficient audio data */
#define RAC_ERROR_INSUFFICIENT_AUDIO_DATA ((rac_result_t) - 283)
/** Audio buffer is empty */
#define RAC_ERROR_EMPTY_AUDIO_BUFFER ((rac_result_t) - 284)
/** Audio session activation failed */
#define RAC_ERROR_AUDIO_SESSION_ACTIVATION_FAILED ((rac_result_t) - 285)

// =============================================================================
// LANGUAGE/VOICE ERRORS (-300 to -319)
// Mirrors Swift's ErrorCode: Language/Voice Errors
// =============================================================================

/** Language is not supported */
#define RAC_ERROR_LANGUAGE_NOT_SUPPORTED ((rac_result_t) - 300)
/** Voice is not available */
#define RAC_ERROR_VOICE_NOT_AVAILABLE ((rac_result_t) - 301)
/** Streaming is not supported */
#define RAC_ERROR_STREAMING_NOT_SUPPORTED ((rac_result_t) - 302)
/** Stream was cancelled */
#define RAC_ERROR_STREAM_CANCELLED ((rac_result_t) - 303)

// =============================================================================
// AUTHENTICATION ERRORS (-320 to -329)
// Mirrors Swift's ErrorCode: Authentication Errors
// =============================================================================

/** Authentication failed */
#define RAC_ERROR_AUTHENTICATION_FAILED ((rac_result_t) - 320)
/** Unauthorized access */
#define RAC_ERROR_UNAUTHORIZED ((rac_result_t) - 321)
/** Access forbidden */
#define RAC_ERROR_FORBIDDEN ((rac_result_t) - 322)

// =============================================================================
// SECURITY ERRORS (-330 to -349)
// Mirrors Swift's ErrorCode: Security Errors
// =============================================================================

/** Keychain operation failed */
#define RAC_ERROR_KEYCHAIN_ERROR ((rac_result_t) - 330)
/** Encoding error */
#define RAC_ERROR_ENCODING_ERROR ((rac_result_t) - 331)
/** Decoding error */
#define RAC_ERROR_DECODING_ERROR ((rac_result_t) - 332)
/** Secure storage failed */
#define RAC_ERROR_SECURE_STORAGE_FAILED ((rac_result_t) - 333)

// =============================================================================
// EXTRACTION ERRORS (-350 to -369)
// Mirrors Swift's ErrorCode: Extraction Errors
// =============================================================================

/** Extraction failed (JSON, archive, etc.) */
#define RAC_ERROR_EXTRACTION_FAILED ((rac_result_t) - 350)
/** Checksum mismatch */
#define RAC_ERROR_CHECKSUM_MISMATCH ((rac_result_t) - 351)
/** Unsupported archive format */
#define RAC_ERROR_UNSUPPORTED_ARCHIVE ((rac_result_t) - 352)

// =============================================================================
// CALIBRATION ERRORS (-370 to -379)
// Mirrors Swift's ErrorCode: Calibration Errors
// =============================================================================

/** Calibration failed */
#define RAC_ERROR_CALIBRATION_FAILED ((rac_result_t) - 370)
/** Calibration timed out */
#define RAC_ERROR_CALIBRATION_TIMEOUT ((rac_result_t) - 371)

// =============================================================================
// CANCELLATION (-380 to -389)
// Mirrors Swift's ErrorCode: Cancellation
// =============================================================================

/** Operation was cancelled */
#define RAC_ERROR_CANCELLED ((rac_result_t) - 380)

// =============================================================================
// MODULE/SERVICE ERRORS (-400 to -499)
// =============================================================================

/** Module not found */
#define RAC_ERROR_MODULE_NOT_FOUND ((rac_result_t) - 400)
/** Module already registered */
#define RAC_ERROR_MODULE_ALREADY_REGISTERED ((rac_result_t) - 401)
/** Module load failed */
#define RAC_ERROR_MODULE_LOAD_FAILED ((rac_result_t) - 402)
/** Service not found */
#define RAC_ERROR_SERVICE_NOT_FOUND ((rac_result_t) - 410)
/** Service already registered */
#define RAC_ERROR_SERVICE_ALREADY_REGISTERED ((rac_result_t) - 411)
/** Service create failed */
#define RAC_ERROR_SERVICE_CREATE_FAILED ((rac_result_t) - 412)
/** Capability not found */
#define RAC_ERROR_CAPABILITY_NOT_FOUND ((rac_result_t) - 420)
/** Provider not found */
#define RAC_ERROR_PROVIDER_NOT_FOUND ((rac_result_t) - 421)
/** No capable provider */
#define RAC_ERROR_NO_CAPABLE_PROVIDER ((rac_result_t) - 422)
/** Generic not found */
#define RAC_ERROR_NOT_FOUND ((rac_result_t) - 423)

// =============================================================================
// PLATFORM ADAPTER ERRORS (-500 to -509)
// =============================================================================

/** Adapter not set */
#define RAC_ERROR_ADAPTER_NOT_SET ((rac_result_t) - 500)

// =============================================================================
// QNN/NPU ERRORS (-510 to -549)
// Errors related to Qualcomm QNN Execution Provider and NPU acceleration
// =============================================================================

/** QNN runtime is not available on this device */
#define RAC_ERROR_QNN_NOT_AVAILABLE ((rac_result_t) - 510)
/** QNN initialization failed */
#define RAC_ERROR_QNN_INIT_FAILED ((rac_result_t) - 511)
/** Model has operators not supported on QNN HTP (NPU) */
#define RAC_ERROR_QNN_UNSUPPORTED_OPS ((rac_result_t) - 512)
/** QNN context binary generation failed */
#define RAC_ERROR_QNN_CONTEXT_FAILED ((rac_result_t) - 513)
/** QNN session creation failed */
#define RAC_ERROR_QNN_SESSION_FAILED ((rac_result_t) - 514)
/** NPU inference failed */
#define RAC_ERROR_QNN_INFERENCE_FAILED ((rac_result_t) - 515)
/** Model has dynamic shapes (NPU requires static shapes) */
#define RAC_ERROR_QNN_DYNAMIC_SHAPES ((rac_result_t) - 516)
/** Model is not QDQ quantized (NPU requires QDQ format) */
#define RAC_ERROR_QNN_NOT_QDQ ((rac_result_t) - 517)
/** SoC is not supported for QNN acceleration */
#define RAC_ERROR_QNN_SOC_UNSUPPORTED ((rac_result_t) - 518)
/** Insufficient VTCM memory for model */
#define RAC_ERROR_QNN_VTCM_INSUFFICIENT ((rac_result_t) - 519)
/** Split model configuration is invalid */
#define RAC_ERROR_QNN_SPLIT_MODEL_INVALID ((rac_result_t) - 520)
/** Encoder model failed to load on NPU */
#define RAC_ERROR_QNN_ENCODER_LOAD_FAILED ((rac_result_t) - 521)
/** Vocoder model failed to load on CPU */
#define RAC_ERROR_QNN_VOCODER_LOAD_FAILED ((rac_result_t) - 522)
/** Hybrid inference pipeline failed */
#define RAC_ERROR_QNN_HYBRID_INFERENCE_FAILED ((rac_result_t) - 523)

// =============================================================================
// BACKEND ERRORS (-600 to -699)
// =============================================================================

/** Backend not found */
#define RAC_ERROR_BACKEND_NOT_FOUND ((rac_result_t) - 600)
/** Backend not ready */
#define RAC_ERROR_BACKEND_NOT_READY ((rac_result_t) - 601)
/** Backend init failed */
#define RAC_ERROR_BACKEND_INIT_FAILED ((rac_result_t) - 602)
/** Backend busy */
#define RAC_ERROR_BACKEND_BUSY ((rac_result_t) - 603)
/** NPU/QNN not available or model not compatible with NPU execution */
#define RAC_ERROR_NPU_NOT_AVAILABLE ((rac_result_t) - 604)
/** NPU execution required but model is not quantized (INT8) */
#define RAC_ERROR_NPU_REQUIRES_QUANTIZED_MODEL ((rac_result_t) - 605)
/** Invalid handle */
#define RAC_ERROR_INVALID_HANDLE ((rac_result_t) - 610)

// =============================================================================
// EVENT ERRORS (-700 to -799)
// =============================================================================

/** Invalid event category */
#define RAC_ERROR_EVENT_INVALID_CATEGORY ((rac_result_t) - 700)
/** Event subscription failed */
#define RAC_ERROR_EVENT_SUBSCRIPTION_FAILED ((rac_result_t) - 701)
/** Event publish failed */
#define RAC_ERROR_EVENT_PUBLISH_FAILED ((rac_result_t) - 702)

// =============================================================================
// OTHER ERRORS (-800 to -899)
// Mirrors Swift's ErrorCode: Other Errors
// =============================================================================

/** Feature is not implemented */
#define RAC_ERROR_NOT_IMPLEMENTED ((rac_result_t) - 800)
/** Feature is not available */
#define RAC_ERROR_FEATURE_NOT_AVAILABLE ((rac_result_t) - 801)
/** Framework is not available */
#define RAC_ERROR_FRAMEWORK_NOT_AVAILABLE ((rac_result_t) - 802)
/** Unsupported modality */
#define RAC_ERROR_UNSUPPORTED_MODALITY ((rac_result_t) - 803)
/** Unknown error */
#define RAC_ERROR_UNKNOWN ((rac_result_t) - 804)
/** Internal error */
#define RAC_ERROR_INTERNAL ((rac_result_t) - 805)

// =============================================================================
// ERROR MESSAGE API
// =============================================================================

/**
 * Gets a human-readable error message for an error code.
 *
 * @param error_code The error code to get a message for
 * @return A static string describing the error (never NULL)
 */
RAC_API const char* rac_error_message(rac_result_t error_code);

/**
 * Gets the last detailed error message.
 *
 * This returns additional context beyond the error code, such as file paths
 * or specific failure reasons. Returns NULL if no detailed message is set.
 *
 * @return The last error detail string, or NULL
 *
 * @note The returned string is thread-local and valid until the next
 *       RAC function call on the same thread.
 */
RAC_API const char* rac_error_get_details(void);

/**
 * Sets the detailed error message for the current thread.
 *
 * This is typically called internally by RAC functions to provide
 * additional context for errors.
 *
 * @param details The detail string (will be copied internally)
 */
RAC_API void rac_error_set_details(const char* details);

/**
 * Clears the detailed error message for the current thread.
 */
RAC_API void rac_error_clear_details(void);

/**
 * Checks if an error code is in the commons range (-100 to -999).
 *
 * @param error_code The error code to check
 * @return RAC_TRUE if the error is from commons, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_error_is_commons_error(rac_result_t error_code);

/**
 * Checks if an error code is in the core range (0 to -99).
 *
 * @param error_code The error code to check
 * @return RAC_TRUE if the error is from core, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_error_is_core_error(rac_result_t error_code);

/**
 * Checks if an error is expected/routine (like cancellation).
 * Mirrors Swift's ErrorCode.isExpected property.
 *
 * @param error_code The error code to check
 * @return RAC_TRUE if expected, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_error_is_expected(rac_result_t error_code);

#ifdef __cplusplus
}
#endif

#endif /* RAC_ERROR_H */
