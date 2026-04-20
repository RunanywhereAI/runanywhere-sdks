// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_primitives.h"

const char* ra_status_str(ra_status_t status) {
    switch (status) {
        case RA_OK:                         return "OK";
        case RA_ERR_CANCELLED:              return "Cancelled";
        case RA_ERR_INVALID_ARGUMENT:       return "Invalid argument";
        case RA_ERR_MODEL_LOAD_FAILED:      return "Model load failed";
        case RA_ERR_MODEL_NOT_FOUND:        return "Model not found";
        case RA_ERR_RUNTIME_UNAVAILABLE:    return "Runtime unavailable";
        case RA_ERR_BACKEND_UNAVAILABLE:    return "Backend unavailable";
        case RA_ERR_CAPABILITY_UNSUPPORTED: return "Capability unsupported";
        case RA_ERR_OUT_OF_MEMORY:          return "Out of memory";
        case RA_ERR_IO:                     return "I/O error";
        case RA_ERR_TIMEOUT:                return "Timeout";
        case RA_ERR_ABI_MISMATCH:           return "ABI version mismatch";
        case RA_ERR_INTERNAL:               return "Internal error";
        default:                            return "Unknown error";
    }
}
