/**
 * @file rac_str_trans.cpp
 * @brief RunAnywhere Commons - String Transformation Implementation
 *
 * String transformation utilities for Windows.
 */

#include "rac/utils/rac_str_trans.h"

#include <Windows.h>
#include <stdlib.h>

// =============================================================================
// ANSI <-> UNICODE
// =============================================================================

rac_result_t rac_str_ascii_to_unicode(const char* src, wchar_t* out_buf, int buf_wchars,
                                      int* out_required) {
    if (!src) {
        return RAC_ERROR_NULL_POINTER;
    }

    int required = MultiByteToWideChar(CP_ACP, 0, src, -1, NULL, 0);
    if (required == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    if (out_required) {
        *out_required = required;
    }

    if (!out_buf || buf_wchars == 0) {
        return RAC_SUCCESS;
    }

    if (buf_wchars < required) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    if (MultiByteToWideChar(CP_ACP, 0, src, -1, out_buf, buf_wchars) == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_str_unicode_to_ascii(const wchar_t* src, char* out_buf, int buf_size,
                                      int* out_required) {
    if (!src) {
        return RAC_ERROR_NULL_POINTER;
    }

    int required = WideCharToMultiByte(CP_ACP, 0, src, -1, NULL, 0, NULL, NULL);
    if (required == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    if (out_required) {
        *out_required = required;
    }

    if (!out_buf || buf_size == 0) {
        return RAC_SUCCESS;
    }

    if (buf_size < required) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    if (WideCharToMultiByte(CP_ACP, 0, src, -1, out_buf, buf_size, NULL, NULL) == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    return RAC_SUCCESS;
}

// =============================================================================
// ANSI <-> UTF-8
// =============================================================================

rac_result_t rac_str_ascii_to_utf8(const char* src, char* out_buf, int buf_size,
                                   int* out_required) {
    if (!src) {
        return RAC_ERROR_NULL_POINTER;
    }

    int wlen = MultiByteToWideChar(CP_ACP, 0, src, -1, NULL, 0);
    if (wlen == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    wchar_t* wbuf = (wchar_t*)malloc((size_t)wlen * sizeof(wchar_t));
    if (!wbuf) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    if (MultiByteToWideChar(CP_ACP, 0, src, -1, wbuf, wlen) == 0) {
        free(wbuf);
        return RAC_ERROR_PROCESSING_FAILED;
    }

    int required = WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, NULL, 0, NULL, NULL);
    if (required == 0) {
        free(wbuf);
        return RAC_ERROR_PROCESSING_FAILED;
    }

    if (out_required) {
        *out_required = required;
    }

    if (!out_buf || buf_size == 0) {
        free(wbuf);
        return RAC_SUCCESS;
    }

    if (buf_size < required) {
        free(wbuf);
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    if (WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, out_buf, buf_size, NULL, NULL) == 0) {
        free(wbuf);
        return RAC_ERROR_PROCESSING_FAILED;
    }

    free(wbuf);
    return RAC_SUCCESS;
}

rac_result_t rac_str_utf8_to_ascii(const char* src, char* out_buf, int buf_size,
                                   int* out_required) {
    if (!src) {
        return RAC_ERROR_NULL_POINTER;
    }

    int wlen = MultiByteToWideChar(CP_UTF8, 0, src, -1, NULL, 0);
    if (wlen == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    wchar_t* wbuf = (wchar_t*)malloc((size_t)wlen * sizeof(wchar_t));
    if (!wbuf) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    if (MultiByteToWideChar(CP_UTF8, 0, src, -1, wbuf, wlen) == 0) {
        free(wbuf);
        return RAC_ERROR_PROCESSING_FAILED;
    }

    int required = WideCharToMultiByte(CP_ACP, 0, wbuf, -1, NULL, 0, NULL, NULL);
    if (required == 0) {
        free(wbuf);
        return RAC_ERROR_PROCESSING_FAILED;
    }

    if (out_required) {
        *out_required = required;
    }

    if (!out_buf || buf_size == 0) {
        free(wbuf);
        return RAC_SUCCESS;
    }

    if (buf_size < required) {
        free(wbuf);
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    if (WideCharToMultiByte(CP_ACP, 0, wbuf, -1, out_buf, buf_size, NULL, NULL) == 0) {
        free(wbuf);
        return RAC_ERROR_PROCESSING_FAILED;
    }

    free(wbuf);
    return RAC_SUCCESS;
}

// =============================================================================
// UNICODE <-> UTF-8
// =============================================================================

rac_result_t rac_str_unicode_to_utf8(const wchar_t* src, char* out_buf, int buf_size,
                                     int* out_required) {
    if (!src) {
        return RAC_ERROR_NULL_POINTER;
    }

    int required = WideCharToMultiByte(CP_UTF8, 0, src, -1, NULL, 0, NULL, NULL);
    if (required == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    if (out_required) {
        *out_required = required;
    }

    if (!out_buf || buf_size == 0) {
        return RAC_SUCCESS;
    }

    if (buf_size < required) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    if (WideCharToMultiByte(CP_UTF8, 0, src, -1, out_buf, buf_size, NULL, NULL) == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_str_utf8_to_unicode(const char* src, wchar_t* out_buf, int buf_wchars,
                                     int* out_required) {
    if (!src) {
        return RAC_ERROR_NULL_POINTER;
    }

    int required = MultiByteToWideChar(CP_UTF8, 0, src, -1, NULL, 0);
    if (required == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    if (out_required) {
        *out_required = required;
    }

    if (!out_buf || buf_wchars == 0) {
        return RAC_SUCCESS;
    }

    if (buf_wchars < required) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    if (MultiByteToWideChar(CP_UTF8, 0, src, -1, out_buf, buf_wchars) == 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    return RAC_SUCCESS;
}
