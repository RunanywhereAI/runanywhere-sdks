/**
 * @file rac_str_trans.h
 * @brief RunAnywhere Commons - String Transformation
 *
 * String transformation utilities for Windows.
 * Converts strings between ANSI (system code page), UTF-8, and Unicode (UTF-16).
 *
 * All conversion functions follow the Windows API size-query convention:
 * - Pass NULL (or 0) for the output buffer to query the required buffer size.
 * - The required size always includes the null terminator.
 * - out_required receives the required size even when a buffer is provided.
 *
 * Buffer sizes for narrow (char) outputs are in bytes.
 * Buffer sizes for wide (wchar_t) outputs are in wchar_t units.
 *
 * Note: These functions are Windows-only and depend on Windows code page APIs.
 */

#ifndef RAC_STR_TRANS_H
#define RAC_STR_TRANS_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// STRING CONVERSION - ANSI <-> UNICODE
// =============================================================================

/**
 * @brief Convert ANSI (system code page) string to Unicode (UTF-16) string
 *
 * @param src          Source ANSI string (null-terminated)
 * @param out_buf      Output buffer, or NULL to query required size
 * @param buf_wchars   Output buffer size in wchar_t units (including null terminator)
 * @param out_required If non-NULL, receives the required size in wchar_t units
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_str_ascii_to_unicode(const char* src, wchar_t* out_buf, int buf_wchars,
                                              int* out_required);

/**
 * @brief Convert Unicode (UTF-16) string to ANSI (system code page) string
 *
 * @param src          Source Unicode string (null-terminated)
 * @param out_buf      Output buffer, or NULL to query required size
 * @param buf_size     Output buffer size in bytes (including null terminator)
 * @param out_required If non-NULL, receives the required size in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_str_unicode_to_ascii(const wchar_t* src, char* out_buf, int buf_size,
                                              int* out_required);

// =============================================================================
// STRING CONVERSION - ANSI <-> UTF-8
// =============================================================================

/**
 * @brief Convert ANSI (system code page) string to UTF-8 string
 *
 * @param src          Source ANSI string (null-terminated)
 * @param out_buf      Output buffer, or NULL to query required size
 * @param buf_size     Output buffer size in bytes (including null terminator)
 * @param out_required If non-NULL, receives the required size in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_str_ascii_to_utf8(const char* src, char* out_buf, int buf_size,
                                           int* out_required);

/**
 * @brief Convert UTF-8 string to ANSI (system code page) string
 *
 * @param src          Source UTF-8 string (null-terminated)
 * @param out_buf      Output buffer, or NULL to query required size
 * @param buf_size     Output buffer size in bytes (including null terminator)
 * @param out_required If non-NULL, receives the required size in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_str_utf8_to_ascii(const char* src, char* out_buf, int buf_size,
                                           int* out_required);

// =============================================================================
// STRING CONVERSION - UNICODE <-> UTF-8
// =============================================================================

/**
 * @brief Convert Unicode (UTF-16) string to UTF-8 string
 *
 * @param src          Source Unicode string (null-terminated)
 * @param out_buf      Output buffer, or NULL to query required size
 * @param buf_size     Output buffer size in bytes (including null terminator)
 * @param out_required If non-NULL, receives the required size in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_str_unicode_to_utf8(const wchar_t* src, char* out_buf, int buf_size,
                                             int* out_required);

/**
 * @brief Convert UTF-8 string to Unicode (UTF-16) string
 *
 * @param src          Source UTF-8 string (null-terminated)
 * @param out_buf      Output buffer, or NULL to query required size
 * @param buf_wchars   Output buffer size in wchar_t units (including null terminator)
 * @param out_required If non-NULL, receives the required size in wchar_t units
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_str_utf8_to_unicode(const char* src, wchar_t* out_buf, int buf_wchars,
                                             int* out_required);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STR_TRANS_H */
