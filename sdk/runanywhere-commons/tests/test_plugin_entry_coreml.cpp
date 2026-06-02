/**
 * @file test_plugin_entry_coreml.cpp
 * @brief Locks the `coreml` engine plugin-entry / vtable contract.
 *
 * Mirrors the parallel test_plugin_entry_{genie,metalrt}.cpp smoke tests. The
 * coreml engine (named by the FRAMEWORK, serving the DIFFUSION modality today)
 * is the SOLE RAC_PRIMITIVE_DIFFUSION provider — there is no fallback engine for
 * image generation — and the router fans plugin_find(RAC_PRIMITIVE_DIFFUSION)
 * out exactly to this entry. The existing test_diffusion_coreml_generate.cpp
 * exercises the backend (rac_diffusion_coreml_create/initialize/generate)
 * directly and never goes through the plugin-entry/router path, so a manifest
 * regression (dropping the COREML runtime/format, losing the diffusion_ops slot,
 * or breaking capability_check) would silently break image generation across
 * every SDK without failing any test. This locks the vtable wiring.
 *
 * Two build modes covered, discriminated by capability_check() exactly as the
 * plugin entry's own RAC_COREML_ROUTABLE switch does:
 *   - Routable build (Apple + RAC_COREML_GENERATE_AVAILABLE):
 *     capability_check() == RAC_SUCCESS. The manifest must advertise
 *     RAC_PRIMITIVE_DIFFUSION, the RAC_RUNTIME_COREML runtime and the
 *     RAC_MODEL_FORMAT_ID_COREML format, the diffusion_ops slot must be
 *     populated, rac_plugin_register must accept it, and
 *     plugin_find(RAC_PRIMITIVE_DIFFUSION) must return this vtable.
 *   - Stub build (non-Apple, or Apple without the generate component): the
 *     manifest advertises zero primitives/runtimes/formats, diffusion_ops is
 *     NULL, capability_check() refuses (CAPABILITY_UNSUPPORTED on non-Apple,
 *     BACKEND_UNAVAILABLE on Apple) and rac_plugin_register must reject it with
 *     RAC_ERROR_CAPABILITY_UNSUPPORTED so the router never routes DIFFUSION to
 *     an inert engine.
 *
 * The disjoint-slot invariant is asserted in both modes: the coreml engine
 * serves DIFFUSION only today, so every non-diffusion ops slot stays NULL.
 */

#include <cstddef>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_coreml.h"
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
    std::fprintf(stdout, "test_plugin_entry_coreml\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_coreml();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_coreml returned NULL\n");
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n", vt->metadata.abi_version,
                     RAC_PLUGIN_API_VERSION);
        return 1;
    }

    // Stable engine name is the dedup key the registry uses and the symbol the
    // dynamic loader derives — snake_case so a future dlopen of
    // librunanywhere_coreml.{dylib,so} resolves cleanly. Named by the FRAMEWORK
    // (`coreml`), not the modality, mirroring the `cloud` engine.
    if (vt->metadata.name == nullptr ||
        std::strcmp(vt->metadata.name, "coreml") != 0) {
        std::fprintf(stderr, "manifest name mismatch: got '%s'\n",
                     vt->metadata.name ? vt->metadata.name : "(null)");
        return 1;
    }

    if (vt->capability_check == nullptr) {
        std::fprintf(stderr, "capability_check is NULL\n");
        return 1;
    }
    const rac_result_t cap = vt->capability_check();

    if (cap == RAC_SUCCESS) {
        // Routable build: this is the live image-generation path. Lock the full
        // routing contract the EngineRouter relies on to select coreml engine
        // for RAC_PRIMITIVE_DIFFUSION. Primitive routability is expressed via the
        // vtable's diffusion_ops slot (verified below) — rac_engine_metadata no
        // longer carries a primitives[] array.
        if (!contains_runtime(vt->metadata.runtimes, vt->metadata.runtimes_count,
                              RAC_RUNTIME_COREML)) {
            std::fprintf(stderr, "routable manifest missing RAC_RUNTIME_COREML\n");
            return 1;
        }
        if (!contains_format(vt->metadata.formats, vt->metadata.formats_count,
                             RAC_MODEL_FORMAT_ID_COREML)) {
            std::fprintf(stderr, "routable manifest missing RAC_MODEL_FORMAT_ID_COREML\n");
            return 1;
        }
        if (vt->diffusion_ops == nullptr) {
            std::fprintf(stderr, "routable coreml engine has NULL diffusion_ops slot\n");
            return 1;
        }
        // Disjoint-slot invariant: coreml engine is a DIFFUSION-only engine.
        if (vt->llm_ops != nullptr || vt->stt_ops != nullptr || vt->tts_ops != nullptr ||
            vt->vad_ops != nullptr || vt->vlm_ops != nullptr || vt->embedding_ops != nullptr ||
            vt->rerank_ops != nullptr) {
            std::fprintf(stderr, "coreml engine advertised a non-DIFFUSION ops slot\n");
            return 1;
        }

        const rac_result_t rc = rac_plugin_register(vt);
        if (rc != RAC_SUCCESS) {
            std::fprintf(stderr, "rac_plugin_register rejected routable coreml engine, got %d\n",
                         (int)rc);
            return 1;
        }
        if (rac_plugin_find(RAC_PRIMITIVE_DIFFUSION) != vt) {
            std::fprintf(stderr,
                         "plugin_find(RAC_PRIMITIVE_DIFFUSION) did not return coreml engine\n");
            rac_plugin_unregister(vt->metadata.name);
            return 1;
        }
        rac_plugin_unregister(vt->metadata.name);
        std::fprintf(stdout,
                     "  ok: routable coreml engine advertises DIFFUSION+CoreML and routes\n");
        return 0;
    }

    // Stub build: the engine must advertise nothing routable and must be
    // rejected by the registry, so the router never sees DIFFUSION as routable.
    if (cap != RAC_ERROR_CAPABILITY_UNSUPPORTED && cap != RAC_ERROR_BACKEND_UNAVAILABLE) {
        std::fprintf(stderr,
                     "stub capability_check should refuse (CAPABILITY_UNSUPPORTED or "
                     "BACKEND_UNAVAILABLE), got %d\n",
                     (int)cap);
        return 1;
    }
    if (vt->metadata.runtimes_count != 0 || vt->metadata.formats_count != 0 ||
        vt->metadata.runtimes != nullptr || vt->metadata.formats != nullptr) {
        std::fprintf(stderr, "stub coreml engine advertised routing metadata\n");
        return 1;
    }
    if (vt->diffusion_ops != nullptr || vt->llm_ops != nullptr || vt->stt_ops != nullptr ||
        vt->tts_ops != nullptr || vt->vad_ops != nullptr || vt->vlm_ops != nullptr ||
        vt->embedding_ops != nullptr || vt->rerank_ops != nullptr) {
        std::fprintf(stderr, "stub coreml engine advertised an ops slot\n");
        return 1;
    }
    const rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_ERROR_CAPABILITY_UNSUPPORTED) {
        std::fprintf(stderr, "rac_plugin_register should reject stub coreml engine, got %d\n",
                     (int)rc);
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_DIFFUSION) == vt) {
        std::fprintf(stderr, "stub coreml engine was inserted into the registry anyway\n");
        return 1;
    }
    std::fprintf(stdout, "  ok: stub coreml engine is not advertised or routable\n");
    return 0;
}
