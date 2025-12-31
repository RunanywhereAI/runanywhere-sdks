/**
 * @file api_types.cpp
 * @brief API types implementation with JSON serialization
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/infrastructure/network/rac_api_types.h"

// Simple JSON building helpers (no external dependencies)
// For production, consider using a proper JSON library like nlohmann/json

// =============================================================================
// Memory Management
// =============================================================================

static char* str_dup(const char* src) {
    if (!src)
        return nullptr;
    size_t len = strlen(src);
    char* dst = (char*)malloc(len + 1);
    if (dst) {
        memcpy(dst, src, len + 1);
    }
    return dst;
}

void rac_auth_response_free(rac_auth_response_t* response) {
    if (!response)
        return;
    free(response->access_token);
    free(response->refresh_token);
    free(response->device_id);
    free(response->user_id);
    free(response->organization_id);
    free(response->token_type);
    memset(response, 0, sizeof(*response));
}

void rac_health_response_free(rac_health_response_t* response) {
    if (!response)
        return;
    free(response->version);
    memset(response, 0, sizeof(*response));
}

void rac_device_reg_response_free(rac_device_reg_response_t* response) {
    if (!response)
        return;
    free(response->device_id);
    free(response->status);
    free(response->sync_status);
    memset(response, 0, sizeof(*response));
}

void rac_telemetry_response_free(rac_telemetry_response_t* response) {
    if (!response)
        return;
    if (response->errors) {
        for (size_t i = 0; i < response->error_count; i++) {
            free(response->errors[i]);
        }
        free(response->errors);
    }
    free(response->storage_version);
    memset(response, 0, sizeof(*response));
}

void rac_api_error_free(rac_api_error_t* error) {
    if (!error)
        return;
    free(error->message);
    free(error->code);
    free(error->raw_body);
    free(error->request_url);
    memset(error, 0, sizeof(*error));
}

// =============================================================================
// JSON Building Helpers
// =============================================================================

// Escape string for JSON
static void json_escape_string(const char* src, char* dst, size_t dst_size) {
    size_t di = 0;
    for (const char* s = src; *s && di < dst_size - 1; s++) {
        switch (*s) {
            case '"':
                if (di + 2 < dst_size) {
                    dst[di++] = '\\';
                    dst[di++] = '"';
                }
                break;
            case '\\':
                if (di + 2 < dst_size) {
                    dst[di++] = '\\';
                    dst[di++] = '\\';
                }
                break;
            case '\n':
                if (di + 2 < dst_size) {
                    dst[di++] = '\\';
                    dst[di++] = 'n';
                }
                break;
            case '\r':
                if (di + 2 < dst_size) {
                    dst[di++] = '\\';
                    dst[di++] = 'r';
                }
                break;
            case '\t':
                if (di + 2 < dst_size) {
                    dst[di++] = '\\';
                    dst[di++] = 't';
                }
                break;
            default:
                dst[di++] = *s;
                break;
        }
    }
    dst[di] = '\0';
}

// Add string field to JSON buffer
static int json_add_string(char* buf, size_t buf_size, size_t* pos, const char* key,
                           const char* value, bool comma) {
    if (!value)
        return 0;

    char escaped[1024];
    json_escape_string(value, escaped, sizeof(escaped));

    int written =
        snprintf(buf + *pos, buf_size - *pos, "%s\"%s\":\"%s\"", comma ? "," : "", key, escaped);
    if (written < 0 || (size_t)written >= buf_size - *pos)
        return -1;
    *pos += written;
    return 0;
}

// Add int field to JSON buffer
static int json_add_int(char* buf, size_t buf_size, size_t* pos, const char* key, int64_t value,
                        bool comma) {
    int written = snprintf(buf + *pos, buf_size - *pos, "%s\"%s\":%lld", comma ? "," : "", key,
                           (long long)value);
    if (written < 0 || (size_t)written >= buf_size - *pos)
        return -1;
    *pos += written;
    return 0;
}

// Add double field to JSON buffer
static int json_add_double(char* buf, size_t buf_size, size_t* pos, const char* key, double value,
                           bool comma) {
    int written =
        snprintf(buf + *pos, buf_size - *pos, "%s\"%s\":%.6f", comma ? "," : "", key, value);
    if (written < 0 || (size_t)written >= buf_size - *pos)
        return -1;
    *pos += written;
    return 0;
}

// Add bool field to JSON buffer
static int json_add_bool(char* buf, size_t buf_size, size_t* pos, const char* key, bool value,
                         bool comma) {
    int written = snprintf(buf + *pos, buf_size - *pos, "%s\"%s\":%s", comma ? "," : "", key,
                           value ? "true" : "false");
    if (written < 0 || (size_t)written >= buf_size - *pos)
        return -1;
    *pos += written;
    return 0;
}

// =============================================================================
// JSON Parsing Helpers (Simple hand-rolled parser)
// =============================================================================

// Find value for key in JSON object (returns pointer to value start)
static const char* json_find_value(const char* json, const char* key) {
    if (!json || !key)
        return nullptr;

    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);

    const char* found = strstr(json, search);
    if (!found)
        return nullptr;

    // Skip past key and colon
    found += strlen(search);
    while (*found && (*found == ' ' || *found == ':'))
        found++;

    return found;
}

// Extract string value (returns malloc'd string)
static char* json_extract_string(const char* json, const char* key) {
    const char* value = json_find_value(json, key);
    if (!value || *value != '"')
        return nullptr;

    value++;  // Skip opening quote

    // Find end quote (simple - doesn't handle all escapes)
    const char* end = value;
    while (*end && *end != '"') {
        if (*end == '\\' && *(end + 1))
            end += 2;
        else
            end++;
    }

    size_t len = end - value;
    char* result = (char*)malloc(len + 1);
    if (result) {
        // Simple unescape
        size_t di = 0;
        for (size_t si = 0; si < len && di < len; si++) {
            if (value[si] == '\\' && si + 1 < len) {
                si++;
                switch (value[si]) {
                    case 'n':
                        result[di++] = '\n';
                        break;
                    case 'r':
                        result[di++] = '\r';
                        break;
                    case 't':
                        result[di++] = '\t';
                        break;
                    default:
                        result[di++] = value[si];
                        break;
                }
            } else {
                result[di++] = value[si];
            }
        }
        result[di] = '\0';
    }
    return result;
}

// Extract integer value
static int64_t json_extract_int(const char* json, const char* key, int64_t default_val) {
    const char* value = json_find_value(json, key);
    if (!value)
        return default_val;

    // Skip null
    if (strncmp(value, "null", 4) == 0)
        return default_val;

    char* end;
    long long result = strtoll(value, &end, 10);
    if (end == value)
        return default_val;
    return result;
}

// Extract boolean value
static bool json_extract_bool(const char* json, const char* key, bool default_val) {
    const char* value = json_find_value(json, key);
    if (!value)
        return default_val;

    if (strncmp(value, "true", 4) == 0)
        return true;
    if (strncmp(value, "false", 5) == 0)
        return false;
    return default_val;
}

// =============================================================================
// Auth Request/Response Serialization
// =============================================================================

char* rac_auth_request_to_json(const rac_auth_request_t* request) {
    if (!request)
        return nullptr;

    char buf[2048];
    size_t pos = 0;

    buf[pos++] = '{';

    if (json_add_string(buf, sizeof(buf), &pos, "api_key", request->api_key, false) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "device_id", request->device_id, true) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "platform", request->platform, true) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "sdk_version", request->sdk_version, true) < 0)
        return nullptr;

    buf[pos++] = '}';
    buf[pos] = '\0';

    return str_dup(buf);
}

int rac_auth_response_from_json(const char* json, rac_auth_response_t* out_response) {
    if (!json || !out_response)
        return -1;

    memset(out_response, 0, sizeof(*out_response));

    out_response->access_token = json_extract_string(json, "access_token");
    out_response->refresh_token = json_extract_string(json, "refresh_token");
    out_response->device_id = json_extract_string(json, "device_id");
    out_response->user_id = json_extract_string(json, "user_id");
    out_response->organization_id = json_extract_string(json, "organization_id");
    out_response->token_type = json_extract_string(json, "token_type");
    out_response->expires_in = (int32_t)json_extract_int(json, "expires_in", 0);

    // Validate required fields
    if (!out_response->access_token || !out_response->refresh_token) {
        rac_auth_response_free(out_response);
        return -1;
    }

    return 0;
}

char* rac_refresh_request_to_json(const rac_refresh_request_t* request) {
    if (!request)
        return nullptr;

    char buf[1024];
    size_t pos = 0;

    buf[pos++] = '{';

    if (json_add_string(buf, sizeof(buf), &pos, "device_id", request->device_id, false) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "refresh_token", request->refresh_token, true) < 0)
        return nullptr;

    buf[pos++] = '}';
    buf[pos] = '\0';

    return str_dup(buf);
}

// =============================================================================
// Device Registration Serialization
// =============================================================================

char* rac_device_reg_request_to_json(const rac_device_reg_request_t* request) {
    if (!request)
        return nullptr;

    char buf[4096];
    size_t pos = 0;

    buf[pos++] = '{';

    // Device info object
    int written = snprintf(buf + pos, sizeof(buf) - pos, "\"device_info\":{");
    if (written < 0)
        return nullptr;
    pos += written;

    const rac_device_info_t* info = &request->device_info;
    bool first = true;

    if (info->device_fingerprint) {
        if (json_add_string(buf, sizeof(buf), &pos, "device_fingerprint", info->device_fingerprint,
                            !first) < 0)
            return nullptr;
        first = false;
    }
    if (json_add_string(buf, sizeof(buf), &pos, "device_model", info->device_model, !first) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "os_version", info->os_version, true) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "platform", info->platform, true) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "architecture", info->architecture, true) < 0)
        return nullptr;
    if (json_add_int(buf, sizeof(buf), &pos, "total_memory", info->total_memory, true) < 0)
        return nullptr;
    if (json_add_int(buf, sizeof(buf), &pos, "cpu_cores", info->cpu_cores, true) < 0)
        return nullptr;
    if (json_add_bool(buf, sizeof(buf), &pos, "has_neural_engine", info->has_neural_engine, true) <
        0)
        return nullptr;
    if (json_add_bool(buf, sizeof(buf), &pos, "has_gpu", info->has_gpu, true) < 0)
        return nullptr;

    buf[pos++] = '}';  // Close device_info

    // SDK metadata
    if (json_add_string(buf, sizeof(buf), &pos, "sdk_version", request->sdk_version, true) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "build_token", request->build_token, true) < 0)
        return nullptr;

    // Timestamp as ISO8601 string (simplified - platform can provide proper formatting)
    char timestamp[32];
    snprintf(timestamp, sizeof(timestamp), "%lld", (long long)request->last_seen_at);
    if (json_add_string(buf, sizeof(buf), &pos, "last_seen_at", timestamp, true) < 0)
        return nullptr;

    buf[pos++] = '}';
    buf[pos] = '\0';

    return str_dup(buf);
}

int rac_device_reg_response_from_json(const char* json, rac_device_reg_response_t* out_response) {
    if (!json || !out_response)
        return -1;

    memset(out_response, 0, sizeof(*out_response));

    out_response->device_id = json_extract_string(json, "device_id");
    out_response->status = json_extract_string(json, "status");
    out_response->sync_status = json_extract_string(json, "sync_status");

    return 0;
}

// =============================================================================
// Telemetry Serialization
// =============================================================================

char* rac_telemetry_event_to_json(const rac_telemetry_event_t* event) {
    if (!event)
        return nullptr;

    char buf[8192];
    size_t pos = 0;

    buf[pos++] = '{';

    // Required fields
    if (json_add_string(buf, sizeof(buf), &pos, "id", event->id, false) < 0)
        return nullptr;
    if (json_add_string(buf, sizeof(buf), &pos, "event_type", event->event_type, true) < 0)
        return nullptr;
    if (json_add_int(buf, sizeof(buf), &pos, "timestamp", event->timestamp, true) < 0)
        return nullptr;
    if (json_add_int(buf, sizeof(buf), &pos, "created_at", event->created_at, true) < 0)
        return nullptr;

    // Optional fields (only add if set)
    if (event->modality)
        if (json_add_string(buf, sizeof(buf), &pos, "modality", event->modality, true) < 0)
            return nullptr;
    if (event->device_id)
        if (json_add_string(buf, sizeof(buf), &pos, "device_id", event->device_id, true) < 0)
            return nullptr;
    if (event->session_id)
        if (json_add_string(buf, sizeof(buf), &pos, "session_id", event->session_id, true) < 0)
            return nullptr;
    if (event->model_id)
        if (json_add_string(buf, sizeof(buf), &pos, "model_id", event->model_id, true) < 0)
            return nullptr;
    if (event->model_name)
        if (json_add_string(buf, sizeof(buf), &pos, "model_name", event->model_name, true) < 0)
            return nullptr;
    if (event->framework)
        if (json_add_string(buf, sizeof(buf), &pos, "framework", event->framework, true) < 0)
            return nullptr;

    // Device info
    if (event->device)
        if (json_add_string(buf, sizeof(buf), &pos, "device", event->device, true) < 0)
            return nullptr;
    if (event->os_version)
        if (json_add_string(buf, sizeof(buf), &pos, "os_version", event->os_version, true) < 0)
            return nullptr;
    if (event->platform)
        if (json_add_string(buf, sizeof(buf), &pos, "platform", event->platform, true) < 0)
            return nullptr;
    if (event->sdk_version)
        if (json_add_string(buf, sizeof(buf), &pos, "sdk_version", event->sdk_version, true) < 0)
            return nullptr;

    // Common metrics
    if (event->processing_time_ms > 0)
        if (json_add_double(buf, sizeof(buf), &pos, "processing_time_ms", event->processing_time_ms,
                            true) < 0)
            return nullptr;
    if (event->has_success)
        if (json_add_bool(buf, sizeof(buf), &pos, "success", event->success, true) < 0)
            return nullptr;
    if (event->error_message)
        if (json_add_string(buf, sizeof(buf), &pos, "error_message", event->error_message, true) <
            0)
            return nullptr;
    if (event->error_code)
        if (json_add_string(buf, sizeof(buf), &pos, "error_code", event->error_code, true) < 0)
            return nullptr;

    // LLM metrics
    if (event->input_tokens > 0)
        if (json_add_int(buf, sizeof(buf), &pos, "input_tokens", event->input_tokens, true) < 0)
            return nullptr;
    if (event->output_tokens > 0)
        if (json_add_int(buf, sizeof(buf), &pos, "output_tokens", event->output_tokens, true) < 0)
            return nullptr;
    if (event->total_tokens > 0)
        if (json_add_int(buf, sizeof(buf), &pos, "total_tokens", event->total_tokens, true) < 0)
            return nullptr;
    if (event->tokens_per_second > 0)
        if (json_add_double(buf, sizeof(buf), &pos, "tokens_per_second", event->tokens_per_second,
                            true) < 0)
            return nullptr;
    if (event->time_to_first_token_ms > 0)
        if (json_add_double(buf, sizeof(buf), &pos, "time_to_first_token_ms",
                            event->time_to_first_token_ms, true) < 0)
            return nullptr;

    buf[pos++] = '}';
    buf[pos] = '\0';

    return str_dup(buf);
}

char* rac_telemetry_batch_to_json(const rac_telemetry_batch_t* batch) {
    if (!batch)
        return nullptr;

    // Estimate size needed
    size_t buf_size = 1024 + (batch->event_count * 8192);
    char* buf = (char*)malloc(buf_size);
    if (!buf)
        return nullptr;

    size_t pos = 0;

    buf[pos++] = '{';

    // Events array
    int written = snprintf(buf + pos, buf_size - pos, "\"events\":[");
    if (written < 0) {
        free(buf);
        return nullptr;
    }
    pos += written;

    for (size_t i = 0; i < batch->event_count; i++) {
        if (i > 0)
            buf[pos++] = ',';

        char* event_json = rac_telemetry_event_to_json(&batch->events[i]);
        if (!event_json) {
            free(buf);
            return nullptr;
        }

        size_t event_len = strlen(event_json);
        if (pos + event_len >= buf_size - 100) {
            free(event_json);
            free(buf);
            return nullptr;
        }
        memcpy(buf + pos, event_json, event_len);
        pos += event_len;
        free(event_json);
    }

    buf[pos++] = ']';  // Close events array

    // Other batch fields
    if (json_add_string(buf, buf_size, &pos, "device_id", batch->device_id, true) < 0) {
        free(buf);
        return nullptr;
    }
    if (json_add_int(buf, buf_size, &pos, "timestamp", batch->timestamp, true) < 0) {
        free(buf);
        return nullptr;
    }
    if (batch->modality)
        if (json_add_string(buf, buf_size, &pos, "modality", batch->modality, true) < 0) {
            free(buf);
            return nullptr;
        }

    buf[pos++] = '}';
    buf[pos] = '\0';

    return buf;
}

int rac_telemetry_response_from_json(const char* json, rac_telemetry_response_t* out_response) {
    if (!json || !out_response)
        return -1;

    memset(out_response, 0, sizeof(*out_response));

    out_response->success = json_extract_bool(json, "success", false);
    out_response->events_received = (int32_t)json_extract_int(json, "events_received", 0);
    out_response->events_stored = (int32_t)json_extract_int(json, "events_stored", 0);
    out_response->events_skipped = (int32_t)json_extract_int(json, "events_skipped", 0);
    out_response->storage_version = json_extract_string(json, "storage_version");

    return 0;
}

// =============================================================================
// Error Parsing
// =============================================================================

int rac_api_error_from_response(int status_code, const char* body, const char* url,
                                rac_api_error_t* out_error) {
    if (!out_error)
        return -1;

    memset(out_error, 0, sizeof(*out_error));

    out_error->status_code = status_code;
    out_error->raw_body = str_dup(body);
    out_error->request_url = str_dup(url);

    if (body) {
        // Try to extract error message from various formats
        out_error->message = json_extract_string(body, "detail");
        if (!out_error->message) {
            out_error->message = json_extract_string(body, "message");
        }
        if (!out_error->message) {
            out_error->message = json_extract_string(body, "error");
        }

        out_error->code = json_extract_string(body, "code");
    }

    return 0;
}
