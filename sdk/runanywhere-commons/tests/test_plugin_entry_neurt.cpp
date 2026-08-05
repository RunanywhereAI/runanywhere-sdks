/**
 * @file test_plugin_entry_neurt.cpp
 * @brief Locks the `neurt` engine plugin-entry / vtable contract.
 *
 * Mirrors the other plugin-entry smoke tests. The neurt engine (named for the
 * runtime that implements it — NeuRT, the Apple half of the sibling `neurun`
 * repo) serves TWO modalities: it is the SOLE RAC_PRIMITIVE_DIFFUSION provider
 * — there is no fallback engine for image generation — and it is the only path
 * to RAC_PRIMITIVE_GENERATE_TEXT on the Apple Neural Engine. The existing
 * test_diffusion_coreml_generate.cpp exercises the diffusion backend
 * (rac_diffusion_coreml_create/initialize/generate) directly and never goes
 * through the plugin-entry/router path, so a manifest regression (dropping the
 * COREML runtime/format, losing an ops slot, or breaking capability_check)
 * would silently break generation across every SDK without failing any test.
 * This locks the vtable wiring.
 *
 * THE llm_ops ASSERTION IS THE POINT OF THIS FILE, not a detail. `g_neurt_llm_ops`
 * is defined on the NeuRT side; a `const` object at namespace scope has INTERNAL
 * linkage in C++ and `extern "C" { }` does not change that, so dropping the
 * explicit `extern` there makes the symbol vanish, the whole TU get discarded,
 * and `librac_neurt_llm_ops.a` build green at 520 bytes with zero symbols. A
 * static archive never resolves symbols, so nothing catches it until the first
 * executable or dylib link. This test link IS that first link, and the non-null
 * check below is what turns a silent "the ANE slot is empty" into a red test.
 *
 * Two build modes covered, discriminated by capability_check() exactly as the
 * plugin entry's own RAC_NEURT_ROUTABLE switch does:
 *   - Routable build (Apple + RAC_NEURT_GENERATE_AVAILABLE):
 *     capability_check() == RAC_SUCCESS. The manifest must advertise the
 *     RAC_RUNTIME_COREML and RAC_RUNTIME_ANE runtimes and the
 *     RAC_MODEL_FORMAT_ID_COREML format, BOTH the diffusion_ops and llm_ops
 *     slots must be populated, rac_plugin_register must accept it,
 *     plugin_find(RAC_PRIMITIVE_DIFFUSION) must return this vtable, and
 *     plugin_find_for_engine(GENERATE_TEXT, RAC_ENGINE_ID_NEURT) must pin to it
 *     — that pin is how an ANE model reaches this engine past higher-priority
 *     engines such as mlx (110 vs this engine's 100).
 *   - Stub build (non-Apple, or Apple without the generate component): the
 *     manifest advertises zero primitives/runtimes/formats, every ops slot is
 *     NULL, capability_check() refuses (CAPABILITY_UNSUPPORTED on non-Apple,
 *     BACKEND_UNAVAILABLE on Apple) and rac_plugin_register must reject it with
 *     RAC_ERROR_CAPABILITY_UNSUPPORTED so the router never routes to an inert
 *     engine.
 *
 * The disjoint-slot invariant is asserted in both modes: this engine serves
 * DIFFUSION and GENERATE_TEXT only, so stt/tts/vad/vlm/embedding stay NULL.
 */

#include <cstddef>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_ids.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_neurt.h"
#include "rac/plugin/rac_primitive.h"

namespace {

bool contains_runtime(const rac_runtime_id_t* runtimes, size_t count, rac_runtime_id_t needle) {
    if (runtimes == nullptr)
        return false;
    for (size_t i = 0; i < count; ++i) {
        if (runtimes[i] == needle)
            return true;
    }
    return false;
}

bool contains_format(const uint32_t* formats, size_t count, uint32_t needle) {
    if (formats == nullptr)
        return false;
    for (size_t i = 0; i < count; ++i) {
        if (formats[i] == needle)
            return true;
    }
    return false;
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_plugin_entry_neurt\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_neurt();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_neurt returned NULL\n");
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n", vt->metadata.abi_version,
                     RAC_PLUGIN_API_VERSION);
        return 1;
    }

    // Stable engine name is the dedup key the registry uses and the symbol the
    // dynamic loader derives — snake_case so a dlopen of
    // librunanywhere_neurt.{dylib,so} resolves cleanly. Named by the IMPLEMENTING
    // RUNTIME (`neurt`), not the modality and not Apple's framework.
    if (vt->metadata.name == nullptr || std::strcmp(vt->metadata.name, "neurt") != 0) {
        std::fprintf(stderr, "manifest name mismatch: got '%s'\n",
                     vt->metadata.name ? vt->metadata.name : "(null)");
        return 1;
    }
    // The engine-id table is what model_lifecycle pins against. If it drifts from
    // the manifest name, rac_plugin_find_for_engine() silently finds nothing and
    // every ANE model quietly routes to whichever engine wins on priority.
    if (std::strcmp(RAC_ENGINE_ID_NEURT, vt->metadata.name) != 0) {
        std::fprintf(stderr, "RAC_ENGINE_ID_NEURT ('%s') != manifest name ('%s')\n",
                     RAC_ENGINE_ID_NEURT, vt->metadata.name);
        return 1;
    }

    if (vt->capability_check == nullptr) {
        std::fprintf(stderr, "capability_check is NULL\n");
        return 1;
    }
    const rac_result_t cap = vt->capability_check();

    if (cap == RAC_SUCCESS) {
        // Routable build: the live ANE + image-generation path. Lock the full
        // routing contract the registry relies on.
        if (!contains_runtime(vt->metadata.runtimes, vt->metadata.runtimes_count,
                              RAC_RUNTIME_COREML)) {
            std::fprintf(stderr, "routable manifest missing RAC_RUNTIME_COREML\n");
            return 1;
        }
        if (!contains_runtime(vt->metadata.runtimes, vt->metadata.runtimes_count,
                              RAC_RUNTIME_ANE)) {
            std::fprintf(stderr, "routable manifest missing RAC_RUNTIME_ANE\n");
            return 1;
        }
        if (!contains_format(vt->metadata.formats, vt->metadata.formats_count,
                             RAC_MODEL_FORMAT_ID_COREML)) {
            std::fprintf(stderr, "routable manifest missing RAC_MODEL_FORMAT_ID_COREML\n");
            return 1;
        }
        if (vt->diffusion_ops == nullptr) {
            std::fprintf(stderr, "routable neurt engine has NULL diffusion_ops slot\n");
            return 1;
        }
        // See the file header: this is the linkage guard for g_neurt_llm_ops.
        if (vt->llm_ops == nullptr) {
            std::fprintf(stderr,
                         "routable neurt engine has NULL llm_ops slot — the NeuRT ANE op-table is "
                         "not linked in (check that g_neurt_llm_ops is declared `extern`)\n");
            return 1;
        }
        // Disjoint-slot invariant: DIFFUSION + GENERATE_TEXT only, today.
        if (vt->stt_ops != nullptr || vt->tts_ops != nullptr || vt->vad_ops != nullptr ||
            vt->vlm_ops != nullptr || vt->embedding_ops != nullptr) {
            std::fprintf(stderr, "neurt engine advertised an unserved ops slot\n");
            return 1;
        }

        const rac_result_t rc = rac_plugin_register(vt);
        if (rc != RAC_SUCCESS) {
            std::fprintf(stderr, "rac_plugin_register rejected routable neurt engine, got %d\n",
                         (int)rc);
            return 1;
        }
        if (rac_plugin_find(RAC_PRIMITIVE_DIFFUSION) != vt) {
            std::fprintf(stderr,
                         "plugin_find(RAC_PRIMITIVE_DIFFUSION) did not return neurt engine\n");
            rac_plugin_unregister(vt->metadata.name);
            return 1;
        }
        // The pin. Plain priority order would send an unpinned GENERATE_TEXT
        // request to mlx (110) over this engine (100) — by design. An ANE model
        // arrives here through the name pin instead, so that path is the one
        // worth locking.
        if (rac_plugin_find_for_engine(RAC_PRIMITIVE_GENERATE_TEXT, RAC_ENGINE_ID_NEURT) != vt) {
            std::fprintf(stderr,
                         "plugin_find_for_engine(GENERATE_TEXT, \"%s\") did not pin the neurt "
                         "engine\n",
                         RAC_ENGINE_ID_NEURT);
            rac_plugin_unregister(vt->metadata.name);
            return 1;
        }
        rac_plugin_unregister(vt->metadata.name);
        std::fprintf(stdout,
                     "  ok: routable neurt engine serves DIFFUSION + GENERATE_TEXT and pins\n");
        return 0;
    }

    // Stub build: the engine must advertise nothing routable and must be
    // rejected by the registry, so the router never sees it as routable.
    if (cap != RAC_ERROR_CAPABILITY_UNSUPPORTED && cap != RAC_ERROR_BACKEND_UNAVAILABLE) {
        std::fprintf(stderr,
                     "stub capability_check should refuse (CAPABILITY_UNSUPPORTED or "
                     "BACKEND_UNAVAILABLE), got %d\n",
                     (int)cap);
        return 1;
    }
    if (vt->metadata.runtimes_count != 0 || vt->metadata.formats_count != 0 ||
        vt->metadata.runtimes != nullptr || vt->metadata.formats != nullptr) {
        std::fprintf(stderr, "stub neurt engine advertised routing metadata\n");
        return 1;
    }
    if (vt->diffusion_ops != nullptr || vt->llm_ops != nullptr || vt->stt_ops != nullptr ||
        vt->tts_ops != nullptr || vt->vad_ops != nullptr || vt->vlm_ops != nullptr ||
        vt->embedding_ops != nullptr) {
        std::fprintf(stderr, "stub neurt engine advertised an ops slot\n");
        return 1;
    }
    const rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_ERROR_CAPABILITY_UNSUPPORTED) {
        std::fprintf(stderr, "rac_plugin_register should reject stub neurt engine, got %d\n",
                     (int)rc);
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_DIFFUSION) == vt) {
        std::fprintf(stderr, "stub neurt engine was inserted into the registry anyway\n");
        return 1;
    }
    std::fprintf(stdout, "  ok: stub neurt engine is not advertised or routable\n");
    return 0;
}
