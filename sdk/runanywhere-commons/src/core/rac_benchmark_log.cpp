/**
 * @file rac_benchmark_log.cpp
 * @brief RunAnywhere Commons - Benchmark Logging Implementation
 *
 * Serializes benchmark timing data to JSON and CSV formats,
 * and provides a convenience function to log via the RAC logging system.
 */

#include "rac/core/rac_benchmark_log.h"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_logger.h"

namespace {

/**
 * Computes a derived metric (difference) safely.
 * Returns 0.0 if either timestamp is 0 (not captured).
 */
double safe_diff(int64_t end_ms, int64_t start_ms) {
    if (end_ms <= 0 || start_ms <= 0) {
        return 0.0;
    }
    return static_cast<double>(end_ms - start_ms);
}

/**
 * Computes decode throughput in tokens/second.
 * Returns 0.0 if decode time is 0 or output_tokens is 0.
 */
double decode_tps(const rac_benchmark_timing_t* t) {
    double decode_ms = safe_diff(t->t5_last_token_ms, t->t3_prefill_end_ms);
    if (decode_ms <= 0.0 || t->output_tokens <= 0) {
        return 0.0;
    }
    return static_cast<double>(t->output_tokens) / decode_ms * 1000.0;
}

}  // namespace

extern "C" {

char* rac_benchmark_timing_to_json(const rac_benchmark_timing_t* timing) {
    if (timing == nullptr) {
        return nullptr;
    }

    double ttft_ms = safe_diff(timing->t4_first_token_ms, timing->t0_request_start_ms);
    double prefill_ms = safe_diff(timing->t3_prefill_end_ms, timing->t2_prefill_start_ms);
    double decode_ms_val = safe_diff(timing->t5_last_token_ms, timing->t3_prefill_end_ms);
    double e2e_ms = safe_diff(timing->t6_request_end_ms, timing->t0_request_start_ms);
    double tps = decode_tps(timing);

    // Build JSON string
    std::string json;
    json.reserve(512);
    json += "{";
    json += "\"t0_request_start_ms\":" + std::to_string(timing->t0_request_start_ms) + ",";
    json += "\"t2_prefill_start_ms\":" + std::to_string(timing->t2_prefill_start_ms) + ",";
    json += "\"t3_prefill_end_ms\":" + std::to_string(timing->t3_prefill_end_ms) + ",";
    json += "\"t4_first_token_ms\":" + std::to_string(timing->t4_first_token_ms) + ",";
    json += "\"t5_last_token_ms\":" + std::to_string(timing->t5_last_token_ms) + ",";
    json += "\"t6_request_end_ms\":" + std::to_string(timing->t6_request_end_ms) + ",";
    json += "\"prompt_tokens\":" + std::to_string(timing->prompt_tokens) + ",";
    json += "\"output_tokens\":" + std::to_string(timing->output_tokens) + ",";
    json += "\"status\":" + std::to_string(timing->status) + ",";
    json += "\"error_code\":" + std::to_string(timing->error_code) + ",";

    // Derived metrics
    char buf[64];
    snprintf(buf, sizeof(buf), "%.2f", ttft_ms);
    json += "\"ttft_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", prefill_ms);
    json += "\"prefill_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", decode_ms_val);
    json += "\"decode_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", e2e_ms);
    json += "\"e2e_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", tps);
    json += "\"decode_tps\":" + std::string(buf);

    json += "}";

    // Copy to heap-allocated C string
    char* result = static_cast<char*>(malloc(json.size() + 1));
    if (result != nullptr) {
        memcpy(result, json.c_str(), json.size() + 1);
    }
    return result;
}

char* rac_benchmark_timing_to_csv(const rac_benchmark_timing_t* timing, rac_bool_t header) {
    std::string csv;
    csv.reserve(256);

    if (header) {
        csv = "t0_request_start_ms,t2_prefill_start_ms,t3_prefill_end_ms,"
              "t4_first_token_ms,t5_last_token_ms,t6_request_end_ms,"
              "prompt_tokens,output_tokens,status,error_code,"
              "ttft_ms,prefill_ms,decode_ms,e2e_ms,decode_tps";
    } else {
        if (timing == nullptr) {
            return nullptr;
        }

        double ttft_ms = safe_diff(timing->t4_first_token_ms, timing->t0_request_start_ms);
        double prefill_ms = safe_diff(timing->t3_prefill_end_ms, timing->t2_prefill_start_ms);
        double decode_ms_val = safe_diff(timing->t5_last_token_ms, timing->t3_prefill_end_ms);
        double e2e_ms = safe_diff(timing->t6_request_end_ms, timing->t0_request_start_ms);
        double tps = decode_tps(timing);

        char buf[512];
        snprintf(buf, sizeof(buf),
                 "%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64
                 ",%" PRId32 ",%" PRId32 ",%" PRId32 ",%" PRId32 ",%.2f,%.2f,%.2f,%.2f,%.2f",
                 timing->t0_request_start_ms, timing->t2_prefill_start_ms,
                 timing->t3_prefill_end_ms, timing->t4_first_token_ms, timing->t5_last_token_ms,
                 timing->t6_request_end_ms, timing->prompt_tokens, timing->output_tokens,
                 timing->status, timing->error_code, ttft_ms, prefill_ms, decode_ms_val, e2e_ms,
                 tps);
        csv = buf;
    }

    char* result = static_cast<char*>(malloc(csv.size() + 1));
    if (result != nullptr) {
        memcpy(result, csv.c_str(), csv.size() + 1);
    }
    return result;
}

void rac_benchmark_timing_log(const rac_benchmark_timing_t* timing, const char* label) {
    if (timing == nullptr) {
        return;
    }

    double ttft_ms = safe_diff(timing->t4_first_token_ms, timing->t0_request_start_ms);
    double prefill_ms = safe_diff(timing->t3_prefill_end_ms, timing->t2_prefill_start_ms);
    double decode_ms_val = safe_diff(timing->t5_last_token_ms, timing->t3_prefill_end_ms);
    double e2e_ms = safe_diff(timing->t6_request_end_ms, timing->t0_request_start_ms);
    double tps = decode_tps(timing);

    const char* tag = (label != nullptr) ? label : "run";

    RAC_LOG_INFO("Benchmark",
                 "[%s] TTFT=%.1fms prefill=%.1fms decode=%.1fms E2E=%.1fms "
                 "prompt=%d output=%d tps=%.1f status=%d error=%d",
                 tag, ttft_ms, prefill_ms, decode_ms_val, e2e_ms, timing->prompt_tokens,
                 timing->output_tokens, tps, timing->status, timing->error_code);
}

}  // extern "C"
