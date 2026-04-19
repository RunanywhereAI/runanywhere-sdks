// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Extended structured error codes. Ports the 900-code taxonomy from
// `sdk/runanywhere-commons/include/rac/core/rac_structured_error.h`.
//
// The basic statuses in ra_primitives.h (RA_OK, RA_ERR_CANCELLED, ...)
// cover the C ABI surface and are what frontends check. These extended
// codes are additional context a plugin or service can attach when the
// bare status code doesn't capture enough detail — surfaced via the
// ra_error_callback_t's message parameter as "[code] message".

#ifndef RA_ERRORS_H
#define RA_ERRORS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ra_extended_error_t;

enum {
    // Initialization (-100 to -109)
    RA_EX_NOT_INITIALIZED               = -100,
    RA_EX_ALREADY_INITIALIZED           = -101,
    RA_EX_INITIALIZATION_FAILED         = -102,
    RA_EX_INVALID_CONFIGURATION         = -103,
    RA_EX_INVALID_API_KEY               = -104,
    RA_EX_CONFIGURATION_CONFLICT        = -105,

    // Model (-110 to -129)
    RA_EX_MODEL_NOT_FOUND               = -110,
    RA_EX_MODEL_LOAD_FAILED             = -111,
    RA_EX_MODEL_VALIDATION_FAILED       = -112,
    RA_EX_MODEL_INCOMPATIBLE            = -113,
    RA_EX_INVALID_MODEL_FORMAT          = -114,
    RA_EX_MODEL_DOWNLOAD_FAILED         = -115,
    RA_EX_MODEL_CHECKSUM_MISMATCH       = -116,
    RA_EX_MODEL_CORRUPTED               = -117,
    RA_EX_MODEL_VERSION_UNSUPPORTED     = -118,

    // Generation (-130 to -149)
    RA_EX_GENERATION_FAILED             = -130,
    RA_EX_GENERATION_TIMEOUT            = -131,
    RA_EX_CONTEXT_TOO_LONG              = -132,
    RA_EX_TOKEN_LIMIT_EXCEEDED          = -133,
    RA_EX_COST_LIMIT_EXCEEDED           = -134,
    RA_EX_INFERENCE_FAILED              = -135,
    RA_EX_KV_CACHE_FULL                 = -136,

    // Network (-150 to -179)
    RA_EX_NETWORK_UNAVAILABLE           = -150,
    RA_EX_NETWORK_ERROR                 = -151,
    RA_EX_REQUEST_FAILED                = -152,
    RA_EX_DOWNLOAD_FAILED               = -153,
    RA_EX_UPLOAD_FAILED                 = -154,
    RA_EX_CONNECTION_TIMEOUT            = -155,
    RA_EX_DNS_RESOLUTION_FAILED         = -156,
    RA_EX_TLS_HANDSHAKE_FAILED          = -157,

    // Storage (-180 to -219)
    RA_EX_STORAGE_FULL                  = -180,
    RA_EX_STORAGE_NOT_AVAILABLE         = -181,
    RA_EX_STORAGE_CORRUPTED             = -182,
    RA_EX_STORAGE_PERMISSION_DENIED     = -183,
    RA_EX_FILE_NOT_FOUND                = -184,
    RA_EX_FILE_READ_FAILED              = -185,
    RA_EX_FILE_WRITE_FAILED             = -186,

    // Hardware (-220 to -229)
    RA_EX_HARDWARE_NOT_SUPPORTED        = -220,
    RA_EX_GPU_NOT_AVAILABLE             = -221,
    RA_EX_NPU_NOT_AVAILABLE             = -222,
    RA_EX_INSUFFICIENT_MEMORY           = -223,

    // Component state (-230 to -249)
    RA_EX_COMPONENT_NOT_READY           = -230,
    RA_EX_COMPONENT_BUSY                = -231,
    RA_EX_COMPONENT_DEAD                = -232,

    // Validation (-250 to -279)
    RA_EX_VALIDATION_FAILED             = -250,
    RA_EX_INVALID_PARAMETER             = -251,
    RA_EX_MISSING_PARAMETER             = -252,
    RA_EX_INVALID_FORMAT                = -253,

    // Audio (-280 to -299)
    RA_EX_AUDIO_FORMAT_NOT_SUPPORTED    = -280,
    RA_EX_AUDIO_DEVICE_ERROR            = -281,
    RA_EX_AUDIO_PERMISSION_DENIED       = -282,
    RA_EX_AUDIO_SAMPLE_RATE_UNSUPPORTED = -283,

    // Language / voice (-300 to -319)
    RA_EX_LANGUAGE_NOT_SUPPORTED        = -300,
    RA_EX_VOICE_NOT_AVAILABLE           = -301,

    // Auth (-320 to -329)
    RA_EX_AUTHENTICATION_FAILED         = -320,
    RA_EX_AUTHORIZATION_FAILED          = -321,
    RA_EX_API_KEY_EXPIRED               = -322,

    // Security (-330 to -349)
    RA_EX_SECURITY_ERROR                = -330,
    RA_EX_ZIP_SLIP_DETECTED             = -331,

    // Extraction (-350 to -369)
    RA_EX_EXTRACTION_FAILED             = -350,
    RA_EX_UNSUPPORTED_ARCHIVE_FORMAT    = -351,
    RA_EX_ARCHIVE_CORRUPTED             = -352,

    // Module / service (-400 to -499)
    RA_EX_SERVICE_NOT_AVAILABLE         = -400,
    RA_EX_SERVICE_INITIALIZATION_FAILED = -401,
    RA_EX_PLUGIN_NOT_LOADED             = -402,
    RA_EX_PLUGIN_ABI_MISMATCH           = -403,

    // Backend (-600 to -699) — plugins attach their own codes in this
    // range when none of the above fit.
    RA_EX_BACKEND_ERROR_BASE            = -600,

    // Event (-700 to -799)
    RA_EX_EVENT_DISPATCH_FAILED         = -700,
    RA_EX_EVENT_QUEUE_FULL              = -701,
};

// Returns a human-readable string for the given extended error code.
// Returns a static pointer valid for process lifetime. Never NULL.
const char* ra_extended_error_str(ra_extended_error_t code);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_ERRORS_H
