/**
 * @file test_decision.cpp
 * @brief Contract test for the decision primitive (RAC_PRIMITIVE_DECIDE).
 *
 * Backend-neutral: registers a small in-test fake decision engine (no model
 * file, no llama.cpp) and asserts:
 *   - RAC_PLUGIN_API_VERSION == 13 and the primitive/vtable-slot wiring.
 *   - A registered decision engine routes via rac_plugin_find(RAC_PRIMITIVE_DECIDE)
 *     and rac_engine_vtable_slot() resolves decision_ops.
 *   - Full DecisionRequest → DecisionResult proto round-trip through the
 *     component ABI, including choice/noul/score answers, probabilities,
 *     confidence, the SCORE legend, and the logical model id.
 *   - Graceful failure on null args, missing model (not loaded), and a missing
 *     decision backend (none registered).
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/decision/rac_decision_component.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

#include "decision.pb.h"

namespace {

int g_failures = 0;

void check(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        ++g_failures;
    }
}

// ---- Fake decision engine ---------------------------------------------------
//
// Deterministic answers so the round-trip can be asserted:
//   CHOICE -> the first option key always wins with probability 0.75,
//   NOUL   -> 0.9, SCORE -> expected level 1.0. Answers carry the resolved load
//   path as model_id (mirroring a real engine), which commons must replace with
//   the logical model id in the proto.

struct FakeDecisionImpl {
    std::string load_path;
};

// The pin the fake engine last received, so the request->options plumbing can
// be asserted (the engine itself does not enforce it; real engines do).
uint32_t g_last_prompt_format_pin = 0;

rac_result_t fake_create(const char* model_id, const char* /*config*/, void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = new FakeDecisionImpl{};
    return RAC_SUCCESS;
}

rac_result_t fake_initialize(void* impl, const char* model_path) {
    if (!impl || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    static_cast<FakeDecisionImpl*>(impl)->load_path = model_path;
    return RAC_SUCCESS;
}

rac_result_t fake_decide(void* impl, const char* state, const rac_decision_question_t* questions,
                         size_t question_count, const rac_decision_options_t* options,
                         rac_decision_result_t* out_result) {
    if (!impl || !state || !out_result || (question_count > 0 && !questions)) {
        return RAC_ERROR_NULL_POINTER;
    }
    g_last_prompt_format_pin = options != nullptr ? options->prompt_format_version : 0;
    *out_result = {};
    out_result->processing_time_ms = 1;
    const auto* fake = static_cast<const FakeDecisionImpl*>(impl);
    out_result->model_id = strdup(fake->load_path.empty() ? "fake-decider" : fake->load_path.c_str());
    out_result->input_tokens = 42;
    // The fake engine serves the shared default version, so the pin-mismatch
    // path can be exercised against a known value.
    out_result->prompt_format_version = rac_decision_default_prompt_format_version();

    out_result->answers = static_cast<rac_decision_answer_t*>(
        std::calloc(question_count, sizeof(rac_decision_answer_t)));
    if (!out_result->answers) {
        rac_decision_result_free(out_result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->answer_count = question_count;

    for (size_t i = 0; i < question_count; ++i) {
        const auto& question = questions[i];
        auto& answer = out_result->answers[i];
        answer.id = strdup(question.id ? question.id : "");
        answer.type = question.type;
        answer.probability_count = question.option_count;
        answer.probabilities = static_cast<float*>(std::calloc(
            question.option_count ? question.option_count : 1, sizeof(float)));
        if (!answer.probabilities) {
            rac_decision_result_free(out_result);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        switch (question.type) {
            case RAC_DECISION_QUESTION_CHOICE:
                // first option wins, 75/25 split across two options
                answer.probabilities[0] = 0.75f;
                if (question.option_count > 1) {
                    answer.probabilities[1] = 0.25f;
                }
                answer.choice = strdup(question.option_count > 0 && question.options[0].key
                                           ? question.options[0].key
                                           : "a");
                answer.confidence = 0.5f;
                break;
            case RAC_DECISION_QUESTION_NOUL:
                answer.noul = 0.9f;
                answer.confidence = 0.8f;
                break;
            case RAC_DECISION_QUESTION_SCORE:
                answer.score = 1.0f;
                for (size_t j = 0; j < question.option_count; ++j) {
                    answer.probabilities[j] = j == 1 ? 1.0f : 0.0f;
                }
                answer.confidence = 0.7f;
                break;
            default:
                break;
        }
    }
    return RAC_SUCCESS;
}

rac_result_t fake_cleanup(void* /*impl*/) { return RAC_SUCCESS; }

void fake_destroy(void* impl) { delete static_cast<FakeDecisionImpl*>(impl); }

const rac_decision_service_ops_t g_fake_decision_ops = {
    /* initialize */ fake_initialize,
    /* decide     */ fake_decide,
    /* cleanup    */ fake_cleanup,
    /* destroy    */ fake_destroy,
    /* create     */ fake_create,
};

rac_engine_vtable_t make_fake_vtable() {
    rac_engine_vtable_t vt{};
    vt.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vt.metadata.name = "fake_decision";
    vt.metadata.display_name = "Fake Decider";
    vt.metadata.engine_version = "0.0.0";
    vt.metadata.priority = 10;
    vt.decision_ops = &g_fake_decision_ops;
    return vt;
}

std::string build_request(const std::string& state, uint32_t prompt_format_pin = 0) {
    runanywhere::v1::DecisionRequest request;
    request.set_state(state);
    if (prompt_format_pin != 0) {
        request.mutable_options()->set_prompt_format_version(prompt_format_pin);
    }

    auto* team = request.add_questions();
    team->set_id("team");
    team->set_type(runanywhere::v1::DECISION_QUESTION_TYPE_CHOICE);
    team->set_instructions("Which team?");
    auto* billing = team->add_options();
    billing->set_key("billing");
    billing->set_description("Payments and refunds");
    auto* technical = team->add_options();
    technical->set_key("technical");
    technical->set_description("Bugs");

    auto* refund = request.add_questions();
    refund->set_id("refund");
    refund->set_type(runanywhere::v1::DECISION_QUESTION_TYPE_NOUL);
    refund->set_instructions("Does the customer ask for a refund?");
    auto* yes = refund->add_options();
    yes->set_key("true");
    auto* no = refund->add_options();
    no->set_key("false");

    auto* urgency = request.add_questions();
    urgency->set_id("urgency");
    urgency->set_type(runanywhere::v1::DECISION_QUESTION_TYPE_SCORE);
    urgency->set_instructions("How urgent?");
    auto* routine = urgency->add_options();
    routine->set_key("0");
    routine->set_description("Routine");
    auto* soon = urgency->add_options();
    soon->set_key("1");
    soon->set_description("Soon");
    auto* urgent = urgency->add_options();
    urgent->set_key("2");
    urgent->set_description("Urgent");

    return request.SerializeAsString();
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_decision\n");

    // (1) ABI + primitive naming. The version pin is an exact tripwire: bumping
    // it is only correct once the wire value below has been re-verified, because
    // a promotion that shifted wire 14 would reroute every decision call.
    check(RAC_PLUGIN_API_VERSION == 13u, "RAC_PLUGIN_API_VERSION must be 13");
    check(std::strcmp(rac_primitive_name(RAC_PRIMITIVE_DECIDE), "decide") == 0,
          "rac_primitive_name(RAC_PRIMITIVE_DECIDE) == \"decide\"");
    check(static_cast<int>(RAC_PRIMITIVE_DECIDE) == 14, "RAC_PRIMITIVE_DECIDE wire value is 14");

    // (2) No backend registered yet → create fails gracefully, no route.
    check(rac_plugin_find(RAC_PRIMITIVE_DECIDE) == nullptr,
          "no decision plugin before registration");
    rac_handle_t no_engine = nullptr;
    check(rac_decision_create("some-model", &no_engine) == RAC_ERROR_BACKEND_NOT_FOUND,
          "rac_decision_create with no engine → BACKEND_NOT_FOUND");
    check(no_engine == nullptr, "no service handle produced without a backend");
    check(rac_decision_create(nullptr, &no_engine) == RAC_ERROR_NULL_POINTER,
          "rac_decision_create(nullptr) → NULL_POINTER");

    // (3) Register the fake engine and assert routing + slot resolution.
    static rac_engine_vtable_t fake_vt = make_fake_vtable();
    check(rac_plugin_register(&fake_vt) == RAC_SUCCESS, "fake decision engine registers");
    const rac_engine_vtable_t* found = rac_plugin_find(RAC_PRIMITIVE_DECIDE);
    check(found == &fake_vt, "rac_plugin_find(RAC_PRIMITIVE_DECIDE) returns the fake engine");
    check(rac_engine_vtable_slot(&fake_vt, RAC_PRIMITIVE_DECIDE) == fake_vt.decision_ops,
          "rac_engine_vtable_slot resolves decision_ops");

    // (4) Component lifecycle + proto round-trip against the fake backend.
    rac_handle_t component = nullptr;
    check(rac_decision_component_create(&component) == RAC_SUCCESS && component != nullptr,
          "decision component created");

    // Missing-model: deciding before a model is loaded fails gracefully.
    {
        const std::string request_bytes = build_request("ticket text");
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_decision_component_decide_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc != RAC_SUCCESS, "decide before load → error (not loaded)");
        rac_proto_buffer_free(&out);
    }

    check(rac_decision_component_load_model(component, "/tmp/fake-decider", "fake-decider",
                                            "Fake Decider") == RAC_SUCCESS,
          "decision component loads via the fake engine");
    check(rac_decision_component_is_loaded(component) == RAC_TRUE, "component reports loaded");

    {
        const std::string request_bytes = build_request("I was charged twice.");
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_decision_component_decide_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc == RAC_SUCCESS, "decide_proto succeeds against a loaded model");

        uint8_t* data = nullptr;
        size_t size = 0;
        check(rac_proto_buffer_take_data(&out, &data, &size) == RAC_SUCCESS,
              "decision result buffer holds serialized proto");
        runanywhere::v1::DecisionResult result;
        check(result.ParseFromArray(data, static_cast<int>(size)), "DecisionResult parses");
        check(result.answers_size() == 3, "one answer per question, in order");
        if (result.answers_size() == 3) {
            const auto& team = result.answers(0);
            check(team.id() == "team" && team.type() == runanywhere::v1::DECISION_QUESTION_TYPE_CHOICE,
                  "answer 0 is the team CHOICE question");
            check(team.choice() == "billing", "CHOICE answer carries the winning option key");
            check(team.probabilities().at("billing") == 0.75f &&
                      team.probabilities().at("technical") == 0.25f,
                  "CHOICE probabilities are keyed by the request option keys");
            check(team.confidence() == 0.5f, "CHOICE confidence round-trips");

            const auto& refund = result.answers(1);
            check(refund.id() == "refund" && refund.type() == runanywhere::v1::DECISION_QUESTION_TYPE_NOUL,
                  "answer 1 is the refund NOUL question");
            check(refund.noul() == 0.9f, "NOUL answer carries p(true)");

            const auto& urgency = result.answers(2);
            check(urgency.id() == "urgency" &&
                      urgency.type() == runanywhere::v1::DECISION_QUESTION_TYPE_SCORE,
                  "answer 2 is the urgency SCORE question");
            check(urgency.score() == 1.0f, "SCORE answer carries the expected level");
            check(urgency.legend().at("1") == "Soon", "SCORE legend maps level key to description");
        }
        // The backend echoed the load path ("/tmp/fake-decider"); commons must
        // report the LOGICAL model id, never the device path.
        check(result.model_id() == "fake-decider",
              "result carries the logical model id, not the backend-reported load path");
        check(result.usage().input_tokens() == 42 && result.usage().output_tokens() == 0,
              "usage reports input tokens only");
        check(result.prompt_format_version() == rac_decision_default_prompt_format_version(),
              "result carries the prompt-wording version the model served");
        std::free(data);
        rac_proto_buffer_free(&out);
    }

    // The request pin reaches the engine's options unchanged.
    {
        const uint32_t pin = rac_decision_default_prompt_format_version();
        const std::string request_bytes = build_request("pinned request", pin);
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_decision_component_decide_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc == RAC_SUCCESS, "decide_proto with a prompt-format pin succeeds");
        check(g_last_prompt_format_pin == pin,
              "request prompt_format_version reaches the engine options");
        rac_proto_buffer_free(&out);
    }

    // A request with no questions is rejected.
    {
        runanywhere::v1::DecisionRequest empty;
        empty.set_state("state");
        const std::string request_bytes = empty.SerializeAsString();
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_decision_component_decide_proto(
            component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &out);
        check(rc != RAC_SUCCESS, "a question-less request is rejected");
        rac_proto_buffer_free(&out);
    }

    // Garbage bytes are rejected with a decode error, not a crash.
    {
        const uint8_t garbage[] = {0xff, 0xff, 0xff, 0x01, 0x02};
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc =
            rac_decision_component_decide_proto(component, garbage, sizeof(garbage), &out);
        check(rc != RAC_SUCCESS, "garbage request bytes are rejected");
        rac_proto_buffer_free(&out);
    }

    // Rejected requests: blank state, duplicate option keys, invalid keys, and
    // fewer than two options on CHOICE/SCORE. Each used to score silently.
    {
        auto expect_rejected = [&](runanywhere::v1::DecisionRequest request,
                                   const char* what) {
            const std::string bytes = request.SerializeAsString();
            rac_proto_buffer_t out = {};
            rac_proto_buffer_init(&out);
            const rac_result_t rc = rac_decision_component_decide_proto(
                component, reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &out);
            check(rc != RAC_SUCCESS, what);
            rac_proto_buffer_free(&out);
        };

        runanywhere::v1::DecisionRequest blank;
        blank.set_state("   ");
        blank.add_questions()->set_id("q");
        expect_rejected(std::move(blank), "blank state is rejected");

        runanywhere::v1::DecisionRequest duplicate;
        duplicate.set_state("state");
        auto* dup = duplicate.add_questions();
        dup->set_id("q");
        dup->set_type(runanywhere::v1::DECISION_QUESTION_TYPE_CHOICE);
        dup->set_instructions("Pick");
        dup->add_options()->set_key("a");
        dup->add_options()->set_key("A");  // duplicates a, ignoring case
        expect_rejected(std::move(duplicate), "duplicate option keys are rejected");

        runanywhere::v1::DecisionRequest empty_key;
        empty_key.set_state("state");
        auto* ek = empty_key.add_questions();
        ek->set_id("q");
        ek->set_type(runanywhere::v1::DECISION_QUESTION_TYPE_CHOICE);
        ek->set_instructions("Pick");
        ek->add_options()->set_key("");
        ek->add_options()->set_key("b");
        expect_rejected(std::move(empty_key), "empty option key is rejected");

        runanywhere::v1::DecisionRequest single;
        single.set_state("state");
        auto* one = single.add_questions();
        one->set_id("q");
        one->set_type(runanywhere::v1::DECISION_QUESTION_TYPE_CHOICE);
        one->set_instructions("Pick");
        one->add_options()->set_key("only");
        expect_rejected(std::move(single), "single-option choice is rejected");

        runanywhere::v1::DecisionRequest unknown_type;
        unknown_type.set_state("state");
        auto* ut = unknown_type.add_questions();
        ut->set_id("q");
        ut->set_instructions("Pick");
        ut->add_options()->set_key("a");
        ut->add_options()->set_key("b");
        expect_rejected(std::move(unknown_type), "unspecified question type is rejected");
    }

    // NOUL is normalized to the reserved true/false pair regardless of the
    // caller's wording, so every engine reads the same shape and p(true) is
    // unambiguous.
    {
        runanywhere::v1::DecisionRequest request;
        request.set_state("state");
        auto* noul = request.add_questions();
        noul->set_id("refund");
        noul->set_type(runanywhere::v1::DECISION_QUESTION_TYPE_NOUL);
        noul->set_instructions("Refund?");
        noul->add_options()->set_key("no: No refund");
        noul->add_options()->set_key("yes: Refund");
        const std::string bytes = request.SerializeAsString();
        rac_proto_buffer_t out = {};
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_decision_component_decide_proto(
            component, reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &out);
        check(rc == RAC_SUCCESS, "no/yes NOUL question is accepted");
        uint8_t* data = nullptr;
        size_t size = 0;
        rac_proto_buffer_take_data(&out, &data, &size);
        runanywhere::v1::DecisionResult result;
        result.ParseFromArray(data, static_cast<int>(size));
        check(result.answers_size() == 1 &&
                  result.answers(0).probabilities().count("true") == 1 &&
                  result.answers(0).probabilities().count("false") == 1,
              "NOUL options are normalized to true/false keys");
        std::free(data);
        rac_proto_buffer_free(&out);
    }

    rac_decision_component_destroy(component);

    // (5) Standalone request/result proto round-trip (no backend involved).
    {
        const std::string request_bytes = build_request("some state");
        runanywhere::v1::DecisionRequest parsed;
        check(parsed.ParseFromString(request_bytes) && parsed.state() == "some state" &&
                  parsed.questions_size() == 3 && parsed.questions(0).options_size() == 2,
              "DecisionRequest proto round-trips");

        runanywhere::v1::DecisionResult result;
        auto* answer = result.add_answers();
        answer->set_id("q1");
        answer->set_type(runanywhere::v1::DECISION_QUESTION_TYPE_CHOICE);
        answer->set_choice("a");
        (*answer->mutable_probabilities())["a"] = 0.6f;
        result.set_model_id("m");
        const std::string result_bytes = result.SerializeAsString();
        runanywhere::v1::DecisionResult reparsed;
        check(reparsed.ParseFromString(result_bytes) && reparsed.answers_size() == 1 &&
                  reparsed.answers(0).choice() == "a" &&
                  reparsed.answers(0).probabilities().at("a") == 0.6f,
              "DecisionResult proto round-trips");
    }

    rac_plugin_unregister("fake_decision");
    check(rac_plugin_find(RAC_PRIMITIVE_DECIDE) == nullptr,
          "decision route removed after unregister");

    if (g_failures == 0) {
        std::fprintf(stdout, "  ok: decision primitive wiring, routing, proto round-trip, "
                             "graceful failure\n");
        return 0;
    }
    std::fprintf(stderr, "test_decision: %d checks failed\n", g_failures);
    return 1;
}