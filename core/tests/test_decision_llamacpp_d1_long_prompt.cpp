#include <cstdio>
#include <cstdlib>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/features/decision/rac_decision_service.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry_llamacpp.h"

namespace {

rac_result_t decide(const rac_decision_service_ops_t* ops, void* impl, const std::string& state) {
    const rac_decision_option_t options[] = {{"yes", nullptr}, {"no", nullptr}};
    const rac_decision_question_t question = {"q", RAC_DECISION_QUESTION_NOUL,
                                              "Is the user asking about the weather?", options, 2};
    rac_decision_result_t result = {};
    const rac_result_t rc = ops->decide(impl, state.c_str(), &question, 1, nullptr, &result);
    if (rc == RAC_SUCCESS) {
        rac_decision_result_free(&result);
    }
    return rc;
}

}  // namespace

int main() {
    const char* model = std::getenv("RAC_TEST_D1_GGUF");
    if (model == nullptr || *model == '\0') {
        std::fprintf(stdout, "SKIP: RAC_TEST_D1_GGUF not set\n");
        return 0;
    }
    const rac_engine_vtable_t* vt = rac_plugin_entry_llamacpp();
    if (vt == nullptr || vt->decision_ops == nullptr) {
        std::fprintf(stdout, "SKIP: llama.cpp built without decision support\n");
        return 0;
    }
    const rac_decision_service_ops_t* ops = vt->decision_ops;
    void* impl = nullptr;
    if (ops->create("d1", nullptr, &impl) != RAC_SUCCESS ||
        ops->initialize(impl, model) != RAC_SUCCESS) {
        std::fprintf(stderr, "FAIL: could not load %s\n", model);
        return 1;
    }

    int failures = 0;
    const rac_result_t short_rc = decide(ops, impl, "What is the forecast for tomorrow?");
    if (short_rc != RAC_SUCCESS) {
        std::fprintf(stderr, "FAIL: short prompt returned %d\n", short_rc);
        ++failures;
    }

    std::string long_state;
    for (int i = 0; i < 400; ++i) {
        long_state += "The user keeps talking about their garden and the tomatoes. ";
    }
    const rac_result_t long_rc = decide(ops, impl, long_state);
    if (long_rc != RAC_ERROR_TEXT_TOO_LONG) {
        std::fprintf(stderr, "FAIL: long prompt returned %d, want RAC_ERROR_TEXT_TOO_LONG\n",
                     long_rc);
        ++failures;
    }

    ops->destroy(impl);
    std::fprintf(stdout, "%s\n", failures == 0 ? "PASS" : "FAILED");
    return failures == 0 ? 0 : 1;
}
