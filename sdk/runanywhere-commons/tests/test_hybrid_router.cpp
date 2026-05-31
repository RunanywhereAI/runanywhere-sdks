/**
 * @file test_hybrid_router.cpp
 * @brief Unit tests for rac_llm_hybrid_router.
 *
 * Uses two mock rac_llm_service_t instances to exercise the filter /
 * rank / cascade algorithm. No external backends — verifies the routing
 * layer in isolation. Filter / cascade / rank kinds match the spec in
 * thoughts/file.txt.
 */

#include <cstring>
#include <iostream>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/routing/rac_hybrid_types.h"
#include "rac/routing/rac_llm_hybrid_router.h"
#include "test_common.h"

namespace {

struct MockBackend {
    std::string  reply_text  = "mock response";
    rac_result_t generate_rc = RAC_SUCCESS;
    int32_t      call_count  = 0;
};

rac_result_t mock_generate(void* impl_v, const char* /*prompt*/,
                           const rac_llm_options_t* /*options*/, rac_llm_result_t* out_result) {
    auto* mock = static_cast<MockBackend*>(impl_v);
    mock->call_count += 1;
    if (mock->generate_rc != RAC_SUCCESS) {
        return mock->generate_rc;
    }
    std::memset(out_result, 0, sizeof(*out_result));
    char* buf = static_cast<char*>(std::malloc(mock->reply_text.size() + 1));
    std::memcpy(buf, mock->reply_text.data(), mock->reply_text.size());
    buf[mock->reply_text.size()] = '\0';
    out_result->text = buf;
    return RAC_SUCCESS;
}

rac_result_t mock_generate_stream(void* impl_v, const char* /*prompt*/,
                                  const rac_llm_options_t* /*options*/,
                                  rac_llm_stream_callback_fn cb, void* user_data) {
    auto* mock = static_cast<MockBackend*>(impl_v);
    mock->call_count += 1;
    if (mock->generate_rc != RAC_SUCCESS) {
        return mock->generate_rc;
    }
    if (cb != nullptr) {
        cb(mock->reply_text.c_str(), user_data);
    }
    return RAC_SUCCESS;
}

const rac_llm_service_ops_t kMockOps = {
    /* initialize                 */ nullptr,
    /* generate                   */ mock_generate,
    /* generate_stream            */ mock_generate_stream,
    /* generate_stream_with_timing*/ nullptr,
    /* get_info                   */ nullptr,
    /* cancel                     */ nullptr,
    /* cleanup                    */ nullptr,
    /* destroy                    */ nullptr,
    /* load_lora                  */ nullptr,
    /* remove_lora                */ nullptr,
    /* clear_lora                 */ nullptr,
    /* get_lora_info              */ nullptr,
    /* inject_system_prompt       */ nullptr,
    /* append_context             */ nullptr,
    /* generate_from_context      */ nullptr,
    /* clear_context              */ nullptr,
    /* create                     */ nullptr,
};

struct TestFixture {
    MockBackend offline;
    MockBackend online;
    rac_llm_service_t offline_svc{&kMockOps, &offline, "mock-offline"};
    rac_llm_service_t online_svc{&kMockOps, &online, "mock-online"};
    rac_hybrid_model_descriptor_t offline_desc{};
    rac_hybrid_model_descriptor_t online_desc{};
    rac_handle_t router = RAC_INVALID_HANDLE;

    TestFixture() {
        std::strncpy(offline_desc.model_id, "llama-1.2b", sizeof(offline_desc.model_id) - 1);
        offline_desc.model_type = RAC_HYBRID_MODEL_TYPE_OFFLINE;
        offline_desc.backend = RAC_HYBRID_BACKEND_LLAMACPP;

        std::strncpy(online_desc.model_id, "openai/gpt-4o-mini", sizeof(online_desc.model_id) - 1);
        online_desc.model_type = RAC_HYBRID_MODEL_TYPE_ONLINE;
        online_desc.backend = RAC_HYBRID_BACKEND_OPENROUTER;

        rac_llm_hybrid_router_create(&router);
        rac_llm_hybrid_router_set_offline_service(router, &offline_svc, &offline_desc);
        rac_llm_hybrid_router_set_online_service(router, &online_svc, &online_desc);
    }

    ~TestFixture() {
        if (router != RAC_INVALID_HANDLE) {
            rac_llm_hybrid_router_destroy(router);
        }
    }

    void apply_policy(const std::vector<rac_hybrid_filter_t>& filters,
                      rac_hybrid_cascade_t                    cascade,
                      rac_hybrid_rank_t                       rank) {
        rac_hybrid_routing_policy_t policy{};
        policy.hard_filters      = filters.empty() ? nullptr : filters.data();
        policy.hard_filter_count = static_cast<int32_t>(filters.size());
        policy.cascade           = cascade;
        policy.rank              = rank;
        rac_llm_hybrid_router_set_policy(router, &policy);
    }
};

rac_hybrid_filter_t network_filter() {
    rac_hybrid_filter_t f{};
    f.kind = RAC_HYBRID_FILTER_NETWORK;
    f.data.network_required = true;
    return f;
}

rac_hybrid_filter_t custom_reject_offline_filter() {
    rac_hybrid_filter_t f{};
    f.kind = RAC_HYBRID_FILTER_CUSTOM;
    std::strncpy(f.data.custom.name, "reject-offline", sizeof(f.data.custom.name) - 1);
    f.data.custom.check = [](const char* model_id, void* /*user_data*/) -> bool {
        return std::strcmp(model_id, "llama-1.2b") != 0;
    };
    f.data.custom.user_data = nullptr;
    return f;
}

rac_hybrid_cascade_t no_cascade() {
    rac_hybrid_cascade_t c{};
    c.kind = RAC_HYBRID_CASCADE_NONE;
    return c;
}

rac_hybrid_cascade_t confidence_cascade(float threshold) {
    rac_hybrid_cascade_t c{};
    c.kind = RAC_HYBRID_CASCADE_CONFIDENCE;
    c.data.confidence.threshold = threshold;
    return c;
}

TestResult run_prefer_local_no_filters() {
    TestResult r;
    r.test_name = "PreferLocalFirst rank → offline chosen";
    TestFixture fx;
    fx.apply_policy({}, no_cascade(), RAC_HYBRID_RANK_PREFER_LOCAL_FIRST);

    rac_hybrid_routing_context_t ctx{};
    ctx.is_online = true;
    ctx.battery_percent = 100;

    rac_llm_result_t            result{};
    rac_hybrid_routed_metadata_t meta{};
    rac_result_t rc = rac_llm_hybrid_router_generate(fx.router, &ctx, "hi", nullptr, &result, &meta);
    r.passed = (rc == RAC_SUCCESS) && (std::strcmp(meta.chosen_model_id, "llama-1.2b") == 0) &&
               !meta.was_fallback && (fx.offline.call_count == 1) && (fx.online.call_count == 0);
    if (!r.passed) {
        r.details = std::string("rc=") + std::to_string(rc) +
                    " chosen=" + meta.chosen_model_id +
                    " offline_calls=" + std::to_string(fx.offline.call_count) +
                    " online_calls=" + std::to_string(fx.online.call_count);
    }
    rac_llm_result_free(&result);
    return r;
}

TestResult run_network_filter_drops_online_when_offline() {
    TestResult r;
    r.test_name = "NETWORK filter drops online when ctx.is_online=false";
    TestFixture fx;
    fx.apply_policy({network_filter()}, no_cascade(), RAC_HYBRID_RANK_PREFER_LOCAL_FIRST);

    rac_hybrid_routing_context_t ctx{};
    ctx.is_online = false;

    rac_llm_result_t            result{};
    rac_hybrid_routed_metadata_t meta{};
    rac_result_t rc = rac_llm_hybrid_router_generate(fx.router, &ctx, "hi", nullptr, &result, &meta);
    r.passed = (rc == RAC_SUCCESS) && (std::strcmp(meta.chosen_model_id, "llama-1.2b") == 0) &&
               (fx.online.call_count == 0);
    if (!r.passed) {
        r.details = std::string("rc=") + std::to_string(rc) +
                    " chosen=" + meta.chosen_model_id;
    }
    rac_llm_result_free(&result);
    return r;
}

TestResult run_confidence_cascade_on_offline_error() {
    TestResult r;
    r.test_name = "Confidence cascade: offline errors → online used";
    TestFixture fx;
    fx.offline.generate_rc = RAC_ERROR_GENERATION_FAILED;
    fx.apply_policy({}, confidence_cascade(0.5f), RAC_HYBRID_RANK_PREFER_LOCAL_FIRST);

    rac_hybrid_routing_context_t ctx{};
    ctx.is_online = true;

    rac_llm_result_t            result{};
    rac_hybrid_routed_metadata_t meta{};
    rac_result_t rc = rac_llm_hybrid_router_generate(fx.router, &ctx, "hi", nullptr, &result, &meta);
    r.passed = (rc == RAC_SUCCESS) && meta.was_fallback &&
               (std::strcmp(meta.chosen_model_id, "openai/gpt-4o-mini") == 0) &&
               (meta.attempt_count == 2) && (fx.online.call_count == 1);
    if (!r.passed) {
        r.details = std::string("rc=") + std::to_string(rc) +
                    " chosen=" + meta.chosen_model_id +
                    " fallback=" + std::to_string(meta.was_fallback) +
                    " attempts=" + std::to_string(meta.attempt_count);
    }
    rac_llm_result_free(&result);
    return r;
}

TestResult run_custom_filter_drops_offline() {
    TestResult r;
    r.test_name = "Custom filter that rejects offline → online chosen";
    TestFixture fx;
    fx.apply_policy({custom_reject_offline_filter()}, no_cascade(),
                    RAC_HYBRID_RANK_PREFER_LOCAL_FIRST);

    rac_hybrid_routing_context_t ctx{};
    ctx.is_online = true;

    rac_llm_result_t            result{};
    rac_hybrid_routed_metadata_t meta{};
    rac_result_t rc = rac_llm_hybrid_router_generate(fx.router, &ctx, "hi", nullptr, &result, &meta);
    r.passed = (rc == RAC_SUCCESS) &&
               (std::strcmp(meta.chosen_model_id, "openai/gpt-4o-mini") == 0) &&
               (fx.offline.call_count == 0);
    if (!r.passed) {
        r.details = std::string("rc=") + std::to_string(rc) +
                    " chosen=" + meta.chosen_model_id;
    }
    rac_llm_result_free(&result);
    return r;
}

TestResult run_empty_router() {
    TestResult r;
    r.test_name = "Router with no services → RAC_ERROR_BACKEND_UNAVAILABLE";
    rac_handle_t router = RAC_INVALID_HANDLE;
    rac_llm_hybrid_router_create(&router);

    rac_hybrid_routing_context_t ctx{};
    ctx.is_online = true;
    rac_llm_result_t            result{};
    rac_hybrid_routed_metadata_t meta{};
    rac_result_t rc =
        rac_llm_hybrid_router_generate(router, &ctx, "hi", nullptr, &result, &meta);
    r.passed = (rc == RAC_ERROR_BACKEND_UNAVAILABLE);
    if (!r.passed) {
        r.details = std::string("rc=") + std::to_string(rc);
    }
    rac_llm_hybrid_router_destroy(router);
    return r;
}

TestResult run_streaming_confidence_cascade() {
    TestResult r;
    r.test_name = "Streaming Confidence cascade: offline fails → online streams";
    TestFixture fx;
    fx.offline.generate_rc = RAC_ERROR_GENERATION_FAILED;
    fx.online.reply_text = "from cloud";
    fx.apply_policy({}, confidence_cascade(0.5f), RAC_HYBRID_RANK_PREFER_LOCAL_FIRST);

    rac_hybrid_routing_context_t ctx{};
    ctx.is_online = true;

    std::string captured;
    auto cb = [](const char* token, void* user_data) -> rac_bool_t {
        auto* sink = static_cast<std::string*>(user_data);
        sink->append(token);
        return RAC_TRUE;
    };
    rac_hybrid_routed_metadata_t meta{};
    rac_result_t rc = rac_llm_hybrid_router_generate_stream(fx.router, &ctx, "hi", nullptr, cb,
                                                            &captured, &meta);
    r.passed = (rc == RAC_SUCCESS) && meta.was_fallback && (captured == "from cloud") &&
               (meta.attempt_count == 2);
    if (!r.passed) {
        r.details = std::string("rc=") + std::to_string(rc) +
                    " captured='" + captured + "' fallback=" +
                    std::to_string(meta.was_fallback) +
                    " attempts=" + std::to_string(meta.attempt_count);
    }
    return r;
}

}  // namespace

int main() {
    std::cout << "================ Hybrid Router Tests ================\n";
    std::vector<TestResult> results;
    results.push_back(run_prefer_local_no_filters());
    results.push_back(run_network_filter_drops_online_when_offline());
    results.push_back(run_confidence_cascade_on_offline_error());
    results.push_back(run_custom_filter_drops_offline());
    results.push_back(run_empty_router());
    results.push_back(run_streaming_confidence_cascade());
    for (const auto& r : results) {
        print_result(r);
    }
    return print_summary(results);
}
