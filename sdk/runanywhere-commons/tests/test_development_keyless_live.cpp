// Live E2E for keyless development telemetry: init with
// environment=development and no API key. Base URL comes from the baked
// staging backend URL (STAGING_BASE_URL / development_config) or must be
// set via rac_state after bake. Emit one terminal event per modality, flush
// unauthenticated, and expect the backend to store each under the PUBLIC org.
//
// Network test against the real Staging backend — build on demand, not part
// of the ctest suite. Requires a build configured with STAGING_BASE_URL (or a
// filled local development_config.cpp), or set RAC_LIVE_BASE_URL.

#include <curl/curl.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <thread>

#include "rac/core/rac_sdk_state.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"

namespace {

int g_ok = 0;
int g_failed = 0;

int64_t now_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

size_t discard_body(char*, size_t size, size_t nmemb, void*) {
    return size * nmemb;
}

void http_send(void*, const char* endpoint, const char* json_body, size_t json_length,
               rac_bool_t requires_auth) {
    const std::string url = std::string(rac_state_get_base_url()) + endpoint;
    CURL* curl = curl_easy_init();
    if (!curl) {
        g_failed++;
        return;
    }
    curl_slist* headers = curl_slist_append(nullptr, "Content-Type: application/json");
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, json_body);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(json_length));
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, discard_body);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    const CURLcode rc = curl_easy_perform(curl);
    long status = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    std::printf("POST %s requires_auth=%d -> curl=%d http=%ld\n", endpoint,
                static_cast<int>(requires_auth), static_cast<int>(rc), status);
    (rc == CURLE_OK && status == 200) ? g_ok++ : g_failed++;
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
}

std::string random_uuid() {
#if defined(__linux__)
    std::ifstream f("/proc/sys/kernel/random/uuid");
    std::string uuid;
    std::getline(f, uuid);
    if (!uuid.empty()) {
        return uuid;
    }
#endif
    return "live-" + std::to_string(now_ms());
}

}  // namespace

int main() {
    const char* override_url = std::getenv("RAC_LIVE_BASE_URL");
    const char* base_arg = (override_url && override_url[0] != '\0') ? override_url : "";
    rac_state_initialize(RAC_ENV_DEVELOPMENT, "", base_arg, "keyless-harness-device");
    const char* base_url = rac_state_get_base_url();
    std::printf("resolved base_url: %s\n", base_url && base_url[0] ? base_url : "<empty>");
    if (!base_url || base_url[0] == '\0') {
        std::printf(
            "FAIL: development base URL did not resolve (bake STAGING_BASE_URL "
            "or set RAC_LIVE_BASE_URL)\n");
        return 1;
    }
    if (!rac_env_should_send_telemetry(RAC_ENV_DEVELOPMENT)) {
        std::printf("FAIL: rac_env_should_send_telemetry(DEVELOPMENT) is false\n");
        return 1;
    }

    curl_global_init(CURL_GLOBAL_DEFAULT);

    rac_telemetry_manager_t* mgr = rac_telemetry_manager_create(
        RAC_ENV_DEVELOPMENT, "keyless-harness-device", "linux", "0.0.0");
    rac_telemetry_manager_set_device_info(mgr, "Linux Keyless Harness", "6.12");
    rac_telemetry_manager_set_http_callback(mgr, http_send, nullptr);

    struct Case {
        const char* modality;
        const char* event_type;
    };
    // All 12 V2 modalities.
    const Case cases[] = {
        {"llm", "llm.generation.completed"},
        {"stt", "stt.transcription.completed"},
        {"tts", "tts.synthesis.completed"},
        {"vlm", "vlm.process.completed"},
        {"rag", "rag.query.completed"},
        {"imagegen", "imagegen.generate.completed"},
        {"embeddings", "embeddings.embed.completed"},
        {"vad", "vad.stopped"},
        {"voice", "voice.turn.metrics"},
        {"lora", "lora.attach.completed"},
        {"model", "model.download.completed"},
        {"system", "sdk.init.completed"},
    };

    for (const Case& c : cases) {
        const std::string id = random_uuid();
        rac_telemetry_payload_t p = rac_telemetry_payload_default();
        p.id = id.c_str();
        p.event_type = c.event_type;
        p.modality = c.modality;
        p.timestamp_ms = now_ms();
        p.created_at_ms = p.timestamp_ms;
        p.model_id = "keyless-harness-model";
        p.model_name = "Keyless Harness Model";
        p.framework = "llamacpp";
        p.device = "Linux Keyless Harness";
        p.os_version = "6.12";
        p.platform = "linux";
        p.sdk_version = "0.0.0";
        p.processing_time_ms = 42.5;
        p.has_processing_time_ms = RAC_TRUE;
        p.success = RAC_TRUE;
        p.has_success = RAC_TRUE;
        if (std::strcmp(c.modality, "llm") == 0 || std::strcmp(c.modality, "vlm") == 0) {
            p.input_tokens = 10;
            p.output_tokens = 20;
            p.total_tokens = 30;
            p.tokens_per_second = 42.0;
        }
        const rac_result_t rc = rac_telemetry_manager_track(mgr, &p);
        if (rc != RAC_SUCCESS) {
            std::printf("FAIL: track(%s) rc=%d\n", c.modality, rc);
            g_failed++;
        }
    }

    rac_telemetry_manager_flush(mgr);
    std::this_thread::sleep_for(std::chrono::seconds(2));
    rac_telemetry_manager_destroy(mgr);
    curl_global_cleanup();

    std::printf("summary: ok=%d failed=%d\n", g_ok, g_failed);
    return g_failed == 0 && g_ok >= 12 ? 0 : 1;
}
