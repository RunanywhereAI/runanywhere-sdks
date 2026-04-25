#include <iostream>
#include <new>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_cpu_runtime_provider.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        if (!(cond)) {                                                          \
            std::cerr << "FAIL: " << msg << " at " << __FILE__ << ":"          \
                      << __LINE__ << std::endl;                                 \
            return 1;                                                           \
        }                                                                       \
    } while (0)

namespace {

struct ProbeSession {
    int marker = 7;
};

int g_provider_create_calls = 0;
int g_provider_destroy_calls = 0;

rac_result_t probe_provider_create(const rac_runtime_session_desc_t* desc,
                                   rac_runtime_session_t** out) {
    if (desc == nullptr || out == nullptr) return RAC_ERROR_NULL_POINTER;
    *out = reinterpret_cast<rac_runtime_session_t*>(new (std::nothrow) ProbeSession());
    if (*out == nullptr) return RAC_ERROR_OUT_OF_MEMORY;
    ++g_provider_create_calls;
    return RAC_SUCCESS;
}

rac_result_t probe_provider_run(rac_runtime_session_t* session,
                                const rac_runtime_io_t*, size_t,
                                rac_runtime_io_t*, size_t) {
    return session == nullptr ? RAC_ERROR_NULL_POINTER : RAC_SUCCESS;
}

void probe_provider_destroy(rac_runtime_session_t* session) {
    delete reinterpret_cast<ProbeSession*>(session);
    ++g_provider_destroy_calls;
}

rac_result_t probe_engine_create(const char* model_id,
                                 const char*,
                                 void** out_impl) {
    if (model_id == nullptr || out_impl == nullptr) return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;
    const rac_runtime_vtable_t* runtime = rac_runtime_get_by_id(RAC_RUNTIME_CPU);
    if (runtime == nullptr || runtime->create_session == nullptr) {
        return RAC_ERROR_NOT_IMPLEMENTED;
    }
    rac_runtime_session_desc_t desc = {};
    desc.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
    desc.model_format = 1;
    desc.model_path = model_id;
    return runtime->create_session(&desc, reinterpret_cast<rac_runtime_session_t**>(out_impl));
}

void probe_engine_destroy(void* impl) {
    const rac_runtime_vtable_t* runtime = rac_runtime_get_by_id(RAC_RUNTIME_CPU);
    if (runtime && runtime->destroy_session) {
        runtime->destroy_session(reinterpret_cast<rac_runtime_session_t*>(impl));
    }
}

extern "C" const rac_llm_service_ops_t g_probe_llm_ops = {
    .initialize = nullptr,
    .generate = nullptr,
    .generate_stream = nullptr,
    .generate_stream_with_timing = nullptr,
    .get_info = nullptr,
    .cancel = nullptr,
    .cleanup = nullptr,
    .destroy = probe_engine_destroy,
    .load_lora = nullptr,
    .remove_lora = nullptr,
    .clear_lora = nullptr,
    .get_lora_info = nullptr,
    .inject_system_prompt = nullptr,
    .append_context = nullptr,
    .generate_from_context = nullptr,
    .clear_context = nullptr,
    .create = probe_engine_create,
};

const rac_runtime_id_t k_probe_runtimes[] = {RAC_RUNTIME_CPU};
const uint32_t k_probe_formats[] = {1};

const rac_engine_vtable_t k_probe_engine = {
    /* metadata */ {
        .abi_version = RAC_PLUGIN_API_VERSION,
        .name = "runtime_probe_engine",
        .display_name = "Runtime Probe Engine",
        .engine_version = "test",
        .priority = 999,
        .capability_flags = 0,
        .runtimes = k_probe_runtimes,
        .runtimes_count = 1,
        .formats = k_probe_formats,
        .formats_count = 1,
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,
    /* llm_ops          */ &g_probe_llm_ops,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

}  // namespace

int main() {
    rac_plugin_unregister("runtime_probe_engine");
    rac_cpu_runtime_unregister_provider("runtime_probe_provider");

    const uint32_t formats[] = {1};
    rac_cpu_runtime_provider_t provider = {};
    provider.name = "runtime_probe_provider";
    provider.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
    provider.formats = formats;
    provider.formats_count = 1;
    provider.create_session = probe_provider_create;
    provider.run_session = probe_provider_run;
    provider.destroy_session = probe_provider_destroy;
    CHECK(rac_cpu_runtime_register_provider(&provider) == RAC_SUCCESS,
          "register CPU probe provider");

    CHECK(rac_plugin_register(&k_probe_engine) == RAC_SUCCESS,
          "register probe engine");
    const rac_engine_vtable_t* selected = rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT);
    CHECK(selected == &k_probe_engine, "probe engine selected for LLM primitive");
    CHECK(selected->llm_ops != nullptr && selected->llm_ops->create != nullptr,
          "probe engine create op present");

    void* impl = nullptr;
    CHECK(selected->llm_ops->create("/tmp/probe.gguf", nullptr, &impl) == RAC_SUCCESS,
          "engine create dispatches through runtime");
    CHECK(impl != nullptr, "runtime session returned");
    CHECK(g_provider_create_calls == 1, "runtime provider create called exactly once");

    selected->llm_ops->destroy(impl);
    CHECK(g_provider_destroy_calls == 1, "runtime provider destroy called exactly once");

    rac_plugin_unregister("runtime_probe_engine");
    rac_cpu_runtime_unregister_provider("runtime_probe_provider");
    std::cout << "engine_uses_runtime_tests passed" << std::endl;
    return 0;
}
