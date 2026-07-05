/**
 * @file api_types.cpp
 * @brief API types implementation with JSON serialization
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/network/rac_api_types.h"

// Simple JSON building helpers (no external dependencies)
// For production, consider using a proper JSON library like nlohmann/json

// Memory Management

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

void rac_api_error_free(rac_api_error_t* error) {
    if (!error)
        return;
    free(error->message);
    free(error->code);
    free(error->raw_body);
    free(error->request_url);
    memset(error, 0, sizeof(*error));
}

// JSON Building Helpers

// Escape string for JSON
static void json_escape_string(const char* src, char* dst, size_t dst_size) {
    size_t di = 0;
    for (const char* s = src; *s != '\0' && di < dst_size - 1; s++) {
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
        snprintf(buf + *pos, buf_size - *pos, R"(%s"%s":"%s")", comma ? "," : "", key, escaped);
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

// JSON Parsing Helpers (Simple hand-rolled parser)

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
    while (*found != '\0' && (*found == ' ' || *found == ':'))
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
    while (*end != '\0' && *end != '"') {
        if (*end == '\\' && *(end + 1) != '\0')
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

// Auth Request/Response Serialization

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

    return rac_strdup(buf);
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

    return rac_strdup(buf);
}

// Error Parsing

int rac_api_error_from_response(int status_code, const char* body, const char* url,
                                rac_api_error_t* out_error) {
    if (!out_error)
        return -1;

    memset(out_error, 0, sizeof(*out_error));

    out_error->status_code = status_code;
    out_error->raw_body = rac_strdup(body);
    out_error->request_url = rac_strdup(url);

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
