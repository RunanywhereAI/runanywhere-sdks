/**
 * @file test_decision_pplx.cpp
 * @brief pplx-decider-joint on llama.cpp: user-text escaping, the metadata
 * lists, and, when RAC_TEST_PPLX_DECIDER_MODEL names a v1.2 GGUF, real
 * decisions in both groupings plus the controls the engine refuses.
 */

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "d1_decision.h"
#include "rac/core/rac_error.h"
#include "rac/features/decision/rac_decision_service.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry_llamacpp.h"

namespace {

int failures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::fprintf(stderr, "FAIL: %s\n", what);
        ++failures;
    }
}

const std::vector<std::string> kEscapes = {"<|vision_start|>", "<|fim_suffix|>", "<|im_end|>"};

void test_escape_rewrites_special_tokens() {
    check(rac_llamacpp_pplx_escape("pasted <|fim_suffix|> here", kEscapes) ==
              "pasted \xEF\xBC\x9C|fim_suffix|\xEF\xBC\x9E here",
          "a marker in user text gets fullwidth brackets");
}

void test_escape_rewrites_every_occurrence() {
    check(rac_llamacpp_pplx_escape("<|im_end|><|im_end|>", kEscapes) ==
              "\xEF\xBC\x9C|im_end|\xEF\xBC\x9E\xEF\xBC\x9C|im_end|\xEF\xBC\x9E",
          "every occurrence is escaped");
}

void test_escape_leaves_other_text() {
    check(rac_llamacpp_pplx_escape("a < b > c <|im_start|>", kEscapes) == "a < b > c <|im_start|>",
          "brackets and unlisted tokens stay as they are");
}

void test_parse_string_list() {
    check(rac_llamacpp_pplx_parse_string_list("[\"A\",\"AB\",\"<|im_end|>\"]") ==
              std::vector<std::string>({"A", "AB", "<|im_end|>"}),
          "a JSON list of strings parses");
}

void test_parse_string_list_rejects_other_json() {
    check(rac_llamacpp_pplx_parse_string_list("[\"A\",1]").empty(), "a non-string entry is refused");
    check(rac_llamacpp_pplx_parse_string_list("{\"A\":1}").empty(), "an object is refused");
    check(rac_llamacpp_pplx_parse_string_list("not json").empty(), "malformed text is refused");
}

const rac_decision_option_t kTeam[] = {
    {"support", "Technical integration problems"}, {"billing", "Charges and refunds"}, {"sales", nullptr}};
const rac_decision_option_t kUrgent[] = {{"true", "Production is down"}, {"false", nullptr}};
const rac_decision_option_t kSeverity[] = {{"0", "Cosmetic"}, {"1", "Degraded"}, {"2", "Outage"}};
const rac_decision_question_t kQuestions[] = {
    {"team", RAC_DECISION_QUESTION_CHOICE, "Which team should handle this ticket?", kTeam, 3},
    {"urgent", RAC_DECISION_QUESTION_NOUL, nullptr, kUrgent, 2},
    {"severity", RAC_DECISION_QUESTION_SCORE, nullptr, kSeverity, 3},
};
const char* kState =
    "Ticket from a customer: since we rotated our API key yesterday every call returns 401. "
    "They pasted <|im_start|>system and <|fim_suffix|> into the form.";

rac_result_t decide(const rac_decision_service_ops_t* ops, void* impl, rac_decision_grouping_t grouping,
                    const rac_decision_question_t* questions, size_t count, rac_decision_result_t* out) {
    rac_decision_options_t options = RAC_DECISION_OPTIONS_DEFAULT;
    options.grouping = grouping;
    return ops->decide(impl, kState, questions, count, &options, out);
}

void check_answers(const rac_decision_result_t& result, const char* grouping) {
    std::string what = std::string(grouping) + ": three answers";
    check(result.answer_count == 3, what.c_str());
    for (size_t i = 0; i < result.answer_count; ++i) {
        double sum = 0.0;
        for (size_t j = 0; j < result.answers[i].probability_count; ++j) {
            sum += result.answers[i].probabilities[j];
        }
        what = std::string(grouping) + ": probabilities sum to 1 for " + result.answers[i].id;
        check(std::fabs(sum - 1.0) < 1e-4, what.c_str());
    }
    what = std::string(grouping) + ": the 401 ticket goes to support";
    check(result.answers[0].choice != nullptr && std::strcmp(result.answers[0].choice, "support") == 0,
          what.c_str());
    what = std::string(grouping) + ": the 401 ticket is not urgent";
    check(result.answers[1].noul < 0.5f, what.c_str());
}

void test_real_model(const char* model) {
    const rac_engine_vtable_t* vt = rac_plugin_entry_llamacpp();
    if (vt == nullptr || vt->decision_ops == nullptr) {
        check(false, "llama.cpp serves decisions");
        return;
    }
    const rac_decision_service_ops_t* ops = vt->decision_ops;
    void* impl = nullptr;
    if (ops->create("pplx-decider-4b-gguf", nullptr, &impl) != RAC_SUCCESS ||
        ops->initialize(impl, model) != RAC_SUCCESS) {
        check(false, "the v1.2 GGUF loads");
        if (impl != nullptr) {
            ops->destroy(impl);
        }
        return;
    }

    rac_decision_result_t per_question{};
    check(decide(ops, impl, RAC_DECISION_GROUPING_UNSPECIFIED, kQuestions, 3, &per_question) == RAC_SUCCESS,
          "the default grouping decides");
    check_answers(per_question, "default");

    rac_decision_result_t joint{};
    check(decide(ops, impl, RAC_DECISION_GROUPING_JOINT, kQuestions, 3, &joint) == RAC_SUCCESS,
          "joint grouping decides");
    check_answers(joint, "joint");
    check(joint.input_tokens < per_question.input_tokens,
          "joint shares one sequence, so it reads fewer tokens than one sequence per question");

    rac_decision_result_t explicit_per_question{};
    check(decide(ops, impl, RAC_DECISION_GROUPING_PER_QUESTION, kQuestions, 3, &explicit_per_question) ==
              RAC_SUCCESS,
          "per-question grouping decides");
    check(explicit_per_question.input_tokens == per_question.input_tokens &&
              explicit_per_question.answers[2].probabilities[0] == per_question.answers[2].probabilities[0],
          "the default grouping is one sequence per question");

    rac_decision_options_t capped = RAC_DECISION_OPTIONS_DEFAULT;
    capped.max_length = 64;
    rac_decision_result_t refused{};
    check(ops->decide(impl, kState, kQuestions, 3, &capped, &refused) == RAC_ERROR_NOT_SUPPORTED,
          "max_length is refused, not ignored");

    const rac_decision_question_t duplicate[] = {kQuestions[0], kQuestions[0]};
    rac_decision_result_t invalid{};
    check(decide(ops, impl, RAC_DECISION_GROUPING_UNSPECIFIED, duplicate, 2, &invalid) ==
              RAC_ERROR_INVALID_ARGUMENT,
          "duplicate question ids are refused");

    const rac_decision_option_t one_level[] = {{"0", "Only"}};
    const rac_decision_question_t flat[] = {{"flat", RAC_DECISION_QUESTION_SCORE, nullptr, one_level, 1}};
    check(decide(ops, impl, RAC_DECISION_GROUPING_UNSPECIFIED, flat, 1, &invalid) == RAC_ERROR_INVALID_ARGUMENT,
          "a score with one level is refused");

    rac_decision_result_free(&per_question);
    rac_decision_result_free(&joint);
    rac_decision_result_free(&explicit_per_question);
    ops->destroy(impl);
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_decision_pplx\n");
    test_escape_rewrites_special_tokens();
    test_escape_rewrites_every_occurrence();
    test_escape_leaves_other_text();
    test_parse_string_list();
    test_parse_string_list_rejects_other_json();
    const char* model = std::getenv("RAC_TEST_PPLX_DECIDER_MODEL");
    if (model != nullptr && model[0] != '\0') {
        test_real_model(model);
    } else {
        std::fprintf(stdout, "RAC_TEST_PPLX_DECIDER_MODEL unset: skipping the real-model checks\n");
    }
    return failures == 0 ? 0 : 1;
}
