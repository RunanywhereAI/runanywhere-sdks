/**
 * @file test_plugin_entry_sherpa.cpp
 * @brief Verifies the Sherpa-ONNX plugin entry point owns STT / TTS / VAD only.
 *
 * commons-010 (review RUN=20260527-122639-review): mirrors the parallel
 * test_plugin_entry_{llamacpp,onnx,genie}.cpp smoke tests so any future edit
 * to rac_plugin_entry_sherpa.cpp (e.g. dropping a primitive, flipping
 * availability, missing ops-slot population) is caught at ctest time rather
 * than at runtime in an iOS/Android voice-agent example app.
 *
 * Two build modes covered (same source, branches on the runtime
 * capability_check result which mirrors the manifest's compile-time gate):
 *   - Routable (SHERPA_ONNX_AVAILABLE && RAC_SHERPA_SPEECH_OPS_AVAILABLE):
 *     STT/TTS/VAD ops slots are non-NULL, llm/vlm/diffusion slots are NULL,
 *     manifest publishes priority 90 + 3 primitives, and registry round-trip
 *     succeeds for TRANSCRIBE / SYNTHESIZE / DETECT_VOICE.
 *   - SDK-unavailable (capability_check returns RAC_ERROR_BACKEND_UNAVAILABLE):
 *     all op slots are NULL, manifest declares zero primitives + priority 0,
 *     and rac_plugin_register refuses to insert the engine into the registry.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_sherpa.h"
#include "rac/plugin/rac_primitive.h"

int main() {
    std::fprintf(stdout, "test_plugin_entry_sherpa\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_sherpa();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_sherpa returned NULL\n");
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n", vt->metadata.abi_version,
                     RAC_PLUGIN_API_VERSION);
        return 1;
    }

    // Stable engine name is the dedup key the registry uses; mis-naming would
    // cause router collisions with engines/onnx (CPP-04).
    if (vt->metadata.name == nullptr || std::strcmp(vt->metadata.name, "sherpa") != 0) {
        std::fprintf(stderr, "manifest name mismatch: got '%s'\n",
                     vt->metadata.name ? vt->metadata.name : "(null)");
        return 1;
    }

    if (vt->capability_check == nullptr) {
        std::fprintf(stderr, "capability_check is NULL\n");
        return 1;
    }

    const rac_result_t cap = vt->capability_check();
    if (cap == RAC_ERROR_BACKEND_UNAVAILABLE) {
        // SDK-unavailable branch: every ops slot must be NULL and the manifest
        // must publish zero routing surface. Registry insertion must be refused.
        if (vt->llm_ops != nullptr || vt->stt_ops != nullptr || vt->tts_ops != nullptr ||
            vt->vad_ops != nullptr || vt->vlm_ops != nullptr || vt->embedding_ops != nullptr ||
            vt->rerank_ops != nullptr || vt->diffusion_ops != nullptr) {
            std::fprintf(stderr, "SDK-unavailable Sherpa advertised an ops slot\n");
            return 1;
        }
        if (vt->metadata.priority != 0 || vt->metadata.runtimes != nullptr ||
            vt->metadata.runtimes_count != 0 || vt->metadata.formats != nullptr ||
            vt->metadata.formats_count != 0) {
            std::fprintf(stderr, "SDK-unavailable Sherpa advertised routing metadata\n");
            return 1;
        }
        const rac_result_t rc = rac_plugin_register(vt);
        if (rc != RAC_ERROR_CAPABILITY_UNSUPPORTED) {
            std::fprintf(stderr,
                         "rac_plugin_register should reject SDK-unavailable Sherpa, got %d\n",
                         (int)rc);
            return 1;
        }
        if (rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) != nullptr ||
            rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) != nullptr ||
            rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE) != nullptr) {
            std::fprintf(stderr, "SDK-unavailable Sherpa was inserted into the registry\n");
            return 1;
        }
        std::fprintf(stdout, "  ok: SDK-unavailable Sherpa is not advertised or routable\n");
        return 0;
    }
    if (cap != RAC_SUCCESS) {
        std::fprintf(stderr, "unexpected capability_check return: %d\n", (int)cap);
        return 1;
    }

    // Routable branch: speech ops are populated; LLM / VLM / embedding /
    // diffusion ops must remain NULL — those primitives live in sibling
    // engines (llamacpp / onnx / metalrt) and the router relies on the
    // disjoint-slot invariant to score routing candidates.
    if (vt->stt_ops == nullptr || vt->tts_ops == nullptr || vt->vad_ops == nullptr) {
        std::fprintf(stderr, "speech ops slot is NULL (stt=%p tts=%p vad=%p)\n",
                     (const void*)vt->stt_ops, (const void*)vt->tts_ops, (const void*)vt->vad_ops);
        return 1;
    }
    if (vt->llm_ops != nullptr || vt->vlm_ops != nullptr || vt->embedding_ops != nullptr ||
        vt->diffusion_ops != nullptr || vt->rerank_ops != nullptr) {
        std::fprintf(stderr, "Sherpa advertised a non-speech ops slot\n");
        return 1;
    }
    if (vt->metadata.priority != 90) {
        std::fprintf(stderr, "routable Sherpa priority != 90, got %d\n",
                     (int)vt->metadata.priority);
        return 1;
    }
    if (vt->metadata.runtimes == nullptr || vt->metadata.runtimes_count == 0 ||
        vt->metadata.formats == nullptr || vt->metadata.formats_count == 0) {
        std::fprintf(stderr, "routable Sherpa routing metadata is empty\n");
        return 1;
    }

    const rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_plugin_register failed: %d\n", (int)rc);
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) != vt ||
        rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) != vt ||
        rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE) != vt) {
        std::fprintf(stderr,
                     "rac_plugin_find did not return Sherpa vtable for a speech primitive\n");
        return 1;
    }
    // Speech-only engine: must NOT be routable for non-speech primitives.
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == vt) {
        std::fprintf(stderr, "Sherpa accidentally served GENERATE_TEXT\n");
        return 1;
    }

    // Manifest holds package ownership + availability (kept outside the vtable
    // so adding new manifest fields does not bump the plugin ABI).
    const rac_engine_manifest_t* manifest = rac_engine_manifest_find("sherpa");
    if (manifest == nullptr || manifest->availability != RAC_ENGINE_AVAILABILITY_PUBLIC ||
        manifest->primitives_count != 3 || manifest->package_name == nullptr ||
        std::strcmp(manifest->package_name, "runanywhere_sherpa") != 0) {
        std::fprintf(stderr, "Sherpa manifest was not published correctly\n");
        return 1;
    }

    rac_plugin_unregister("sherpa");
    std::fprintf(stdout,
                 "  ok: speech ops populated, non-speech slots null, registry round-trip ok\n");
    return 0;
}
