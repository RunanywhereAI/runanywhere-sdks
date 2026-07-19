/**
 * @file test_telemetry_extraction.cpp
 * @brief Unit tests for the telemetry extraction → routing → JSON pipeline.
 *
 * Feeds canonical runanywhere.v1.SDKEvent protos through
 * rac_telemetry_manager_track_proto() with a capturing HTTP callback (no
 * network, no models) and asserts the outgoing endpoint + JSON body per
 * modality. These are regression guards for the telemetry field bugs fixed in
 * commons:
 *   - LLM token undercount / tokens_per_second (decode-loop count)
 *   - LLM/VLM prompt_eval_time_ms on the result
 *   - STT NaN confidence producing invalid JSON ("confidence":nan)
 *   - embeddings total_tokens / batch_size
 *   - LoRA failure-path base_model_id / adapter_id / adapter_size_bytes
 *   - RAG query_token_count / context_tokens
 *
 * DEVELOPMENT env is used so the flush auth-gate (rac_env_requires_auth) is
 * bypassed and completion events flush synchronously into the capture callback.
 */

#include <cmath>
#include <cstdio>
#include <string>

#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
namespace v1 = runanywhere::v1;
#endif

static int g_checks = 0;
static int g_failures = 0;

#define CHECK(cond, msg)                                     \
    do {                                                     \
        ++g_checks;                                          \
        if (!(cond)) {                                       \
            ++g_failures;                                    \
            std::fprintf(stderr, "  FAIL: %s\n", (msg));     \
        }                                                    \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

namespace {

struct Capture {
    bool called = false;
    std::string endpoint;
    std::string body;
};

void capture_cb(void* user_data, const char* endpoint, const char* json_body, size_t json_length,
                rac_bool_t /*requires_auth*/) {
    auto* c = static_cast<Capture*>(user_data);
    c->called = true;
    c->endpoint = endpoint != nullptr ? endpoint : "";
    c->body.assign(json_body != nullptr ? json_body : "", json_body != nullptr ? json_length : 0);
}

bool has(const std::string& hay, const std::string& needle) {
    return hay.find(needle) != std::string::npos;
}

void envelope(v1::SDKEvent* ev, v1::SDKComponent component) {
    ev->set_id("test-event");
    ev->set_timestamp_ms(1);
    ev->set_component(component);
    ev->set_source("cpp");
}

// Serialize + track one event; the completion flush fires the capture callback
// inline. Marks the in-flight batch complete afterward so state stays clean.
void track(rac_telemetry_manager_t* mgr, Capture* cap, const v1::SDKEvent& ev) {
    cap->called = false;
    cap->endpoint.clear();
    cap->body.clear();
    const std::string bytes = ev.SerializeAsString();
    rac_telemetry_manager_track_proto(mgr, reinterpret_cast<const uint8_t*>(bytes.data()),
                                      bytes.size());
    rac_telemetry_manager_http_complete(mgr, RAC_TRUE, nullptr, nullptr);
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF

int main() {
    std::fprintf(stdout, "test_telemetry_extraction\n");

#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: telemetry extraction tests (no protobuf)\n");
    return 0;
#else
    rac_telemetry_manager_t* mgr =
        rac_telemetry_manager_create(RAC_ENV_DEVELOPMENT, "test-device", "linux", "0.20.11");
    CHECK(mgr != nullptr, "telemetry manager created");
    if (mgr == nullptr) {
        return 1;
    }
    Capture cap;
    rac_telemetry_manager_set_http_callback(mgr, capture_cb, &cap);

    // --- LLM: token count + tokens_per_second + prompt_eval_time_ms ----------
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_LLM);
        auto* g = ev.mutable_generation();
        g->set_kind(v1::GENERATION_EVENT_KIND_COMPLETED);
        g->set_model_id("qwen3-0.6b");
        g->set_input_tokens(61);
        g->set_tokens_used(256);
        g->set_tokens_per_second(44.4);
        g->set_prompt_eval_time_ms(437);
        track(mgr, &cap, ev);
        CHECK(cap.called, "llm: event delivered to sink");
        CHECK(cap.endpoint == "/api/v2/sdk/telemetry/llm", "llm: routed to llm endpoint");
        CHECK(has(cap.body, "\"output_tokens\":256"), "llm: output_tokens = 256");
        CHECK(has(cap.body, "\"prompt_eval_time_ms\":437"), "llm: prompt_eval_time_ms = 437");
        CHECK(has(cap.body, "tokens_per_second"), "llm: tokens_per_second present");
    }

    // --- STT with NaN confidence: JSON must stay valid (no "nan") -----------
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_STT);
        auto* vo = ev.mutable_voice();  // VoiceLifecycleEvent
        vo->set_kind(v1::VOICE_EVENT_KIND_STT_COMPLETED);
        vo->set_model_id("whisper-tiny.en");
        vo->set_confidence(std::nanf(""));  // whisper-tiny emits NaN confidence
        vo->set_real_time_factor(0.5);
        vo->set_word_count(4);
        vo->set_audio_length_ms(2000);
        track(mgr, &cap, ev);
        CHECK(cap.called, "stt: event delivered to sink");
        CHECK(cap.endpoint == "/api/v2/sdk/telemetry/stt", "stt: routed to stt endpoint");
        CHECK(!has(cap.body, "nan") && !has(cap.body, "NaN"),
              "stt: NaN confidence does not leak into JSON");
        CHECK(has(cap.body, "real_time_factor") || has(cap.body, "word_count"),
              "stt: fields present");
    }

    // --- Embeddings: total_tokens + batch_size + embedding_dimension --------
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_EMBEDDINGS);
        (*ev.mutable_properties())["embedding_dimension"] = "384";
        (*ev.mutable_properties())["total_tokens"] = "21";
        (*ev.mutable_properties())["batch_size"] = "1";
        auto* cap_ev = ev.mutable_capability();
        cap_ev->set_kind(v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED);
        cap_ev->set_component(v1::SDK_COMPONENT_EMBEDDINGS);
        cap_ev->set_model_id("all-minilm-l6-v2");
        cap_ev->set_input_count(1);
        cap_ev->set_output_count(1);
        track(mgr, &cap, ev);
        CHECK(cap.called, "embeddings: event delivered to sink");
        CHECK(cap.endpoint == "/api/v2/sdk/telemetry/embeddings", "embeddings: routed correctly");
        CHECK(has(cap.body, "\"total_tokens\":21"), "embeddings: total_tokens = 21");
        CHECK(has(cap.body, "\"batch_size\":1"), "embeddings: batch_size = 1");
        CHECK(has(cap.body, "\"embedding_dimension\":384"), "embeddings: embedding_dimension = 384");
    }

    // --- LoRA failure: base_model_id + adapter_id + adapter_size_bytes ------
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_LLM);  // LoRA rides on the LLM component
        (*ev.mutable_properties())["adapter_id"] = "my-test-adapter";
        (*ev.mutable_properties())["adapter_size_bytes"] = "4096";
        auto* cap_ev = ev.mutable_capability();
        cap_ev->set_kind(v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED);
        cap_ev->set_component(v1::SDK_COMPONENT_LLM);
        cap_ev->set_model_id("smollm2-360m-q8_0");  // base model
        track(mgr, &cap, ev);
        CHECK(cap.called, "lora: event delivered to sink");
        CHECK(cap.endpoint == "/api/v2/sdk/telemetry/lora", "lora: routed to lora endpoint");
        CHECK(has(cap.body, "\"operation\":\"failed\""), "lora: operation = failed");
        CHECK(has(cap.body, "smollm2-360m-q8_0"), "lora: base_model_id present");
        CHECK(has(cap.body, "\"adapter_id\":\"my-test-adapter\""), "lora: adapter_id present");
        CHECK(has(cap.body, "\"adapter_size_bytes\":4096"), "lora: adapter_size_bytes = 4096");
    }

    // --- RAG query: retrieved_docs_count + top_k + query/context tokens -----
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_RAG);
        (*ev.mutable_properties())["top_k"] = "5";
        (*ev.mutable_properties())["retrieval_time_ms"] = "1";
        (*ev.mutable_properties())["embedding_model"] = "all-minilm-l6-v2";
        (*ev.mutable_properties())["query_token_count"] = "10";
        (*ev.mutable_properties())["context_tokens"] = "49";
        auto* cap_ev = ev.mutable_capability();
        cap_ev->set_kind(v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED);
        cap_ev->set_component(v1::SDK_COMPONENT_RAG);
        cap_ev->set_model_id("smollm2-360m-q8_0");
        cap_ev->set_output_count(2);  // retrieved docs
        track(mgr, &cap, ev);
        CHECK(cap.called, "rag: event delivered to sink");
        CHECK(cap.endpoint == "/api/v2/sdk/telemetry/rag", "rag: routed to rag endpoint");
        CHECK(has(cap.body, "\"retrieved_docs_count\":2"), "rag: retrieved_docs_count = 2");
        CHECK(has(cap.body, "\"top_k\":5"), "rag: top_k = 5");
        CHECK(has(cap.body, "\"query_token_count\":10"), "rag: query_token_count = 10");
        CHECK(has(cap.body, "\"context_tokens\":49"), "rag: context_tokens = 49");
    }

    // --- VLM: image_count + prompt_eval_time_ms -----------------------------
    {
        v1::SDKEvent ev;
        envelope(&ev, v1::SDK_COMPONENT_VLM);
        (*ev.mutable_properties())["total_tokens"] = "124";
        (*ev.mutable_properties())["tokens_per_second"] = "116.7";
        (*ev.mutable_properties())["prompt_eval_time_ms"] = "826";
        auto* cap_ev = ev.mutable_capability();
        cap_ev->set_kind(v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED);
        cap_ev->set_component(v1::SDK_COMPONENT_VLM);
        cap_ev->set_model_id("smolvlm2-256m");
        cap_ev->set_input_count(1);    // image count
        cap_ev->set_output_count(128);
        track(mgr, &cap, ev);
        CHECK(cap.called, "vlm: event delivered to sink");
        CHECK(cap.endpoint == "/api/v2/sdk/telemetry/vlm", "vlm: routed to vlm endpoint");
        CHECK(has(cap.body, "\"image_count\":1"), "vlm: image_count = 1");
        CHECK(has(cap.body, "\"prompt_eval_time_ms\":826"), "vlm: prompt_eval_time_ms = 826");
    }

    rac_telemetry_manager_destroy(mgr);

    std::fprintf(stdout, "  %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
#endif  // RAC_HAVE_PROTOBUF
}
