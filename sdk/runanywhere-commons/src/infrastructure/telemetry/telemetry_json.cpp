/**
 * @file telemetry_json.cpp
 * @brief JSON serialization for telemetry payloads
 *
 * Environment-aware encoding:
 * - Development (Supabase): Uses sdk_event_id, event_timestamp, includes all fields
 * - Production (FastAPI): Uses id, timestamp, skips modality/device_id (batch level)
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <string>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"

// =============================================================================
// JSON BUILDER HELPERS
// =============================================================================

namespace {

class JsonBuilder {
   public:
    void start_object() {
        ss_ << "{";
        first_ = true;
    }
    void end_object() { ss_ << "}"; }
    void start_array() {
        ss_ << "[";
        first_ = true;
    }
    void end_array() { ss_ << "]"; }

    void add_string(const char* key, const char* value) {
        if (!value)
            return;
        comma();
        ss_ << "\"" << key << "\":\"" << escape_string(value) << "\"";
    }

    void add_int(const char* key, int64_t value) {
        if (value == 0)
            return;  // Skip zero values
        comma();
        ss_ << "\"" << key << "\":" << value;
    }

    void add_int_always(const char* key, int64_t value) {
        comma();
        ss_ << "\"" << key << "\":" << value;
    }

    void add_double(const char* key, double value) {
        if (value == 0.0)
            return;  // Skip zero values
        comma();
        ss_ << "\"" << key << "\":" << value;
    }

    void add_bool(const char* key, rac_bool_t value, rac_bool_t has_value) {
        if (!has_value)
            return;
        comma();
        ss_ << "\"" << key << "\":" << (value ? "true" : "false");
    }

    void add_timestamp(const char* key, int64_t ms) {
        // Format as ISO8601 string
        time_t secs = ms / 1000;
        int millis = ms % 1000;
        struct tm tm_info;
        gmtime_r(&secs, &tm_info);

        char buf[32];
        strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S", &tm_info);

        comma();
        ss_ << "\"" << key << "\":\"" << buf << "." << std::setfill('0') << std::setw(3) << millis
            << "Z\"";
    }

    void add_raw(const char* json) {
        comma();
        ss_ << json;
    }

    std::string str() const { return ss_.str(); }

   private:
    void comma() {
        if (!first_)
            ss_ << ",";
        first_ = false;
    }

    std::string escape_string(const char* s) {
        std::string result;
        while (*s) {
            switch (*s) {
                case '"':
                    result += "\\\"";
                    break;
                case '\\':
                    result += "\\\\";
                    break;
                case '\n':
                    result += "\\n";
                    break;
                case '\r':
                    result += "\\r";
                    break;
                case '\t':
                    result += "\\t";
                    break;
                default:
                    result += *s;
            }
            s++;
        }
        return result;
    }

    std::stringstream ss_;
    bool first_ = true;
};

}  // namespace

// =============================================================================
// PAYLOAD JSON SERIALIZATION
// =============================================================================

rac_result_t rac_telemetry_manager_payload_to_json(const rac_telemetry_payload_t* payload,
                                                   rac_environment_t env, char** out_json,
                                                   size_t* out_length) {
    if (!payload || !out_json || !out_length) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    bool is_production = (env != RAC_ENV_DEVELOPMENT);
    JsonBuilder json;
    json.start_object();

    // Required fields - different key names based on environment
    if (is_production) {
        // Production: FastAPI expects "id" and "timestamp"
        json.add_string("id", payload->id);
        json.add_timestamp("timestamp", payload->timestamp_ms);
    } else {
        // Development: Supabase expects "sdk_event_id" and "event_timestamp"
        json.add_string("sdk_event_id", payload->id);
        json.add_timestamp("event_timestamp", payload->timestamp_ms);
    }

    json.add_string("event_type", payload->event_type);
    json.add_timestamp("created_at", payload->created_at_ms);

    // Conditional fields - skip for production (FastAPI has them at batch level)
    if (!is_production) {
        json.add_string("modality", payload->modality);
        json.add_string("device_id", payload->device_id);
    }

    // Session tracking
    json.add_string("session_id", payload->session_id);

    // Model info
    json.add_string("model_id", payload->model_id);
    json.add_string("model_name", payload->model_name);
    json.add_string("framework", payload->framework);

    // Device info
    json.add_string("device", payload->device);
    json.add_string("os_version", payload->os_version);
    json.add_string("platform", payload->platform);
    json.add_string("sdk_version", payload->sdk_version);

    // Common metrics
    json.add_double("processing_time_ms", payload->processing_time_ms);
    json.add_bool("success", payload->success, payload->has_success);
    json.add_string("error_message", payload->error_message);
    json.add_string("error_code", payload->error_code);

    // LLM fields
    json.add_int("input_tokens", payload->input_tokens);
    json.add_int("output_tokens", payload->output_tokens);
    json.add_int("total_tokens", payload->total_tokens);
    json.add_double("tokens_per_second", payload->tokens_per_second);
    json.add_double("time_to_first_token_ms", payload->time_to_first_token_ms);
    json.add_double("prompt_eval_time_ms", payload->prompt_eval_time_ms);
    json.add_double("generation_time_ms", payload->generation_time_ms);
    json.add_int("context_length", payload->context_length);
    json.add_double("temperature", payload->temperature);
    json.add_int("max_tokens", payload->max_tokens);

    // STT fields
    json.add_double("audio_duration_ms", payload->audio_duration_ms);
    json.add_double("real_time_factor", payload->real_time_factor);
    json.add_int("word_count", payload->word_count);
    json.add_double("confidence", payload->confidence);
    json.add_string("language", payload->language);
    json.add_bool("is_streaming", payload->is_streaming, payload->has_is_streaming);
    json.add_int("segment_index", payload->segment_index);

    // TTS fields
    json.add_int("character_count", payload->character_count);
    json.add_double("characters_per_second", payload->characters_per_second);
    json.add_int("audio_size_bytes", payload->audio_size_bytes);
    json.add_int("sample_rate", payload->sample_rate);
    json.add_string("voice", payload->voice);
    json.add_double("output_duration_ms", payload->output_duration_ms);

    // Model lifecycle
    json.add_int("model_size_bytes", payload->model_size_bytes);
    json.add_string("archive_type", payload->archive_type);

    // VAD
    json.add_double("speech_duration_ms", payload->speech_duration_ms);

    // SDK lifecycle
    json.add_int("count", payload->count);

    // Storage
    json.add_int("freed_bytes", payload->freed_bytes);

    // Network
    json.add_bool("is_online", payload->is_online, payload->has_is_online);

    json.end_object();

    std::string result = json.str();
    *out_length = result.size();
    *out_json = (char*)malloc(*out_length + 1);
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_json, result.c_str(), *out_length + 1);

    return RAC_SUCCESS;
}

// =============================================================================
// BATCH REQUEST JSON SERIALIZATION
// =============================================================================

rac_result_t rac_telemetry_manager_batch_to_json(const rac_telemetry_batch_request_t* request,
                                                 rac_environment_t env, char** out_json,
                                                 size_t* out_length) {
    if (!request || !out_json || !out_length) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    bool is_development = (env == RAC_ENV_DEVELOPMENT);

    if (is_development) {
        // Supabase: Send array directly [{...}, {...}]
        JsonBuilder json;
        json.start_array();

        for (size_t i = 0; i < request->events_count; i++) {
            char* event_json = nullptr;
            size_t event_len = 0;
            rac_result_t result = rac_telemetry_manager_payload_to_json(&request->events[i], env,
                                                                        &event_json, &event_len);
            if (result == RAC_SUCCESS && event_json) {
                if (i > 0) {
                    // Need to add comma manually since we're adding raw JSON
                }
                json.add_raw(event_json);
                free(event_json);
            }
        }

        json.end_array();

        std::string result = json.str();
        *out_length = result.size();
        *out_json = (char*)malloc(*out_length + 1);
        if (!*out_json) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(*out_json, result.c_str(), *out_length + 1);
    } else {
        // Production: Batch wrapper {"events": [...], "device_id": "...", ...}
        JsonBuilder json;
        json.start_object();

        // Events array
        std::stringstream events_ss;
        events_ss << "\"events\":[";
        for (size_t i = 0; i < request->events_count; i++) {
            if (i > 0)
                events_ss << ",";

            char* event_json = nullptr;
            size_t event_len = 0;
            rac_result_t result = rac_telemetry_manager_payload_to_json(&request->events[i], env,
                                                                        &event_json, &event_len);
            if (result == RAC_SUCCESS && event_json) {
                events_ss << event_json;
                free(event_json);
            }
        }
        events_ss << "]";
        json.add_raw(events_ss.str().c_str());

        json.add_string("device_id", request->device_id);
        json.add_timestamp("timestamp", request->timestamp_ms);
        json.add_string("modality", request->modality);

        json.end_object();

        std::string result = json.str();
        *out_length = result.size();
        *out_json = (char*)malloc(*out_length + 1);
        if (!*out_json) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(*out_json, result.c_str(), *out_length + 1);
    }

    return RAC_SUCCESS;
}

// =============================================================================
// DEVICE REGISTRATION JSON
// =============================================================================

rac_result_t rac_device_registration_to_json(const rac_device_registration_request_t* request,
                                             rac_environment_t env, char** out_json,
                                             size_t* out_length) {
    if (!request || !out_json || !out_length) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    JsonBuilder json;
    json.start_object();

    // For development mode (Supabase), flatten the structure to match Supabase schema
    // For production/staging, use nested device_info structure
    if (env == RAC_ENV_DEVELOPMENT) {
        // Flattened structure for Supabase (matches Kotlin SDK DevDeviceRegistrationRequest)
        const rac_device_registration_info_t* info = &request->device_info;
        
        // Required fields (matching Supabase schema)
        if (info->device_id) {
            json.add_string("device_id", info->device_id);
        }
        if (info->platform) {
            json.add_string("platform", info->platform);
        }
        if (info->os_version) {
            json.add_string("os_version", info->os_version);
        }
        if (info->device_model) {
            json.add_string("device_model", info->device_model);
        }
        if (request->sdk_version) {
            json.add_string("sdk_version", request->sdk_version);
        }
        
        // Optional fields
        if (request->build_token) {
            json.add_string("build_token", request->build_token);
        }
        if (info->total_memory > 0) {
            json.add_int("total_memory", info->total_memory);
        }
        if (info->architecture) {
            json.add_string("architecture", info->architecture);
        }
        if (info->chip_name) {
            json.add_string("chip_name", info->chip_name);
        }
        if (info->form_factor) {
            json.add_string("form_factor", info->form_factor);
        }
        // has_neural_engine is always set (rac_bool_t), so we can always include it
        json.add_bool("has_neural_engine", info->has_neural_engine, RAC_TRUE);
        // Add last_seen_at timestamp for UPSERT to update existing records
        if (request->last_seen_at_ms > 0) {
            json.add_timestamp("last_seen_at", request->last_seen_at_ms);
        }
    } else {
        // Nested structure for production/staging
        // Matches backend schemas/device.py DeviceInfo schema
        const rac_device_registration_info_t* info = &request->device_info;
        std::stringstream device_ss;
        device_ss << "\"device_info\":{";

        // Required fields (backend schema expects snake_case)
        device_ss << "\"device_model\":\"" << (info->device_model ? info->device_model : "") << "\"";
        device_ss << ",\"device_name\":\"" << (info->device_name ? info->device_name : "") << "\"";
        device_ss << ",\"platform\":\"" << (info->platform ? info->platform : "") << "\"";
        device_ss << ",\"os_version\":\"" << (info->os_version ? info->os_version : "") << "\"";
        device_ss << ",\"form_factor\":\"" << (info->form_factor ? info->form_factor : "phone") << "\"";
        device_ss << ",\"architecture\":\"" << (info->architecture ? info->architecture : "") << "\"";
        device_ss << ",\"chip_name\":\"" << (info->chip_name ? info->chip_name : "") << "\"";
        device_ss << ",\"total_memory\":" << info->total_memory;
        device_ss << ",\"available_memory\":" << info->available_memory;
        device_ss << ",\"has_neural_engine\":" << (info->has_neural_engine ? "true" : "false");
        device_ss << ",\"neural_engine_cores\":" << info->neural_engine_cores;
        device_ss << ",\"gpu_family\":\"" << (info->gpu_family ? info->gpu_family : "unknown") << "\"";

        // Battery info (may be unavailable)
        if (info->battery_level >= 0) {
            device_ss << ",\"battery_level\":" << info->battery_level;
        } else {
            device_ss << ",\"battery_level\":null";
        }
        if (info->battery_state) {
            device_ss << ",\"battery_state\":\"" << info->battery_state << "\"";
        } else {
            device_ss << ",\"battery_state\":null";
        }

        device_ss << ",\"is_low_power_mode\":" << (info->is_low_power_mode ? "true" : "false");
        device_ss << ",\"core_count\":" << info->core_count;
        device_ss << ",\"performance_cores\":" << info->performance_cores;
        device_ss << ",\"efficiency_cores\":" << info->efficiency_cores;

        // Device fingerprint (same as device_id for most cases)
        device_ss << ",\"device_fingerprint\":\"" << (info->device_fingerprint ? info->device_fingerprint : (info->device_id ? info->device_id : "")) << "\"";

        device_ss << "}";
        json.add_raw(device_ss.str().c_str());

        json.add_string("sdk_version", request->sdk_version);

        // Add last_seen_at timestamp for UPSERT to update existing records
        if (request->last_seen_at_ms > 0) {
            json.add_timestamp("last_seen_at", request->last_seen_at_ms);
        }
    }

    json.end_object();

    std::string result = json.str();
    *out_length = result.size();
    *out_json = (char*)malloc(*out_length + 1);
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_json, result.c_str(), *out_length + 1);

    return RAC_SUCCESS;
}

const char* rac_device_registration_endpoint(rac_environment_t env) {
    return rac_endpoint_device_registration(env);
}
