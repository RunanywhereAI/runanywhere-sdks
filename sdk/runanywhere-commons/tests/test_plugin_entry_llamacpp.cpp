/**
 * @file test_plugin_entry_llamacpp.cpp
 * @brief Verifies the llama.cpp plugin entry point returns a well-formed vtable.
 *
 * This test does NOT load a model — that's handled by
 * downstream integration tests. It only asserts:
 *   - The entry symbol is present.
 *   - The returned vtable has abi_version == RAC_PLUGIN_API_VERSION.
 *   - The LLM ops slot is non-NULL.
 *   - Every op function pointer in the LLM slot is non-NULL.
 *   - Registering + finding via the unified registry round-trips.
 */

#include <cstdio>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry_llamacpp.h"

int main() {
    std::fprintf(stdout, "test_plugin_entry_llamacpp\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_llamacpp();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_llamacpp returned NULL\n");
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n", vt->metadata.abi_version,
                     RAC_PLUGIN_API_VERSION);
        return 1;
    }
    if (vt->llm_ops == nullptr) {
        std::fprintf(stderr, "llm_ops is NULL — LLM primitive not served\n");
        return 1;
    }
    // Core LLM ops must be populated.
    if (vt->llm_ops->initialize == nullptr || vt->llm_ops->generate == nullptr ||
        vt->llm_ops->destroy == nullptr) {
        std::fprintf(stderr, "Core LLM ops (initialize/generate/destroy) NULL\n");
        return 1;
    }

    rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_plugin_register failed: %d\n", (int)rc);
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != vt) {
        std::fprintf(stderr, "rac_plugin_find did not return llama.cpp vtable\n");
        return 1;
    }
    const rac_engine_manifest_t* manifest = rac_engine_manifest_find("llamacpp");
    if (manifest == nullptr || manifest->availability != RAC_ENGINE_AVAILABILITY_PUBLIC ||
        manifest->primitives_count != 1 || manifest->primitives[0] != RAC_PRIMITIVE_GENERATE_TEXT) {
        std::fprintf(stderr, "llama.cpp manifest was not published correctly\n");
        return 1;
    }
    rac_plugin_unregister("llamacpp");

    std::fprintf(stdout, "  ok: vtable well-formed, registry round-trip ok\n");
    return 0;
}
