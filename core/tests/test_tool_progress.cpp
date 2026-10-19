/**
 * @file test_tool_progress.cpp
 * @brief Tool-provider progress emission: sink routing, stamping, cancel.
 *
 * Drives execute_via_provider directly rather than a whole run loop, because
 * what needs proving here is the contract between a provider and the context
 * it is handed, not the loop around it.
 *
 * Scenarios:
 *   1. Provider emits stages; sink receives them, decoded and in order.
 *   2. Commons stamps tool_name, sequence, run_loop_handle — not the provider.
 *   3. Optional detail is present only when the provider supplied one.
 *   4. No sink installed: emit still returns true, so the tool still runs.
 *   5. Sink returning false stops the provider mid-run.
 *   6. A latched cancel makes emit return false without reaching the sink.
 *   7. is_cancelled reports without emitting.
 *   8. Unregistering the sink stops delivery.
 *   9. A provider that ignores ctx entirely still works.
 */

#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "features/llm/tool_provider_dispatch.h"
#include "rac/core/rac_error.h"
#include "rac/plugin/rac_tool_progress.h"
#include "rac/plugin/rac_tool_provider.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
#endif

namespace {

int g_test_count = 0;
int g_fail_count = 0;

#define CHECK(cond, label)                        \
    do {                                          \
        ++g_test_count;                           \
        if (!(cond)) {                            \
            ++g_fail_count;                       \
            std::printf("  FAIL: %s\n", (label)); \
        } else {                                  \
            std::printf("  ok:   %s\n", (label)); \
        }                                         \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

std::vector<runanywhere::v1::ToolProgress> g_received;
int g_sink_stop_after = -1;  // -1 = never stop

rac_bool_t recording_sink(const uint8_t* bytes, size_t size, void* user_data) {
    (void)user_data;
    runanywhere::v1::ToolProgress event;
    if (event.ParseFromArray(bytes, static_cast<int>(size))) {
        g_received.push_back(event);
    }
    if (g_sink_stop_after >= 0 && static_cast<int>(g_received.size()) >= g_sink_stop_after) {
        return RAC_FALSE;
    }
    return RAC_TRUE;
}

// How far a provider got before something told it to stop.
int g_stages_run = 0;

char* dup_json(const char* text) {
    const size_t len = std::strlen(text);
    char* out = static_cast<char*>(std::malloc(len + 1));
    std::memcpy(out, text, len + 1);
    return out;
}

rac_result_t staged_execute(const char* args_json, const rac_tool_context_t* ctx,
                            char** out_result_json, void* user_data) {
    (void)args_json;
    (void)user_data;
    g_stages_run = 0;

    if (!ctx->emit(ctx, "understanding", "Understanding the question", RAC_TOOL_PROGRESS_STARTED,
                   nullptr)) {
        *out_result_json = dup_json("{\"stopped\":true}");
        return RAC_SUCCESS;
    }
    g_stages_run = 1;

    if (!ctx->emit(ctx, "generating_questions", "Generating questions", RAC_TOOL_PROGRESS_COMPLETED,
                   "why, how, when, what")) {
        *out_result_json = dup_json("{\"stopped\":true}");
        return RAC_SUCCESS;
    }
    g_stages_run = 2;

    if (ctx->is_cancelled(ctx)) {
        *out_result_json = dup_json("{\"stopped\":true}");
        return RAC_SUCCESS;
    }

    if (!ctx->emit(ctx, "gathering", "Gathering data", RAC_TOOL_PROGRESS_FAILED,
                   "network unreachable")) {
        *out_result_json = dup_json("{\"stopped\":true}");
        return RAC_SUCCESS;
    }
    g_stages_run = 3;

    *out_result_json = dup_json("{\"summary\":\"done\"}");
    return RAC_SUCCESS;
}

rac_result_t silent_execute(const char* args_json, const rac_tool_context_t* ctx,
                            char** out_result_json, void* user_data) {
    (void)args_json;
    (void)ctx;
    (void)user_data;
    *out_result_json = dup_json("{\"summary\":\"quiet\"}");
    return RAC_SUCCESS;
}

const rac_tool_provider_t kStagedProvider = {
    /* abi_version */ RAC_TOOL_PROVIDER_ABI_VERSION,
    /* name */ "staged_tool",
    /* description */ "emits stages",
    /* category */ "Test",
    /* parameters_json */ "{}",
    /* execute */ staged_execute,
    /* published_keys */ nullptr,
    /* single_use */ 0,
    /* grounds_answer */ 0,
    /* user_data */ nullptr,
    /* reserved */ {0, 0, 0, 0, 0, 0},
};

const rac_tool_provider_t kSilentProvider = {
    /* abi_version */ RAC_TOOL_PROVIDER_ABI_VERSION,
    /* name */ "silent_tool",
    /* description */ "emits nothing",
    /* category */ "Test",
    /* parameters_json */ "{}",
    /* execute */ silent_execute,
    /* published_keys */ nullptr,
    /* single_use */ 0,
    /* grounds_answer */ 0,
    /* user_data */ nullptr,
    /* reserved */ {0, 0, 0, 0, 0, 0},
};

runanywhere::v1::ToolCall make_call(const char* name) {
    runanywhere::v1::ToolCall call;
    call.set_id("call-1");
    call.set_name(name);
    return call;
}

void reset() {
    g_received.clear();
    g_sink_stop_after = -1;
    g_stages_run = 0;
}

void test_stages_reach_sink_stamped() {
    std::printf("[1] stages reach the sink, stamped by commons\n");
    reset();
    rac_tool_provider_register(&kStagedProvider);
    rac_tool_progress_sink_register(recording_sink, nullptr);

    runanywhere::v1::ToolResult result;
    const bool handled = rac::llm::tool_calling::execute_via_provider(
        make_call("staged_tool"), 4242u, nullptr, {}, {}, &result);

    CHECK(handled, "provider answered the call");
    CHECK(g_stages_run == 3, "provider ran every stage");
    CHECK(g_received.size() == 3, "sink received three events");
    if (g_received.size() == 3) {
        CHECK(g_received[0].stage_id() == "understanding", "first stage id");
        CHECK(g_received[0].label() == "Understanding the question", "first label");
        CHECK(g_received[0].status() == runanywhere::v1::TOOL_PROGRESS_STATUS_STARTED,
              "first status");
        CHECK(!g_received[0].has_detail(), "no detail when none supplied");

        CHECK(g_received[1].detail() == "why, how, when, what", "detail carried");
        CHECK(g_received[2].status() == runanywhere::v1::TOOL_PROGRESS_STATUS_FAILED,
              "failed status carried");

        bool named = true, ordered = true, correlated = true;
        for (size_t i = 0; i < g_received.size(); ++i) {
            named = named && g_received[i].tool_name() == "staged_tool";
            ordered = ordered && g_received[i].sequence() == i;
            correlated = correlated && g_received[i].run_loop_handle() == 4242u;
        }
        CHECK(named, "commons stamped the tool name on every event");
        CHECK(ordered, "sequence is 0,1,2 in emit order");
        CHECK(correlated, "run loop handle stamped on every event");
        CHECK(g_received[0].emitted_at_ms() > 0, "timestamp stamped");
    }
    CHECK(result.result_json() == "{\"summary\":\"done\"}", "result returned");
    CHECK(!result.is_error(), "success is not flagged as an error");
    CHECK(result.completed_at_ms() >= result.started_at_ms(), "timings ordered");

    rac_tool_progress_sink_register(nullptr, nullptr);
    rac_tool_provider_unregister("staged_tool");
}

void test_no_sink_still_runs() {
    std::printf("[2] no sink installed: the tool still runs to completion\n");
    reset();
    rac_tool_provider_register(&kStagedProvider);
    CHECK(rac_tool_progress_sink_is_registered() == RAC_FALSE, "no sink registered");

    runanywhere::v1::ToolResult result;
    const bool handled = rac::llm::tool_calling::execute_via_provider(make_call("staged_tool"), 0u,
                                                                      nullptr, {}, {}, &result);

    CHECK(handled, "provider answered the call");
    CHECK(g_stages_run == 3, "nobody listening is not a reason to stop");
    CHECK(g_received.empty(), "nothing recorded");
    rac_tool_provider_unregister("staged_tool");
}

void test_sink_refusal_stops_provider() {
    std::printf("[3] a sink that stops listening stops the provider\n");
    reset();
    rac_tool_provider_register(&kStagedProvider);
    g_sink_stop_after = 1;  // refuse from the first event onward
    rac_tool_progress_sink_register(recording_sink, nullptr);

    runanywhere::v1::ToolResult result;
    rac::llm::tool_calling::execute_via_provider(make_call("staged_tool"), 1u, nullptr, {}, {},
                                                 &result);

    CHECK(g_stages_run == 0, "provider abandoned after the refused emit");
    CHECK(g_received.size() == 1, "only the refused event was delivered");
    CHECK(result.result_json() == "{\"stopped\":true}", "provider reported it stopped");

    rac_tool_progress_sink_register(nullptr, nullptr);
    rac_tool_provider_unregister("staged_tool");
}

void test_cancel_short_circuits_emit() {
    std::printf("[4] a latched cancel stops the provider without reaching the sink\n");
    reset();
    rac_tool_provider_register(&kStagedProvider);
    rac_tool_progress_sink_register(recording_sink, nullptr);

    runanywhere::v1::ToolResult result;
    rac::llm::tool_calling::execute_via_provider(
        make_call("staged_tool"), 7u, []() { return true; }, {}, {}, &result);

    CHECK(g_stages_run == 0, "provider stopped at its first emit");
    CHECK(g_received.empty(), "cancelled events never reach the sink");
    CHECK(result.result_json() == "{\"stopped\":true}", "provider reported it stopped");

    rac_tool_progress_sink_register(nullptr, nullptr);
    rac_tool_provider_unregister("staged_tool");
}

void test_cancel_visible_between_stages() {
    std::printf("[5] is_cancelled reports without emitting\n");
    reset();
    rac_tool_provider_register(&kStagedProvider);
    rac_tool_progress_sink_register(recording_sink, nullptr);

    // Cancel only after the provider's first two emits have landed, so the
    // is_cancelled() poll between stages is what stops it.
    int emits_seen = 0;
    auto cancel_after_two = [&emits_seen]() { return emits_seen++ >= 2; };

    runanywhere::v1::ToolResult result;
    rac::llm::tool_calling::execute_via_provider(make_call("staged_tool"), 9u, cancel_after_two, {},
                                                 {}, &result);

    CHECK(g_stages_run == 2, "stopped at the between-stage cancel poll");
    CHECK(g_received.size() == 2, "two events delivered before the cancel");
    CHECK(result.result_json() == "{\"stopped\":true}", "provider reported it stopped");

    rac_tool_progress_sink_register(nullptr, nullptr);
    rac_tool_provider_unregister("staged_tool");
}

void test_unregister_stops_delivery() {
    std::printf("[6] unregistering the sink stops delivery\n");
    reset();
    rac_tool_provider_register(&kStagedProvider);
    rac_tool_progress_sink_register(recording_sink, nullptr);
    CHECK(rac_tool_progress_sink_is_registered() == RAC_TRUE, "sink reported installed");
    rac_tool_progress_sink_register(nullptr, nullptr);
    CHECK(rac_tool_progress_sink_is_registered() == RAC_FALSE, "sink reported cleared");

    runanywhere::v1::ToolResult result;
    rac::llm::tool_calling::execute_via_provider(make_call("staged_tool"), 0u, nullptr, {}, {},
                                                 &result);
    CHECK(g_received.empty(), "nothing delivered after unregister");
    CHECK(g_stages_run == 3, "the tool still ran");
    rac_tool_provider_unregister("staged_tool");
}

void test_provider_may_ignore_context() {
    std::printf("[7] a provider that ignores ctx works unchanged\n");
    reset();
    rac_tool_provider_register(&kSilentProvider);
    rac_tool_progress_sink_register(recording_sink, nullptr);

    runanywhere::v1::ToolResult result;
    const bool handled = rac::llm::tool_calling::execute_via_provider(make_call("silent_tool"), 0u,
                                                                      nullptr, {}, {}, &result);

    CHECK(handled, "provider answered the call");
    CHECK(result.result_json() == "{\"summary\":\"quiet\"}", "result returned");
    CHECK(g_received.empty(), "a silent tool emits nothing");

    rac_tool_progress_sink_register(nullptr, nullptr);
    rac_tool_provider_unregister("silent_tool");
}

void test_unowned_call_falls_through() {
    std::printf("[8] an unregistered name falls through to the host executor\n");
    reset();
    runanywhere::v1::ToolResult result;
    const bool handled = rac::llm::tool_calling::execute_via_provider(make_call("nobody_owns_this"),
                                                                      0u, nullptr, {}, {}, &result);
    CHECK(!handled, "dispatch declined the call");
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    std::printf("=== tool provider progress ===\n");
#if defined(RAC_HAVE_PROTOBUF)
    test_stages_reach_sink_stamped();
    test_no_sink_still_runs();
    test_sink_refusal_stops_provider();
    test_cancel_short_circuits_emit();
    test_cancel_visible_between_stages();
    test_unregister_stops_delivery();
    test_provider_may_ignore_context();
    test_unowned_call_falls_through();
    std::printf("=== %d checks, %d failed ===\n", g_test_count, g_fail_count);
    return g_fail_count == 0 ? 0 : 1;
#else
    std::printf("skipped: built without protobuf\n");
    return 0;
#endif
}
