/**
 * @file test_plugin_entry_onnx.cpp
 * @brief Verifies the ONNX Runtime plugin entry point owns embeddings only.
 *
 * GAP 02 Phase 10.
 */

#include <cstdio>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry_onnx.h"
#include "rac/plugin/rac_primitive.h"

int main() {
    std::fprintf(stdout, "test_plugin_entry_onnx\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_onnx();
    if (vt == nullptr) { return 1; }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) { return 1; }

    if (vt->embedding_ops == nullptr) {
        std::fprintf(stderr, "embedding_ops is NULL\n");
        return 1;
    }
    if (vt->stt_ops != nullptr || vt->tts_ops != nullptr || vt->vad_ops != nullptr) {
        std::fprintf(stderr, "speech ops should live in the Sherpa engine\n");
        return 1;
    }

    rac_plugin_register(vt);

    // ONNX owns embeddings after Sherpa speech extraction.
    if (rac_plugin_find(RAC_PRIMITIVE_EMBED) != vt) { return 1; }

    // LLM / VLM / speech primitives must remain off ONNX.
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) { return 1; }
    if (rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE)   != nullptr) { return 1; }
    if (rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE)   != nullptr) { return 1; }
    if (rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE) != nullptr) { return 1; }

    rac_plugin_unregister("onnx");
    std::fprintf(stdout, "  ok: embedding slot populated, speech slots null, registry round-trip ok\n");
    return 0;
}
