/**
 * @file rac_types.h
 * @brief RunAnywhere Commons - Common Types and Definitions
 *
 * This header defines common types, handle types, and macros used throughout
 * the runanywhere-commons library. All types use the RAC_ prefix to distinguish
 * from the underlying runanywhere-core (ra_*) types.
 */

#ifndef RAC_TYPES_H
#define RAC_TYPES_H

#include <stddef.h>
#include <stdint.h>

/**
 * Null pointer macro for use in static initializers.
 * Uses nullptr in C++ (preferred by clang-tidy modernize-use-nullptr)
 * and NULL in C for compatibility.
 */
#ifdef __cplusplus
#define RAC_NULL nullptr
#else
#define RAC_NULL NULL
#endif

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// API VISIBILITY MACROS
// =============================================================================
//
// RAC_API marks functions that must be visible to FFI (dlsym).
//
// CRITICAL: For iOS/Android Flutter FFI, symbols MUST have public visibility
// even when statically linked. dlsym(RTLD_DEFAULT, ...) can only find symbols
// with "external" visibility, not "private external".
//
// Without visibility("default"), static library symbols get "private external"
// visibility (due to -fvisibility=hidden), which becomes "non-external" (local)
// in the final binary - breaking FFI symbol lookup.
// =============================================================================

#if defined(_WIN32)
#if defined(RAC_BUILDING_SHARED)
#define RAC_API __declspec(dllexport)
#elif defined(RAC_USING_SHARED)
#define RAC_API __declspec(dllimport)
#else
#define RAC_API
#endif
#elif defined(__GNUC__) || defined(__clang__)
// Always use default visibility for FFI compatibility
// This ensures dlsym() can find symbols even in static libraries
#define RAC_API __attribute__((visibility("default")))
#else
#define RAC_API
#endif

// =============================================================================
// RESULT TYPE
// =============================================================================

/**
 * Result type for all RAC functions.
 * - 0 indicates success
 * - Negative values indicate errors (see rac_error.h)
 *
 * Error code ranges:
 * - runanywhere-core (ra_*): 0 to -99
 * - runanywhere-commons (rac_*): -100 to -999
 */
typedef int32_t rac_result_t;

/** Success result */
#define RAC_SUCCESS ((rac_result_t)0)

// =============================================================================
// BOOLEAN TYPE
// =============================================================================

/** Boolean type for C compatibility */
typedef int32_t rac_bool_t;

#define RAC_TRUE ((rac_bool_t)1)
#define RAC_FALSE ((rac_bool_t)0)

// =============================================================================
// HANDLE TYPES
// =============================================================================

/**
 * Opaque handle for internal objects.
 * Handles should be treated as opaque pointers.
 */
typedef void* rac_handle_t;

/** Invalid handle value */
#define RAC_INVALID_HANDLE ((rac_handle_t)NULL)

// =============================================================================
// STRING TYPES
// =============================================================================

/**
 * String view (non-owning reference to a string).
 * The string is NOT guaranteed to be null-terminated.
 */
typedef struct rac_string_view {
    const char* data; /**< Pointer to string data */
    size_t length;    /**< Length in bytes (not including any null terminator) */
} rac_string_view_t;

/**
 * Creates a string view from a null-terminated C string.
 */
#define RAC_STRING_VIEW(s) ((rac_string_view_t){(s), (s) ? strlen(s) : 0})

// =============================================================================
// AUDIO TYPES
// =============================================================================

/**
 * Audio buffer for STT/VAD operations.
 * Contains PCM float samples in the range [-1.0, 1.0].
 */
typedef struct rac_audio_buffer {
    const float* samples; /**< PCM float samples */
    size_t num_samples;   /**< Number of samples */
    int32_t sample_rate;  /**< Sample rate in Hz (e.g., 16000) */
    int32_t channels;     /**< Number of channels (1 = mono, 2 = stereo) */
} rac_audio_buffer_t;

/**
 * Audio format specification.
 */
typedef struct rac_audio_format {
    int32_t sample_rate;     /**< Sample rate in Hz */
    int32_t channels;        /**< Number of channels */
    int32_t bits_per_sample; /**< Bits per sample (16 or 32) */
} rac_audio_format_t;

// =============================================================================
// MEMORY INFO
// =============================================================================

/**
 * Memory information structure.
 * Used by the platform adapter to report available memory.
 */
typedef struct rac_memory_info {
    uint64_t total_bytes;     /**< Total physical memory in bytes */
    uint64_t available_bytes; /**< Available memory in bytes */
    uint64_t used_bytes;      /**< Used memory in bytes */
} rac_memory_info_t;

// =============================================================================
// CAPABILITY TYPES
// =============================================================================

/**
 * Capability types supported by backends.
 * These match the capabilities defined in runanywhere-core.
 */
typedef enum rac_capability {
    RAC_CAPABILITY_UNKNOWN = 0,
    RAC_CAPABILITY_TEXT_GENERATION = 1, /**< LLM text generation */
    RAC_CAPABILITY_EMBEDDINGS = 2,      /**< Text embeddings */
    RAC_CAPABILITY_STT = 3,             /**< Speech-to-text */
    RAC_CAPABILITY_TTS = 4,             /**< Text-to-speech */
    RAC_CAPABILITY_VAD = 5,             /**< Voice activity detection */
    RAC_CAPABILITY_DIARIZATION = 6,     /**< Speaker diarization */
    RAC_CAPABILITY_VECTOR_SEARCH = 7,   /**< Vector similarity search (memory/RAG) */
} rac_capability_t;

/**
 * Device type for backend execution.
 */
typedef enum rac_device {
    RAC_DEVICE_CPU = 0,
    RAC_DEVICE_GPU = 1,
    RAC_DEVICE_NPU = 2,
    RAC_DEVICE_AUTO = 3,
} rac_device_t;

// =============================================================================
// LOG LEVELS
// =============================================================================

/**
 * Log level for the logging callback.
 */
typedef enum rac_log_level {
    RAC_LOG_TRACE = 0,
    RAC_LOG_DEBUG = 1,
    RAC_LOG_INFO = 2,
    RAC_LOG_WARNING = 3,
    RAC_LOG_ERROR = 4,
    RAC_LOG_FATAL = 5,
} rac_log_level_t;

// =============================================================================
// VERSION INFO
// =============================================================================

/**
 * Version information structure.
 */
typedef struct rac_version {
    uint16_t major;
    uint16_t minor;
    uint16_t patch;
    const char* string; /**< Version string (e.g., "1.0.0") */
} rac_version_t;

// =============================================================================
// UTILITY MACROS
// =============================================================================

/** Check if a result is a success */
#define RAC_SUCCEEDED(result) ((result) >= 0)

/** Check if a result is an error */
#define RAC_FAILED(result) ((result) < 0)

/** Check if a handle is valid */
#define RAC_IS_VALID_HANDLE(handle) ((handle) != RAC_INVALID_HANDLE)

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * Frees memory allocated by RAC functions.
 *
 * Use this to free strings and buffers returned by RAC functions that
 * are marked as "must be freed with rac_free".
 *
 * @param ptr Pointer to memory to free (can be NULL)
 */
RAC_API void rac_free(void* ptr);

/**
 * Allocates memory using the RAC allocator.
 *
 * @param size Number of bytes to allocate
 * @return Pointer to allocated memory, or NULL on failure
 */
RAC_API void* rac_alloc(size_t size);

/**
 * Duplicates a null-terminated string.
 *
 * @param str String to duplicate (can be NULL)
 * @return Duplicated string (must be freed with rac_free), or NULL if str is NULL
 */
RAC_API char* rac_strdup(const char* str);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TYPES_H */
