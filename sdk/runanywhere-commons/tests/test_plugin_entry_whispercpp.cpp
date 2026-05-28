/**
 * @file test_plugin_entry_whispercpp.cpp
 * @brief Verifies the whisper.cpp plugin entry point owns STT only.
 *
 * commons-012 (review RUN=20260527-122639-review): mirrors the parallel
 * test_plugin_entry_{llamacpp,onnx,genie,sherpa}.cpp smoke tests so any future
 * edit to rac_plugin_entry_whispercpp.cpp (e.g. dropping a primitive, flipping
 * availability, bumping the priority above sherpa's 90, or missing ops-slot
 * population) is caught at ctest time rather than at runtime in an
 * iOS/Android voice-agent example app.
 *
 * whisper.cpp is a routable second STT engine that competes with sherpa for
 * RAC_PRIMITIVE_TRANSCRIBE routing. The router scores candidates by
 * `manifest->priority`, so the priority literal (80) is load-bearing — a
 * silent bump to >= 90 would flip every transcription request from sherpa to
 * whispercpp across all five SDKs. This test asserts:
 *   - abi_version + name dedup key (router invariant CPP-04).
 *   - STT ops slot is populated; llm/tts/vad/vlm/embedding/diffusion/rerank
 *     slots are NULL (disjoint-slot invariant the router scoring relies on).
 *   - Manifest priority == 80 (must stay below sherpa's 90).
 *   - Manifest primitives == {TRANSCRIBE} only.
 *   - Manifest availability == PUBLIC, package_name == "runanywhere_whispercpp".
 *   - Registry round-trip via rac_plugin_register / rac_plugin_find /
 *     rac_engine_manifest_find succeeds and TRANSCRIBE resolves to this vtable
 *     (when sherpa is not also registered concurrently).
 *
 * Unlike sherpa, whispercpp's capability_check unconditionally returns
 * RAC_SUCCESS — the engine has no runtime gate beyond build-time linkage, so
 * there is no SDK-unavailable branch to exercise.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_whispercpp.h"
#include "rac/plugin/rac_primitive.h"

int main() {
    std::fprintf(stdout, "test_plugin_entry_whispercpp\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_whispercpp();
    if (vt == nullptr) {
        std::fprintf(stderr, "rac_plugin_entry_whispercpp returned NULL\n");
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: plugin=%u host=%u\n", vt->metadata.abi_version,
                     RAC_PLUGIN_API_VERSION);
        return 1;
    }

    // Stable engine name is the dedup key the registry uses; mis-naming would
    // cause router collisions with engines/sherpa (CPP-04).
    if (vt->metadata.name == nullptr || std::strcmp(vt->metadata.name, "whispercpp") != 0) {
        std::fprintf(stderr, "manifest name mismatch: got '%s'\n",
                     vt->metadata.name ? vt->metadata.name : "(null)");
        return 1;
    }

    if (vt->capability_check == nullptr) {
        std::fprintf(stderr, "capability_check is NULL\n");
        return 1;
    }
    // whispercpp has no runtime gate — capability_check must succeed whenever
    // the plugin binary is loaded.
    const rac_result_t cap = vt->capability_check();
    if (cap != RAC_SUCCESS) {
        std::fprintf(stderr, "whispercpp capability_check returned %d (expected RAC_SUCCESS)\n",
                     (int)cap);
        return 1;
    }

    // STT-only engine: stt_ops populated; every other primitive ops slot must
    // remain NULL — those primitives live in sibling engines (llamacpp / onnx /
    // sherpa / metalrt) and the router relies on the disjoint-slot invariant
    // to score routing candidates.
    if (vt->stt_ops == nullptr) {
        std::fprintf(stderr, "stt_ops is NULL — STT primitive not served\n");
        return 1;
    }
    if (vt->llm_ops != nullptr || vt->tts_ops != nullptr || vt->vad_ops != nullptr ||
        vt->vlm_ops != nullptr || vt->embedding_ops != nullptr || vt->rerank_ops != nullptr ||
        vt->diffusion_ops != nullptr) {
        std::fprintf(stderr, "whispercpp advertised a non-STT ops slot\n");
        return 1;
    }

    // Priority 80 is load-bearing: it MUST stay below sherpa's 90 so the router
    // picks sherpa as the default STT engine. Any bump to >= 90 silently flips
    // every transcription request across all SDKs to whispercpp.
    if (vt->metadata.priority != 80) {
        std::fprintf(stderr, "whispercpp priority != 80 (must stay below sherpa's 90), got %d\n",
                     (int)vt->metadata.priority);
        return 1;
    }
    if (vt->metadata.runtimes == nullptr || vt->metadata.runtimes_count == 0 ||
        vt->metadata.formats == nullptr || vt->metadata.formats_count == 0) {
        std::fprintf(stderr, "whispercpp routing metadata is empty\n");
        return 1;
    }

    const rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_plugin_register failed: %d\n", (int)rc);
        return 1;
    }
    // Whispercpp must own TRANSCRIBE in an isolated test process where sherpa
    // is not concurrently registered. Non-STT primitives must remain off
    // whispercpp.
    if (rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) != vt) {
        std::fprintf(stderr, "rac_plugin_find did not return whispercpp vtable for TRANSCRIBE\n");
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == vt ||
        rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) == vt ||
        rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE) == vt ||
        rac_plugin_find(RAC_PRIMITIVE_EMBED) == vt) {
        std::fprintf(stderr, "whispercpp accidentally served a non-STT primitive\n");
        return 1;
    }

    const rac_engine_manifest_t* manifest = rac_engine_manifest_find("whispercpp");
    if (manifest == nullptr || manifest->availability != RAC_ENGINE_AVAILABILITY_PUBLIC ||
        manifest->primitives_count != 1 || manifest->primitives[0] != RAC_PRIMITIVE_TRANSCRIBE ||
        manifest->priority != 80 || manifest->package_name == nullptr ||
        std::strcmp(manifest->package_name, "runanywhere_whispercpp") != 0) {
        std::fprintf(stderr, "whispercpp manifest was not published correctly\n");
        return 1;
    }

    // GGML/GGUF are the load-bearing whisper.cpp model formats — assert both
    // are still declared so the loader can resolve a Whisper-family model.
    bool saw_ggml = false;
    bool saw_gguf = false;
    for (size_t i = 0; i < manifest->formats_count; ++i) {
        if (manifest->formats[i] == RAC_MODEL_FORMAT_ID_GGML) {
            saw_ggml = true;
        }
        if (manifest->formats[i] == RAC_MODEL_FORMAT_ID_GGUF) {
            saw_gguf = true;
        }
    }
    if (!saw_ggml || !saw_gguf) {
        std::fprintf(stderr, "whispercpp must declare both GGML and GGUF formats\n");
        return 1;
    }

    rac_plugin_unregister("whispercpp");
    std::fprintf(stdout,
                 "  ok: stt slot populated, non-stt slots null, registry round-trip ok\n");
    return 0;
}
