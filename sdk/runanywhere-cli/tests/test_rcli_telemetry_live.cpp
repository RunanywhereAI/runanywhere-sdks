/**
 * @file test_rcli_telemetry_live.cpp
 * @brief Live telemetry integration test — sends real, authenticated per-modality
 *        telemetry to the configured backend and asserts each is accepted (2xx).
 *
 * This complements the hermetic commons unit test (test_telemetry_extraction),
 * which validates JSON shape offline against a mock sink. Here we exercise the
 * full wire path: rcli bootstrap() registers the desktop adapter + HTTP
 * transport and authenticates (API key -> device register -> JWT); we then
 * override the process telemetry manager's HTTP callback with a status-recording
 * POST (the same recipe as bootstrap's rcli_telemetry_http_callback) so we can
 * assert the backend's response. A strict-schema rejection (422 extra_forbidden)
 * fails the test — catching field drift against the real V2 endpoints.
 *
 * Opt-in: runs ONLY when invoked with `--live` AND the creds are in the
 * environment (RUNANYWHERE_BASE_URL + RUNANYWHERE_API_KEY, optional
 * RUNANYWHERE_ENVIRONMENT). Without those it prints a skip and exits 0, so it is
 * safe to leave registered in ctest / CI (which run it with no args).
 *
 *   RUNANYWHERE_BASE_URL=... RUNANYWHERE_API_KEY=... \
 *     ./test_rcli_telemetry_live --live
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "bootstrap.h"

#include "rac/core/rac_sdk_state.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
namespace v1 = runanywhere::v1;
#endif

static int g_checks = 0;
static int g_failures = 0;

#define CHECK(cond, msg)                                 \
    do {                                                 \
        ++g_checks;                                      \
        if (!(cond)) {                                   \
            ++g_failures;                                \
            std::fprintf(stderr, "  FAIL: %s\n", (msg)); \
        }                                                \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

namespace {

// Records the backend's response for the most recent flushed batch, then hands
// the result back to the manager. POST recipe mirrors bootstrap's
// rcli_telemetry_http_callback (all-public rac_http_* / rac_auth_* APIs).
struct LiveState {
    rac_telemetry_manager_t* manager = nullptr;
    bool called = false;
    int status = 0;
    bool ok = false;
    std::string endpoint;
    std::string body;
};

void live_post_cb(void* user_data, const char* endpoint, const char* json_body, size_t json_length,
                  rac_bool_t requires_auth) {
    auto* st = static_cast<LiveState*>(user_data);
    st->called = true;
    st->endpoint = endpoint != nullptr ? endpoint : "";
    st->status = 0;
    st->ok = false;
    st->body.clear();

    const char* base_url = rac_state_get_base_url();
    if (base_url == nullptr || base_url[0] == '\0' ||
        rac_http_transport_is_registered() != RAC_TRUE) {
        rac_telemetry_manager_http_complete(st->manager, RAC_FALSE, nullptr, "transport unavailable");
        return;
    }
    char url[2048] = {};
    if (rac_build_url(base_url, endpoint, url, sizeof(url)) < 0) {
        rac_telemetry_manager_http_complete(st->manager, RAC_FALSE, nullptr, "url build failed");
        return;
    }

    std::vector<rac_http_header_kv_t> headers;
    const rac_http_header_kv_t* defaults = nullptr;
    size_t default_count = 0;
    if (rac_http_default_headers(&defaults, &default_count) == RAC_SUCCESS && defaults != nullptr) {
        headers.assign(defaults, defaults + default_count);
    }
    std::string auth_value;
    if (requires_auth == RAC_TRUE) {
        const char* token = rac_auth_get_access_token();
        if (token != nullptr && token[0] != '\0') {
            auth_value = std::string("Bearer ") + token;
            headers.push_back({"Authorization", auth_value.c_str()});
        }
    }

    rac_http_client_t* client = nullptr;
    if (rac_http_client_create(&client) != RAC_SUCCESS) {
        rac_telemetry_manager_http_complete(st->manager, RAC_FALSE, nullptr, "client create failed");
        return;
    }
    rac_http_request_t request = {};
    request.method = "POST";
    request.url = url;
    request.headers = headers.empty() ? nullptr : headers.data();
    request.header_count = headers.size();
    request.body_bytes = reinterpret_cast<const uint8_t*>(json_body);
    request.body_len = json_length;
    request.timeout_ms = rac_env_default_http_timeout_ms(rac_state_get_environment());
    request.follow_redirects = RAC_FALSE;

    rac_http_response_t response = {};
    const rac_result_t rc = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);

    st->status = response.status;
    st->ok = rc == RAC_SUCCESS && response.status >= 200 && response.status < 300;
    if (response.body_bytes != nullptr && response.body_len > 0) {
        st->body.assign(reinterpret_cast<const char*>(response.body_bytes), response.body_len);
    }
    rac_telemetry_manager_http_complete(st->manager, st->ok ? RAC_TRUE : RAC_FALSE,
                                        st->body.empty() ? nullptr : st->body.c_str(),
                                        st->ok ? nullptr : "POST failed");
    rac_http_response_free(&response);
}

void envelope(v1::SDKEvent* ev, v1::SDKComponent component) {
    ev->set_id("rcli-live-test");
    ev->set_timestamp_ms(1);
    ev->set_component(component);
    ev->set_source("cpp");
}

// Send one event and assert the backend accepted it (2xx).
void send_and_assert(rac_telemetry_manager_t* mgr, LiveState* st, const v1::SDKEvent& ev,
                     const char* label) {
    st->called = false;
    const std::string bytes = ev.SerializeAsString();
    rac_telemetry_manager_track_proto(mgr, reinterpret_cast<const uint8_t*>(bytes.data()),
                                      bytes.size());
    if (!st->called) {
        // No completion flush fired (unexpected for a completion event).
        ++g_checks;
        ++g_failures;
        std::fprintf(stderr, "  FAIL: %s: no POST was made\n", label);
        return;
    }
    if (!st->ok) {
        std::fprintf(stderr, "  %s: http=%d body=%s\n", label, st->status,
                     st->body.empty() ? "(empty)" : st->body.c_str());
    } else {
        std::fprintf(stdout, "  %s: accepted (http=%d, %s)\n", label, st->status,
                     st->endpoint.c_str());
    }
    CHECK(st->ok, label);
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF

int main(int argc, char** argv) {
    std::fprintf(stdout, "test_rcli_telemetry_live\n");

    bool live = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--live") == 0) {
            live = true;
        }
    }
    const char* base = std::getenv("RUNANYWHERE_BASE_URL");
    const char* key = std::getenv("RUNANYWHERE_API_KEY");
    const bool have_creds = base != nullptr && base[0] != '\0' && key != nullptr && key[0] != '\0';

    if (!live || !have_creds) {
        std::fprintf(stdout,
                     "  skip: live telemetry test (needs --live and "
                     "RUNANYWHERE_BASE_URL + RUNANYWHERE_API_KEY)\n");
        return 0;
    }

#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: no protobuf\n");
    return 0;
#else
    rcli::GlobalOptions opts;
    opts.quiet = true;
    rcli::Bootstrapped env;
    const rac_result_t brc = rcli::bootstrap(opts, &env);
    CHECK(brc == RAC_SUCCESS, "bootstrap succeeded");
    if (brc != RAC_SUCCESS) {
        return 1;
    }

    rac_telemetry_manager_t* mgr = rcli::active_telemetry_manager();
    CHECK(mgr != nullptr, "telemetry manager initialized (creds + auth)");
    if (mgr == nullptr) {
        rcli::shutdown();
        return 1;
    }

    LiveState state;
    state.manager = mgr;
    rac_telemetry_manager_set_http_callback(mgr, live_post_cb, &state);

    // LLM
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_LLM);
        auto* g = ev.mutable_generation();
        g->set_kind(v1::GENERATION_EVENT_KIND_COMPLETED);
        g->set_model_id("rcli-live-test");
        g->set_input_tokens(10);
        g->set_tokens_used(20);
        g->set_tokens_per_second(40.0);
        g->set_prompt_eval_time_ms(100);
        send_and_assert(mgr, &state, ev, "llm");
    }
    // Embeddings
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_EMBEDDINGS);
        (*ev.mutable_properties())["embedding_dimension"] = "384";
        (*ev.mutable_properties())["total_tokens"] = "8";
        (*ev.mutable_properties())["batch_size"] = "1";
        auto* c = ev.mutable_capability();
        c->set_kind(v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED);
        c->set_component(v1::SDK_COMPONENT_EMBEDDINGS);
        c->set_model_id("rcli-live-test");
        c->set_input_count(1);
        c->set_output_count(1);
        send_and_assert(mgr, &state, ev, "embeddings");
    }
    // RAG
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_RAG);
        (*ev.mutable_properties())["top_k"] = "5";
        (*ev.mutable_properties())["retrieval_time_ms"] = "1";
        (*ev.mutable_properties())["embedding_model"] = "rcli-live-test";
        (*ev.mutable_properties())["query_token_count"] = "10";
        (*ev.mutable_properties())["context_tokens"] = "49";
        auto* c = ev.mutable_capability();
        c->set_kind(v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED);
        c->set_component(v1::SDK_COMPONENT_RAG);
        c->set_model_id("rcli-live-test");
        c->set_output_count(2);
        send_and_assert(mgr, &state, ev, "rag");
    }
    // VLM
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_VLM);
        (*ev.mutable_properties())["total_tokens"] = "120";
        (*ev.mutable_properties())["tokens_per_second"] = "100.0";
        (*ev.mutable_properties())["prompt_eval_time_ms"] = "800";
        auto* c = ev.mutable_capability();
        c->set_kind(v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED);
        c->set_component(v1::SDK_COMPONENT_VLM);
        c->set_model_id("rcli-live-test");
        c->set_input_count(1);
        c->set_output_count(120);
        send_and_assert(mgr, &state, ev, "vlm");
    }
    // LoRA (failure path — rides the LLM component, modality overridden to lora)
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_LLM);
        (*ev.mutable_properties())["adapter_id"] = "rcli-live-test";
        (*ev.mutable_properties())["adapter_size_bytes"] = "4096";
        auto* c = ev.mutable_capability();
        c->set_kind(v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED);
        c->set_component(v1::SDK_COMPONENT_LLM);
        c->set_model_id("rcli-live-test");
        send_and_assert(mgr, &state, ev, "lora");
    }

    rcli::shutdown();
    std::fprintf(stdout, "  %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
#endif  // RAC_HAVE_PROTOBUF
}
