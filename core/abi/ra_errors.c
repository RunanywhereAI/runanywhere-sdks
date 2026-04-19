// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_errors.h"

const char* ra_extended_error_str(ra_extended_error_t code) {
    switch (code) {
        // Initialization
        case RA_EX_NOT_INITIALIZED:               return "Not initialized";
        case RA_EX_ALREADY_INITIALIZED:           return "Already initialized";
        case RA_EX_INITIALIZATION_FAILED:         return "Initialization failed";
        case RA_EX_INVALID_CONFIGURATION:         return "Invalid configuration";
        case RA_EX_INVALID_API_KEY:               return "Invalid API key";
        case RA_EX_CONFIGURATION_CONFLICT:        return "Configuration conflict";

        // Model
        case RA_EX_MODEL_NOT_FOUND:               return "Model not found";
        case RA_EX_MODEL_LOAD_FAILED:             return "Model load failed";
        case RA_EX_MODEL_VALIDATION_FAILED:       return "Model validation failed";
        case RA_EX_MODEL_INCOMPATIBLE:            return "Model incompatible with runtime";
        case RA_EX_INVALID_MODEL_FORMAT:          return "Invalid model format";
        case RA_EX_MODEL_DOWNLOAD_FAILED:         return "Model download failed";
        case RA_EX_MODEL_CHECKSUM_MISMATCH:       return "Model checksum mismatch";
        case RA_EX_MODEL_CORRUPTED:               return "Model file corrupted";
        case RA_EX_MODEL_VERSION_UNSUPPORTED:     return "Model version unsupported";

        // Generation
        case RA_EX_GENERATION_FAILED:             return "Generation failed";
        case RA_EX_GENERATION_TIMEOUT:            return "Generation timeout";
        case RA_EX_CONTEXT_TOO_LONG:              return "Context exceeds model limit";
        case RA_EX_TOKEN_LIMIT_EXCEEDED:          return "Token limit exceeded";
        case RA_EX_COST_LIMIT_EXCEEDED:           return "Cost limit exceeded";
        case RA_EX_INFERENCE_FAILED:              return "Inference failed";
        case RA_EX_KV_CACHE_FULL:                 return "KV cache full";

        // Network
        case RA_EX_NETWORK_UNAVAILABLE:           return "Network unavailable";
        case RA_EX_NETWORK_ERROR:                 return "Network error";
        case RA_EX_REQUEST_FAILED:                return "HTTP request failed";
        case RA_EX_DOWNLOAD_FAILED:               return "Download failed";
        case RA_EX_UPLOAD_FAILED:                 return "Upload failed";
        case RA_EX_CONNECTION_TIMEOUT:            return "Connection timeout";
        case RA_EX_DNS_RESOLUTION_FAILED:         return "DNS resolution failed";
        case RA_EX_TLS_HANDSHAKE_FAILED:          return "TLS handshake failed";

        // Storage
        case RA_EX_STORAGE_FULL:                  return "Storage full";
        case RA_EX_STORAGE_NOT_AVAILABLE:         return "Storage not available";
        case RA_EX_STORAGE_CORRUPTED:             return "Storage corrupted";
        case RA_EX_STORAGE_PERMISSION_DENIED:     return "Storage permission denied";
        case RA_EX_FILE_NOT_FOUND:                return "File not found";
        case RA_EX_FILE_READ_FAILED:              return "File read failed";
        case RA_EX_FILE_WRITE_FAILED:             return "File write failed";

        // Hardware
        case RA_EX_HARDWARE_NOT_SUPPORTED:        return "Hardware not supported";
        case RA_EX_GPU_NOT_AVAILABLE:             return "GPU not available";
        case RA_EX_NPU_NOT_AVAILABLE:             return "NPU not available";
        case RA_EX_INSUFFICIENT_MEMORY:           return "Insufficient memory";

        // Component state
        case RA_EX_COMPONENT_NOT_READY:           return "Component not ready";
        case RA_EX_COMPONENT_BUSY:                return "Component busy";
        case RA_EX_COMPONENT_DEAD:                return "Component dead";

        // Validation
        case RA_EX_VALIDATION_FAILED:             return "Validation failed";
        case RA_EX_INVALID_PARAMETER:             return "Invalid parameter";
        case RA_EX_MISSING_PARAMETER:             return "Missing parameter";
        case RA_EX_INVALID_FORMAT:                return "Invalid format";

        // Audio
        case RA_EX_AUDIO_FORMAT_NOT_SUPPORTED:    return "Audio format not supported";
        case RA_EX_AUDIO_DEVICE_ERROR:            return "Audio device error";
        case RA_EX_AUDIO_PERMISSION_DENIED:       return "Audio permission denied";
        case RA_EX_AUDIO_SAMPLE_RATE_UNSUPPORTED: return "Audio sample rate unsupported";

        // Language / voice
        case RA_EX_LANGUAGE_NOT_SUPPORTED:        return "Language not supported";
        case RA_EX_VOICE_NOT_AVAILABLE:           return "Voice not available";

        // Auth
        case RA_EX_AUTHENTICATION_FAILED:         return "Authentication failed";
        case RA_EX_AUTHORIZATION_FAILED:          return "Authorization failed";
        case RA_EX_API_KEY_EXPIRED:               return "API key expired";

        // Security
        case RA_EX_SECURITY_ERROR:                return "Security error";
        case RA_EX_ZIP_SLIP_DETECTED:             return "Zip-slip path escape detected";

        // Extraction
        case RA_EX_EXTRACTION_FAILED:             return "Extraction failed";
        case RA_EX_UNSUPPORTED_ARCHIVE_FORMAT:    return "Unsupported archive format";
        case RA_EX_ARCHIVE_CORRUPTED:             return "Archive corrupted";

        // Module / service
        case RA_EX_SERVICE_NOT_AVAILABLE:         return "Service not available";
        case RA_EX_SERVICE_INITIALIZATION_FAILED: return "Service initialization failed";
        case RA_EX_PLUGIN_NOT_LOADED:             return "Plugin not loaded";
        case RA_EX_PLUGIN_ABI_MISMATCH:           return "Plugin ABI mismatch";

        // Backend
        case RA_EX_BACKEND_ERROR_BASE:            return "Backend error";

        // Event
        case RA_EX_EVENT_DISPATCH_FAILED:         return "Event dispatch failed";
        case RA_EX_EVENT_QUEUE_FULL:              return "Event queue full";

        default:                                   return "Unknown extended error";
    }
}
