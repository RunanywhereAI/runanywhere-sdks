/** Focused host-only regression for the QHexRT disable_thinking input bridge. */

#include "qhexrt_session.h"

#include <cstdio>
#include <cstring>
#include <string>

#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"

extern "C" const rac_llm_service_ops_t g_qhexrt_llm_ops;

struct qhx_model {};
struct qhx_session {};

namespace {

std::string g_prompt;
int g_disable_thinking = -1;
int g_generate_calls = 0;

#define EXPECT_TRUE(condition)                                                                   \
    do {                                                                                         \
        if (!(condition)) {                                                                      \
            std::fprintf(stderr, "EXPECT FAILED: %s @ %s:%d\n", #condition, __FILE__, __LINE__); \
            return false;                                                                        \
        }                                                                                        \
    } while (0)

rac_bool_t keep_streaming(const char*, void*) { return RAC_TRUE; }

bool run_case(rac_bool_t disable_thinking, const char* prompt, bool streaming = false) {
    g_prompt.clear();
    g_disable_thinking = -1;
    g_generate_calls = 0;

    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    options.disable_thinking = disable_thinking;
    rac_llm_result_t result{};

    const rac_result_t rc = streaming
                                ? g_qhexrt_llm_ops.generate_stream(
                                      &session, prompt, &options, keep_streaming, nullptr)
                                : g_qhexrt_llm_ops.generate(&session, prompt, &options, &result);
    EXPECT_TRUE(rc == RAC_SUCCESS);
    EXPECT_TRUE(g_generate_calls == 1);
    EXPECT_TRUE(g_prompt == prompt);
    EXPECT_TRUE(g_disable_thinking == (disable_thinking != RAC_FALSE ? 1 : 0));
    if (!streaming) rac_llm_result_free(&result);
    return true;
}

}  // namespace

namespace qhexrt_engine {

Session* session_open(const char*) { return nullptr; }
void session_close(Session*) {}

}  // namespace qhexrt_engine

extern "C" {

void qhx_session_reset(qhx_session*) {}
void qhx_session_cancel(qhx_session*) {}

void qhx_gen_cfg_default(qhx_gen_cfg* cfg) {
    if (cfg != nullptr) std::memset(cfg, 0, sizeof(*cfg));
}

void qhx_generate_options_default(qhx_generate_options* options) {
    if (options == nullptr) return;
    std::memset(options, 0, sizeof(*options));
    options->struct_size = sizeof(*options);
}

qhx_status qhx_generate_ex(qhx_session*, const qhx_inputs* inputs, const qhx_gen_cfg*,
                           const qhx_generate_options* options,
                           qhx_token_cb callback, void* user, qhx_output* output) {
    ++g_generate_calls;
    g_prompt = inputs && inputs->text ? inputs->text : "";
    g_disable_thinking = options ? options->disable_thinking : -1;
    static const char kText[] = "ok";
    if (callback != nullptr) {
        (void)callback(user, kText, 2, 1, 0);
        (void)callback(user, nullptr, 0, -1, 1);
    }
    if (output != nullptr) {
        output->status = 0;
        output->text = kText;
        output->n_generated = 1;
        output->n_prompt = 1;
    }
    return 0;
}

qhx_status qhx_generate(qhx_session* session, const qhx_inputs* inputs, const qhx_gen_cfg* cfg,
                        qhx_token_cb callback, void* user, qhx_output* output) {
    return qhx_generate_ex(session, inputs, cfg, nullptr, callback, user, output);
}

const char* qhx_status_str(qhx_status) { return "fake"; }

}  // extern "C"

int main() {
    // Commons still prepends this soft directive for engines/models that use it. QHexRT receives the semantic
    // flag as well; its Qwen3.5-aware template removes the unsupported directive and emits the hard assistant
    // prefill inside the private runtime.
    if (!run_case(RAC_TRUE, "/no_think\nAnswer briefly")) return 1;
    if (!run_case(RAC_FALSE, "Answer normally")) return 1;
    if (!run_case(RAC_TRUE, "/no_think\nStream briefly", true)) return 1;
    std::puts("QHexRT LLM thinking bridge tests passed");
    return 0;
}
