#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

extern "C" {
const rac_engine_vtable_t* rac_plugin_entry_genie(void);
const char* genie_backend_build_info(void);
rac_result_t genie_backend_unavailable(void);
extern const rac_llm_service_ops_t g_genie_llm_ops;
}

int main() {
    std::fprintf(stdout, "test_plugin_entry_genie\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_genie();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_genie returned NULL\n");
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n",
                     vt->metadata.abi_version, RAC_PLUGIN_API_VERSION);
        return 1;
    }

    const char* build_info = genie_backend_build_info();
    if (std::strcmp(build_info, "genie:sdk-unavailable") != 0) {
        std::fprintf(stdout,
                     "  skip: Genie SDK is available in this build (%s)\n",
                     build_info);
        return 0;
    }

    if (vt->metadata.priority != 0 ||
        vt->metadata.capability_flags != 0 ||
        vt->metadata.runtimes != nullptr ||
        vt->metadata.runtimes_count != 0 ||
        vt->metadata.formats != nullptr ||
        vt->metadata.formats_count != 0) {
        std::fprintf(stderr,
                     "SDK-unavailable Genie advertised routing metadata\n");
        return 1;
    }
    if (vt->llm_ops != nullptr) {
        std::fprintf(stderr, "SDK-unavailable Genie advertised LLM ops\n");
        return 1;
    }
    if (vt->capability_check == nullptr ||
        vt->capability_check() != RAC_ERROR_BACKEND_UNAVAILABLE) {
        std::fprintf(stderr,
                     "SDK-unavailable Genie capability_check did not return BACKEND_UNAVAILABLE\n");
        return 1;
    }
    if (genie_backend_unavailable() != RAC_ERROR_BACKEND_UNAVAILABLE) {
        std::fprintf(stderr,
                     "genie_backend_unavailable did not return BACKEND_UNAVAILABLE\n");
        return 1;
    }

    void* impl = reinterpret_cast<void*>(0x1);
    if (g_genie_llm_ops.create("genie-test", "{}", &impl) !=
            RAC_ERROR_BACKEND_UNAVAILABLE ||
        impl != nullptr ||
        g_genie_llm_ops.initialize(nullptr, nullptr) !=
            RAC_ERROR_BACKEND_UNAVAILABLE ||
        g_genie_llm_ops.generate(nullptr, nullptr, nullptr, nullptr) !=
            RAC_ERROR_BACKEND_UNAVAILABLE ||
        g_genie_llm_ops.generate_stream(nullptr, nullptr, nullptr, nullptr,
                                        nullptr) !=
            RAC_ERROR_BACKEND_UNAVAILABLE ||
        g_genie_llm_ops.get_info(nullptr, nullptr) !=
            RAC_ERROR_BACKEND_UNAVAILABLE ||
        g_genie_llm_ops.cancel(nullptr) !=
            RAC_ERROR_BACKEND_UNAVAILABLE) {
        std::fprintf(stderr,
                     "SDK-unavailable Genie LLM stubs did not return BACKEND_UNAVAILABLE\n");
        return 1;
    }
    if (g_genie_llm_ops.cleanup(nullptr) != RAC_SUCCESS) {
        std::fprintf(stderr, "SDK-unavailable Genie cleanup should be a no-op success\n");
        return 1;
    }

    rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_ERROR_CAPABILITY_UNSUPPORTED) {
        std::fprintf(stderr,
                     "rac_plugin_register should reject SDK-unavailable Genie, got %d\n",
                     (int)rc);
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        std::fprintf(stderr,
                     "SDK-unavailable Genie was inserted into the LLM registry\n");
        return 1;
    }

    std::fprintf(stdout,
                 "  ok: SDK-unavailable Genie is not advertised or routable\n");
    return 0;
}
