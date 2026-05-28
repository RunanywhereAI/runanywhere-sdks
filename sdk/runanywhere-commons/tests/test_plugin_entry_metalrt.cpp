/**
 * @file test_plugin_entry_metalrt.cpp
 * @brief Verifies the MetalRT plugin entry point owns LLM / STT / TTS / VLM
 *        (the four primitives metalrt serves on Apple platforms).
 *
 * commons-009 (review RUN=20260527-122639-review): mirrors the parallel
 * test_plugin_entry_{llamacpp,onnx,genie,sherpa}.cpp smoke tests so any
 * future edit to rac_plugin_entry_metalrt.cpp (e.g. dropping a primitive,
 * flipping availability, missing ops-slot population) is caught at ctest
 * time rather than at first-inference time. MetalRT is the highest-priority
 * Apple engine (priority=120) and competes with llamacpp / sherpa for
 * routing slots — a silently-mis-declared vtable would let it win router
 * scoring and then fail at inference.
 *
 * Two build modes covered (same source, branches on the runtime
 * capability_check result which mirrors the manifest's compile-time gate):
 *   - Routable (__APPLE__ && RAC_METALRT_ENGINE_AVAILABLE):
 *     LLM/STT/TTS/VLM ops slots are non-NULL, VAD/embedding/rerank/diffusion
 *     slots are NULL, manifest publishes priority 120 + 4 primitives + Metal/
 *     ANE runtimes + CoreML/MLPackage/GGUF formats, availability is PRIVATE,
 *     and registry round-trip succeeds for GENERATE_TEXT / TRANSCRIBE /
 *     SYNTHESIZE / VLM.
 *   - SDK-unavailable (capability_check returns RAC_ERROR_BACKEND_UNAVAILABLE
 *     under !__APPLE__ or RAC_METALRT_ENGINE_AVAILABLE=0): all op slots are
 *     NULL, manifest declares zero primitives + priority 0 + zero runtimes/
 *     formats, availability is still PRIVATE (compile-time fact), and
 *     rac_plugin_register refuses to insert the engine into the registry.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_metalrt.h"
#include "rac/plugin/rac_primitive.h"

int main() {
    std::fprintf(stdout, "test_plugin_entry_metalrt\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_metalrt();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_metalrt returned NULL\n");
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n", vt->metadata.abi_version,
                     RAC_PLUGIN_API_VERSION);
        return 1;
    }

    // Stable engine name is the dedup key the registry uses; mis-naming would
    // cause router collisions with engines/llamacpp or engines/sherpa.
    if (vt->metadata.name == nullptr || std::strcmp(vt->metadata.name, "metalrt") != 0) {
        std::fprintf(stderr, "manifest name mismatch: got '%s'\n",
                     vt->metadata.name ? vt->metadata.name : "(null)");
        return 1;
    }

    if (vt->capability_check == nullptr) {
        std::fprintf(stderr, "capability_check is NULL\n");
        return 1;
    }

    const rac_result_t cap = vt->capability_check();
    if (cap == RAC_ERROR_BACKEND_UNAVAILABLE ||
        cap == RAC_ERROR_CAPABILITY_UNSUPPORTED) {
        // SDK-unavailable branch (non-Apple host OR Apple host without the
        // private libmetalrt_engine.a). Every ops slot must be NULL and the
        // manifest must publish zero routing surface. Registry insertion must
        // be refused.
        if (vt->llm_ops != nullptr || vt->stt_ops != nullptr || vt->tts_ops != nullptr ||
            vt->vad_ops != nullptr || vt->vlm_ops != nullptr || vt->embedding_ops != nullptr ||
            vt->rerank_ops != nullptr || vt->diffusion_ops != nullptr) {
            std::fprintf(stderr, "SDK-unavailable MetalRT advertised an ops slot\n");
            return 1;
        }
        if (vt->metadata.priority != 0 || vt->metadata.runtimes != nullptr ||
            vt->metadata.runtimes_count != 0 || vt->metadata.formats != nullptr ||
            vt->metadata.formats_count != 0) {
            std::fprintf(stderr, "SDK-unavailable MetalRT advertised routing metadata\n");
            return 1;
        }
        const rac_result_t rc = rac_plugin_register(vt);
        if (rc != RAC_ERROR_CAPABILITY_UNSUPPORTED && rc != RAC_ERROR_BACKEND_UNAVAILABLE) {
            std::fprintf(stderr,
                         "rac_plugin_register should reject SDK-unavailable MetalRT, got %d\n",
                         (int)rc);
            return 1;
        }
        if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == vt ||
            rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) == vt ||
            rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) == vt ||
            rac_plugin_find(RAC_PRIMITIVE_VLM) == vt) {
            std::fprintf(stderr, "SDK-unavailable MetalRT was inserted into the registry\n");
            return 1;
        }
        std::fprintf(stdout, "  ok: SDK-unavailable MetalRT is not advertised or routable\n");
        return 0;
    }
    if (cap != RAC_SUCCESS) {
        std::fprintf(stderr, "unexpected capability_check return: %d\n", (int)cap);
        return 1;
    }

    // Routable branch: LLM/STT/TTS/VLM ops are populated; VAD / embedding /
    // rerank / diffusion ops must remain NULL — those primitives live in
    // sibling engines (sherpa VAD, onnx embeddings, diffusion-coreml) and the
    // router relies on the disjoint-slot invariant to score routing candidates.
    if (vt->llm_ops == nullptr || vt->stt_ops == nullptr || vt->tts_ops == nullptr ||
        vt->vlm_ops == nullptr) {
        std::fprintf(stderr,
                     "multi-primitive ops slot is NULL "
                     "(llm=%p stt=%p tts=%p vlm=%p)\n",
                     (const void*)vt->llm_ops, (const void*)vt->stt_ops, (const void*)vt->tts_ops,
                     (const void*)vt->vlm_ops);
        return 1;
    }
    if (vt->vad_ops != nullptr || vt->embedding_ops != nullptr || vt->rerank_ops != nullptr ||
        vt->diffusion_ops != nullptr) {
        std::fprintf(stderr, "MetalRT advertised a non-served ops slot\n");
        return 1;
    }
    if (vt->metadata.priority != 120) {
        std::fprintf(stderr, "routable MetalRT priority != 120, got %d\n",
                     (int)vt->metadata.priority);
        return 1;
    }
    if (vt->metadata.runtimes == nullptr || vt->metadata.runtimes_count == 0 ||
        vt->metadata.formats == nullptr || vt->metadata.formats_count == 0) {
        std::fprintf(stderr, "routable MetalRT routing metadata is empty\n");
        return 1;
    }

    const rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_plugin_register failed: %d\n", (int)rc);
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != vt ||
        rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) != vt ||
        rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) != vt ||
        rac_plugin_find(RAC_PRIMITIVE_VLM) != vt) {
        std::fprintf(stderr,
                     "rac_plugin_find did not return MetalRT vtable for a served primitive\n");
        return 1;
    }
    // MetalRT does NOT serve VAD / embed / rerank / diffusion — must NOT win
    // those routing slots even when registered.
    if (rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE) == vt ||
        rac_plugin_find(RAC_PRIMITIVE_EMBED) == vt ||
        rac_plugin_find(RAC_PRIMITIVE_DIFFUSION) == vt) {
        std::fprintf(stderr, "MetalRT accidentally served a non-served primitive\n");
        return 1;
    }

    // Manifest holds package ownership + availability (kept outside the vtable
    // so adding new manifest fields does not bump the plugin ABI). MetalRT is
    // Apple-only / closed-source → PRIVATE availability in both build modes.
    const rac_engine_manifest_t* manifest = rac_engine_manifest_find("metalrt");
    if (manifest == nullptr || manifest->availability != RAC_ENGINE_AVAILABILITY_PRIVATE ||
        manifest->primitives_count != 4 || manifest->package_name == nullptr ||
        std::strcmp(manifest->package_name, "runanywhere_metalrt") != 0) {
        std::fprintf(stderr, "MetalRT manifest was not published correctly\n");
        return 1;
    }

    rac_plugin_unregister("metalrt");
    std::fprintf(stdout,
                 "  ok: multi-primitive ops populated, non-served slots null, "
                 "registry round-trip ok\n");
    return 0;
}
