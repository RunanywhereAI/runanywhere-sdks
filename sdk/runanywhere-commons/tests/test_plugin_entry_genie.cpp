#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

// genie now ships as the shared "compiled but not routable" shell emitted by
// RAC_ENGINE_UNAVAILABLE_PLUGIN (engines/common/rac_engine_unavailable.h): a
// not-routable manifest, an all-NULL-ops vtable whose only live field besides
// metadata is capability_check, and RAC_PLUGIN_ENTRY_DEF(genie). The former
// forwarding LLM ops (g_genie_llm_ops + genie_llm_*) and genie_backend_unavailable()
// were deleted, so this test no longer references them.
extern "C" {
const rac_engine_vtable_t* rac_plugin_entry_genie(void);
}

int main() {
    std::fprintf(stdout, "test_plugin_entry_genie\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_genie();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_genie returned NULL\n");
        return 1;
    }

    // Identity / ABI: the shell still carries valid, host-matching metadata so
    // the loader can inspect (and reject) it like any other plugin.
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n", vt->metadata.abi_version,
                     RAC_PLUGIN_API_VERSION);
        return 1;
    }
    if (vt->metadata.name == nullptr || std::strcmp(vt->metadata.name, "genie") != 0) {
        std::fprintf(stderr, "metadata.name is not \"genie\" (got %s)\n",
                     vt->metadata.name ? vt->metadata.name : "(null)");
        return 1;
    }

    // Not routable: the manifest advertises nothing the router can score on.
    if (vt->metadata.priority != 0 || vt->metadata.capability_flags != 0 ||
        vt->metadata.runtimes != nullptr || vt->metadata.runtimes_count != 0 ||
        vt->metadata.formats != nullptr || vt->metadata.formats_count != 0) {
        std::fprintf(stderr, "not-routable Genie advertised routing metadata\n");
        return 1;
    }

    // Every primitive op-table slot is NULL — the shell serves no primitive.
    if (vt->llm_ops != nullptr || vt->stt_ops != nullptr || vt->tts_ops != nullptr ||
        vt->vad_ops != nullptr || vt->embedding_ops != nullptr || vt->rerank_ops != nullptr ||
        vt->vlm_ops != nullptr || vt->diffusion_ops != nullptr) {
        std::fprintf(stderr, "not-routable Genie advertised primitive ops\n");
        return 1;
    }

    // capability_check is the only live op besides metadata, and it always
    // rejects in-tree (the engine never routes here). The exact non-success
    // code is host-specific: genie_capability_check() reports BACKEND_UNAVAILABLE
    // on Android (right platform, SDK-backed ops absent) and CAPABILITY_UNSUPPORTED
    // off-Android (wrong platform). Assert the precise code per host; both are
    // non-RAC_SUCCESS, so the engine is never selectable regardless of platform.
    if (vt->capability_check == nullptr) {
        std::fprintf(stderr, "not-routable Genie has no capability_check\n");
        return 1;
    }
    rac_result_t cap = vt->capability_check();
#if defined(__ANDROID__)
    const rac_result_t expected_cap = RAC_ERROR_BACKEND_UNAVAILABLE;
#else
    const rac_result_t expected_cap = RAC_ERROR_CAPABILITY_UNSUPPORTED;
#endif
    if (cap == RAC_SUCCESS || cap != expected_cap) {
        std::fprintf(stderr,
                     "Genie capability_check returned %d, expected non-success %d for this host\n",
                     (int)cap, (int)expected_cap);
        return 1;
    }

    // End-to-end: registration is rejected (the registry normalizes any
    // non-success capability_check result to CAPABILITY_UNSUPPORTED, so this
    // holds on every host), and Genie never lands in the LLM primitive table.
    rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_ERROR_CAPABILITY_UNSUPPORTED) {
        std::fprintf(stderr, "rac_plugin_register should reject not-routable Genie, got %d\n",
                     (int)rc);
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        std::fprintf(stderr, "not-routable Genie was inserted into the LLM registry\n");
        return 1;
    }

    std::fprintf(stdout, "  ok: not-routable Genie is not advertised or routable\n");
    return 0;
}
