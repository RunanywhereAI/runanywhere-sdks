/**
 * @file test_router.cpp
 * @brief Unit tests for the hybrid router core.
 *
 * Uses fake STT services (rac_stt_service_t with a fake ops vtable) that
 * record calls and return controllable confidence values — no real
 * inference required.
 */

#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <thread>
#include <vector>

#include "rac/routing/rac_router.h"
#include "test_common.h"

namespace {

// -----------------------------------------------------------------------------
// Fake STT service
// -----------------------------------------------------------------------------

struct FakeImpl {
    std::string      id;
    float            confidence  = std::numeric_limits<float>::quiet_NaN();
    rac_result_t     return_code = RAC_SUCCESS;
    std::atomic<int> call_count{0};
};

static rac_result_t fake_initialize(void* /*impl*/, const char* /*model_path*/) {
    return RAC_SUCCESS;
}
static rac_result_t fake_transcribe(void* impl, const void* /*audio*/, size_t /*size*/,
                                    const rac_stt_options_t* /*opts*/,
                                    rac_stt_result_t* out) {
    auto* fi = static_cast<FakeImpl*>(impl);
    fi->call_count.fetch_add(1, std::memory_order_relaxed);
    if (fi->return_code != RAC_SUCCESS) return fi->return_code;
    if (out) {
        std::string tag = "fake:" + fi->id;
        out->text              = strdup(tag.c_str());
        out->detected_language = nullptr;
        out->words             = nullptr;
        out->num_words         = 0;
        out->confidence        = fi->confidence;
        out->processing_time_ms = 1;
    }
    return RAC_SUCCESS;
}
static rac_result_t fake_stream(void*, const void*, size_t, const rac_stt_options_t*,
                                rac_stt_stream_callback_t, void*) {
    return RAC_ERROR_NOT_SUPPORTED;
}
static rac_result_t fake_get_info(void*, rac_stt_info_t* info) {
    if (info) {
        info->is_ready           = RAC_TRUE;
        info->current_model      = nullptr;
        info->supports_streaming = RAC_FALSE;
    }
    return RAC_SUCCESS;
}
static rac_result_t fake_cleanup(void*) { return RAC_SUCCESS; }
static void         fake_destroy(void*) {}

static const rac_stt_service_ops_t FAKE_OPS = {
    .initialize        = fake_initialize,
    .transcribe        = fake_transcribe,
    .transcribe_stream = fake_stream,
    .get_info          = fake_get_info,
    .cleanup           = fake_cleanup,
    .destroy           = fake_destroy,
};

struct FakeService {
    FakeImpl          impl;
    rac_stt_service_t service;

    explicit FakeService(const std::string& id) {
        impl.id         = id;
        service.ops     = &FAKE_OPS;
        service.impl    = &impl;
        service.model_id = nullptr;
    }
};

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

struct Spec {
    std::string id;
    int32_t     priority;
    bool        local_only;
    bool        network_required;
};

static rac_backend_descriptor_t make_desc(const Spec& s,
                                          std::vector<rac_routing_condition_t>& storage) {
    storage.clear();
    if (s.local_only) {
        rac_routing_condition_t c{};
        c.kind = RAC_COND_LOCAL_ONLY;
        storage.push_back(c);
    }
    if (s.network_required) {
        rac_routing_condition_t c{};
        c.kind = RAC_COND_NETWORK_REQUIRED;
        storage.push_back(c);
    }
    rac_backend_descriptor_t d{};
    std::strncpy(d.module_id, s.id.c_str(), sizeof(d.module_id) - 1);
    std::strncpy(d.module_name, s.id.c_str(), sizeof(d.module_name) - 1);
    d.capability      = RAC_ROUTED_CAP_STT;
    d.base_priority   = s.priority;
    d.conditions      = storage.data();
    d.condition_count = static_cast<int32_t>(storage.size());
    return d;
}

static rac_routing_context_t make_ctx(bool online,
                                      rac_routing_policy_t policy = RAC_ROUTING_POLICY_AUTO) {
    rac_routing_context_t c{};
    c.is_online              = online;
    c.policy                 = policy;
    c.preferred_framework[0] = '\0';
    return c;
}

static void free_result(rac_stt_result_t* r) {
    if (r->text) {
        free(r->text);
        r->text = nullptr;
    }
    if (r->detected_language) {
        free(r->detected_language);
        r->detected_language = nullptr;
    }
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

static TestResult test_register_and_list() {
    TestResult r{"register_and_list"};
    rac_router_t* router = rac_router_create();
    FakeService a("a"), b("b"), c("c");
    std::vector<rac_routing_condition_t> ca, cb, cc;
    auto da = make_desc({"a", 10, true, false}, ca);
    auto db = make_desc({"b", 30, true, false}, cb);
    auto dc = make_desc({"c", 20, true, false}, cc);
    rac_router_register_stt(router, &da, &a.service);
    rac_router_register_stt(router, &db, &b.service);
    rac_router_register_stt(router, &dc, &c.service);
    r.passed  = (rac_router_stt_count(router) == 3);
    r.details = "registered 3 backends";
    rac_router_destroy(router);
    return r;
}

static TestResult test_eligibility_network_required() {
    TestResult r{"eligibility_network_required"};
    rac_router_t* router = rac_router_create();
    FakeService local("local"), cloud("cloud");
    local.impl.confidence = 0.9f;
    cloud.impl.confidence = 0.9f;

    std::vector<rac_routing_condition_t> cl, cc;
    auto dl = make_desc({"local", 10, true, false}, cl);
    auto dc = make_desc({"cloud", 100, false, true}, cc);
    rac_router_register_stt(router, &dl, &local.service);
    rac_router_register_stt(router, &dc, &cloud.service);

    auto ctx = make_ctx(/*online=*/false);
    rac_stt_result_t out{};
    rac_routed_metadata_t meta{};
    uint8_t audio[16] = {0};
    rac_result_t rc = rac_router_run_stt(router, &ctx, audio, sizeof(audio), nullptr, &out, &meta);

    r.passed  = (rc == RAC_SUCCESS) && cloud.impl.call_count == 0 &&
               local.impl.call_count == 1 && std::strcmp(meta.chosen_module_id, "local") == 0;
    r.details = "offline → cloud skipped, local wins";
    free_result(&out);
    rac_router_destroy(router);
    return r;
}

static TestResult test_policy_local_only() {
    TestResult r{"policy_local_only"};
    rac_router_t* router = rac_router_create();
    FakeService local("local"), cloud("cloud");
    local.impl.confidence = 0.9f;
    cloud.impl.confidence = 0.9f;

    std::vector<rac_routing_condition_t> cl, cc;
    auto dl = make_desc({"local", 10, true, false}, cl);
    auto dc = make_desc({"cloud", 999, false, true}, cc);
    rac_router_register_stt(router, &dl, &local.service);
    rac_router_register_stt(router, &dc, &cloud.service);

    auto ctx = make_ctx(/*online=*/true, RAC_ROUTING_POLICY_LOCAL_ONLY);
    rac_stt_result_t out{};
    rac_routed_metadata_t meta{};
    uint8_t audio[16] = {0};
    rac_result_t rc = rac_router_run_stt(router, &ctx, audio, sizeof(audio), nullptr, &out, &meta);

    r.passed  = (rc == RAC_SUCCESS) && cloud.impl.call_count == 0 &&
               std::strcmp(meta.chosen_module_id, "local") == 0;
    r.details = "LOCAL_ONLY filters cloud";
    free_result(&out);
    rac_router_destroy(router);
    return r;
}

static TestResult test_cascade_triggers_on_low_confidence() {
    TestResult r{"cascade_triggers_on_low_confidence"};
    rac_router_t* router = rac_router_create();
    FakeService local("local"), cloud("cloud");
    local.impl.confidence = 0.2f;
    cloud.impl.confidence = 0.95f;

    std::vector<rac_routing_condition_t> cl, cc;
    auto dl = make_desc({"local", 100, true, false}, cl);
    auto dc = make_desc({"cloud", 50, false, false}, cc);
    rac_router_register_stt(router, &dl, &local.service);
    rac_router_register_stt(router, &dc, &cloud.service);

    auto ctx = make_ctx(true);
    rac_stt_result_t out{};
    rac_routed_metadata_t meta{};
    uint8_t audio[16] = {0};
    rac_result_t rc = rac_router_run_stt(router, &ctx, audio, sizeof(audio), nullptr, &out, &meta);

    r.passed  = (rc == RAC_SUCCESS) && local.impl.call_count == 1 && cloud.impl.call_count == 1 &&
               meta.was_fallback && std::fabs(meta.primary_confidence - 0.2f) < 1e-4f &&
               std::strcmp(meta.chosen_module_id, "cloud") == 0;
    r.details = "local 0.2 < 0.5 → cloud fallback";
    free_result(&out);
    rac_router_destroy(router);
    return r;
}

static TestResult test_cascade_skipped_when_not_local() {
    TestResult r{"cascade_skipped_when_not_local"};
    rac_router_t* router = rac_router_create();
    FakeService primary("cloud1"), fallback("cloud2");
    primary.impl.confidence  = 0.2f;
    fallback.impl.confidence = 0.9f;

    std::vector<rac_routing_condition_t> c1, c2;
    auto d1 = make_desc({"cloud1", 100, false, false}, c1);
    auto d2 = make_desc({"cloud2", 50, false, false}, c2);
    rac_router_register_stt(router, &d1, &primary.service);
    rac_router_register_stt(router, &d2, &fallback.service);

    auto ctx = make_ctx(true);
    rac_stt_result_t out{};
    rac_routed_metadata_t meta{};
    uint8_t audio[16] = {0};
    rac_router_run_stt(router, &ctx, audio, sizeof(audio), nullptr, &out, &meta);

    r.passed  = primary.impl.call_count == 1 && fallback.impl.call_count == 0 &&
               !meta.was_fallback && std::strcmp(meta.chosen_module_id, "cloud1") == 0;
    r.details = "non-local primary does not cascade";
    free_result(&out);
    rac_router_destroy(router);
    return r;
}

static TestResult test_nan_confidence_is_trusted() {
    TestResult r{"nan_confidence_is_trusted"};
    rac_router_t* router = rac_router_create();
    FakeService local("local"), cloud("cloud");
    local.impl.confidence = std::numeric_limits<float>::quiet_NaN();
    cloud.impl.confidence = 0.9f;

    std::vector<rac_routing_condition_t> cl, cc;
    auto dl = make_desc({"local", 100, true, false}, cl);
    auto dc = make_desc({"cloud", 50, false, false}, cc);
    rac_router_register_stt(router, &dl, &local.service);
    rac_router_register_stt(router, &dc, &cloud.service);

    auto ctx = make_ctx(true);
    rac_stt_result_t out{};
    rac_routed_metadata_t meta{};
    uint8_t audio[16] = {0};
    rac_router_run_stt(router, &ctx, audio, sizeof(audio), nullptr, &out, &meta);

    r.passed  = local.impl.call_count == 1 && cloud.impl.call_count == 0 && !meta.was_fallback &&
               std::strcmp(meta.chosen_module_id, "local") == 0;
    r.details = "NaN confidence → no cascade";
    free_result(&out);
    rac_router_destroy(router);
    return r;
}

static TestResult test_unregister_removes_backend() {
    TestResult r{"unregister_removes_backend"};
    rac_router_t* router = rac_router_create();
    FakeService a("a");
    std::vector<rac_routing_condition_t> ca;
    auto da = make_desc({"a", 10, true, false}, ca);
    rac_router_register_stt(router, &da, &a.service);
    int before      = rac_router_stt_count(router);
    rac_result_t rc = rac_router_unregister_stt(router, "a");
    int after       = rac_router_stt_count(router);
    r.passed        = before == 1 && after == 0 && rc == RAC_SUCCESS;
    rac_router_destroy(router);
    return r;
}

static TestResult test_concurrent_run_and_register() {
    TestResult r{"concurrent_run_and_register"};
    rac_router_t* router = rac_router_create();
    FakeService primary("primary");
    primary.impl.confidence = 0.9f;
    std::vector<rac_routing_condition_t> ca;
    auto da = make_desc({"primary", 50, true, false}, ca);
    rac_router_register_stt(router, &da, &primary.service);

    auto ctx = make_ctx(true);
    std::atomic<bool> stop{false};
    std::atomic<int>  successes{0};

    std::thread runner([&] {
        while (!stop.load(std::memory_order_relaxed)) {
            rac_stt_result_t out{};
            uint8_t          audio[16] = {0};
            if (rac_router_run_stt(router, &ctx, audio, sizeof(audio), nullptr, &out, nullptr) ==
                RAC_SUCCESS) {
                successes.fetch_add(1);
            }
            free_result(&out);
        }
    });

    std::vector<FakeService> extras;
    extras.reserve(8);
    std::vector<std::vector<rac_routing_condition_t>> extra_conds(8);
    for (int i = 0; i < 8; ++i) {
        extras.emplace_back("extra" + std::to_string(i));
        extras.back().impl.confidence = 0.9f;
        auto d = make_desc({extras.back().impl.id, 10, true, false}, extra_conds[i]);
        rac_router_register_stt(router, &d, &extras.back().service);
        rac_router_unregister_stt(router, extras.back().impl.id.c_str());
    }

    stop.store(true);
    runner.join();

    r.passed  = successes.load() > 0;
    r.details = "runs survived concurrent (un)registrations";
    rac_router_destroy(router);
    return r;
}

static bool always_false(void* user_data, const rac_routing_context_t* /*ctx*/) {
    auto* count = static_cast<int*>(user_data);
    (*count)++;
    return false;
}

static TestResult test_custom_condition_callback() {
    TestResult r{"custom_condition_callback"};
    rac_router_t* router = rac_router_create();
    FakeService blocked("blocked"), allowed("allowed");
    blocked.impl.confidence = 0.9f;
    allowed.impl.confidence = 0.9f;

    int                     cb_hits = 0;
    rac_routing_condition_t custom{};
    custom.kind = RAC_COND_CUSTOM;
    std::strcpy(custom.data.custom.desc, "always_false");
    custom.data.custom.check     = always_false;
    custom.data.custom.user_data = &cb_hits;

    std::vector<rac_routing_condition_t> cb_conds = {custom};
    rac_backend_descriptor_t             db{};
    std::strcpy(db.module_id, "blocked");
    std::strcpy(db.module_name, "blocked");
    db.capability      = RAC_ROUTED_CAP_STT;
    db.base_priority   = 100;
    db.conditions      = cb_conds.data();
    db.condition_count = 1;

    std::vector<rac_routing_condition_t> ca_conds;
    auto da = make_desc({"allowed", 10, true, false}, ca_conds);

    rac_router_register_stt(router, &db, &blocked.service);
    rac_router_register_stt(router, &da, &allowed.service);

    auto ctx = make_ctx(true);
    rac_stt_result_t out{};
    rac_routed_metadata_t meta{};
    uint8_t audio[16] = {0};
    rac_router_run_stt(router, &ctx, audio, sizeof(audio), nullptr, &out, &meta);

    r.passed = cb_hits >= 1 && blocked.impl.call_count == 0 && allowed.impl.call_count == 1 &&
               std::strcmp(meta.chosen_module_id, "allowed") == 0;
    r.details = "custom condition user_data is threaded + respected";
    free_result(&out);
    rac_router_destroy(router);
    return r;
}

static TestResult test_scoring_order() {
    TestResult r{"scoring_order"};
    rac_router_t* router = rac_router_create();
    FakeService low("low"), high("high");
    low.impl.confidence  = 0.9f;
    high.impl.confidence = 0.9f;

    std::vector<rac_routing_condition_t> cl, ch;
    auto dl = make_desc({"low", 10, true, false}, cl);
    auto dh = make_desc({"high", 200, true, false}, ch);
    rac_router_register_stt(router, &dl, &low.service);
    rac_router_register_stt(router, &dh, &high.service);

    auto ctx = make_ctx(true);
    rac_stt_result_t out{};
    rac_routed_metadata_t meta{};
    uint8_t audio[16] = {0};
    rac_router_run_stt(router, &ctx, audio, sizeof(audio), nullptr, &out, &meta);

    r.passed  = high.impl.call_count == 1 && low.impl.call_count == 0 &&
               std::strcmp(meta.chosen_module_id, "high") == 0;
    r.details = "higher base_priority wins";
    free_result(&out);
    rac_router_destroy(router);
    return r;
}

}  // namespace

int main(int, char**) {
    std::vector<TestResult> results;
    results.push_back(test_register_and_list());
    results.push_back(test_eligibility_network_required());
    results.push_back(test_policy_local_only());
    results.push_back(test_cascade_triggers_on_low_confidence());
    results.push_back(test_cascade_skipped_when_not_local());
    results.push_back(test_nan_confidence_is_trusted());
    results.push_back(test_unregister_removes_backend());
    results.push_back(test_concurrent_run_and_register());
    results.push_back(test_custom_condition_callback());
    results.push_back(test_scoring_order());
    for (const auto& r : results) print_result(r);
    return print_summary(results);
}
