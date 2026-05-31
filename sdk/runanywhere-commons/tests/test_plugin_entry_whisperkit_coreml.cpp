/**
 * @file test_plugin_entry_whisperkit_coreml.cpp
 * @brief Locks the WhisperKit CoreML plugin-entry manifest contract.
 *
 * Mirrors the parallel
 * test_plugin_entry_{llamacpp,onnx,genie,sherpa}.cpp smoke tests so any future
 * edit to rac_plugin_entry_whisperkit_coreml.cpp (dropping a runtime, flipping
 * availability, losing the STT ops slot) is caught at ctest time rather than at
 * runtime in an iOS voice-agent example app.
 *
 * Specific contract this asserts (the one test_engine_capability_honesty.cpp's
 * ANEHintSelectsWhisperKit case relies on):
 *   - manifest.runtimes contains RAC_RUNTIME_ANE and RAC_RUNTIME_COREML so the
 *     router can pick whisperkit_coreml over sherpa / whispercpp when the
 *     caller pins preferred_runtime=ANE.
 *   - manifest publishes RAC_PRIMITIVE_TRANSCRIBE, availability=PRIVATE,
 *     priority=110, package owner/name (declarative metadata block).
 *   - vtable populates stt_ops only; llm/tts/vad/vlm/embedding/diffusion slots
 *     stay NULL (disjoint-slot routing invariant).
 *
 * Two host modes covered:
 *   - Apple host: capability_check returns RAC_SUCCESS only when Swift-side
 *     WhisperKit callbacks are installed; in a unit-test process they are not,
 *     so capability_check returns RAC_ERROR_BACKEND_UNAVAILABLE and
 *     rac_plugin_register must refuse to insert. Manifest fields are
 *     unconditional and asserted regardless.
 *   - Non-Apple host: capability_check returns RAC_ERROR_CAPABILITY_UNSUPPORTED;
 *     test prints a skip notice and exits 0. The CMake wiring already gates
 *     the test on APPLE so this branch is defensive.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_whisperkit_coreml.h"
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

}  // namespace

int main() {
    std::fprintf(stdout, "test_plugin_entry_whisperkit_coreml\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_whisperkit_coreml();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_whisperkit_coreml returned NULL\n");
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n", vt->metadata.abi_version,
                     RAC_PLUGIN_API_VERSION);
        return 1;
    }

    // Stable engine name is the dedup key the registry uses; mis-naming would
    // collide with engines/sherpa or engines/whispercpp under ANE-preferred
    // routing.
    if (vt->metadata.name == nullptr ||
        std::strcmp(vt->metadata.name, "whisperkit_coreml") != 0) {
        std::fprintf(stderr, "manifest name mismatch: got '%s'\n",
                     vt->metadata.name ? vt->metadata.name : "(null)");
        return 1;
    }

    // Manifest is published unconditionally (no compile-time conditional like
    // genie) so the routing fields land on vt->metadata via the
    // RAC_ENGINE_METADATA_FROM_MANIFEST copy. This is the contract
    // test_engine_capability_honesty.cpp's ANE tiebreak depends on. We assert
    // it directly off the vtable so the check works even when the engine
    // declines registration (no callbacks installed in this unit-test process,
    // so rac_engine_manifest_find by name would return nullptr).
    if (!contains_runtime(vt->metadata.runtimes, vt->metadata.runtimes_count, RAC_RUNTIME_ANE)) {
        std::fprintf(stderr,
                     "vt->metadata.runtimes missing RAC_RUNTIME_ANE (ANE routing tiebreak)\n");
        return 1;
    }
    if (!contains_runtime(vt->metadata.runtimes, vt->metadata.runtimes_count, RAC_RUNTIME_COREML)) {
        std::fprintf(stderr, "vt->metadata.runtimes missing RAC_RUNTIME_COREML\n");
        return 1;
    }
    if (vt->metadata.priority != 110) {
        std::fprintf(stderr, "vt->metadata.priority != 110, got %d\n",
                     (int)vt->metadata.priority);
        return 1;
    }

    // Disjoint-slot invariant: WhisperKit CoreML is an STT-only engine.
    // Populating any non-STT slot would let the router pick it for unrelated
    // primitives (e.g. SYNTHESIZE) and break the capability-honesty contract.
    if (vt->stt_ops == nullptr) {
        std::fprintf(stderr, "stt_ops slot is NULL\n");
        return 1;
    }
    if (vt->llm_ops != nullptr || vt->tts_ops != nullptr || vt->vad_ops != nullptr ||
        vt->vlm_ops != nullptr || vt->embedding_ops != nullptr || vt->rerank_ops != nullptr ||
        vt->diffusion_ops != nullptr) {
        std::fprintf(stderr, "WhisperKit CoreML advertised a non-STT ops slot\n");
        return 1;
    }

    if (vt->capability_check == nullptr) {
        std::fprintf(stderr, "capability_check is NULL\n");
        return 1;
    }

    const rac_result_t cap = vt->capability_check();
#if defined(__APPLE__)
    // On Apple, Swift-side WhisperKit callbacks are not installed in this unit
    // test process, so rac_whisperkit_coreml_stt_is_available() returns FALSE
    // and capability_check must return BACKEND_UNAVAILABLE (or
    // CAPABILITY_UNSUPPORTED if the host has no Core ML runtime — e.g. a
    // tvOS/visionOS lane that intentionally strips it). Both refusals must
    // be honored by rac_plugin_register.
    if (cap != RAC_ERROR_BACKEND_UNAVAILABLE && cap != RAC_ERROR_CAPABILITY_UNSUPPORTED) {
        std::fprintf(
            stderr,
            "Apple capability_check should refuse without Swift callbacks (got %d)\n",
            (int)cap);
        return 1;
    }
    const rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_ERROR_CAPABILITY_UNSUPPORTED) {
        std::fprintf(
            stderr,
            "rac_plugin_register should reject WhisperKit without callbacks, got %d\n",
            (int)rc);
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) == vt) {
        std::fprintf(stderr,
                     "WhisperKit without callbacks was inserted into the registry anyway\n");
        return 1;
    }
    std::fprintf(stdout,
                 "  ok: manifest publishes ANE+CoreML+TRANSCRIBE; registry rejects "
                 "callback-less WhisperKit\n");
    return 0;
#else
    // Non-Apple host: plugin must decline registration outright. The CMake
    // wiring already gates this test on APPLE so this is defensive cover
    // for accidental host changes.
    if (cap != RAC_ERROR_CAPABILITY_UNSUPPORTED) {
        std::fprintf(stderr, "non-Apple capability_check should be CAPABILITY_UNSUPPORTED (got %d)\n",
                     (int)cap);
        return 1;
    }
    std::fprintf(stdout, "  skip: non-Apple host, WhisperKit CoreML correctly unsupported\n");
    return 0;
#endif
}
