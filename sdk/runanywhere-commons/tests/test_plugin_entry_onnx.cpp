/**
 * @file test_plugin_entry_onnx.cpp
 * @brief Verifies ONNX owns segmentation, vocoding, and optional RAG embeddings.
 */

#include <cstdio>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry_onnx.h"
#include "rac/plugin/rac_primitive.h"

int main() {
    std::fprintf(stdout, "test_plugin_entry_onnx\n");

    const rac_engine_vtable_t* vt = rac_plugin_entry_onnx();
    if (vt == nullptr) {
        return 1;
    }
    if (vt->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        return 1;
    }

    if (vt->segmentation_ops == nullptr) {
        std::fprintf(stderr, "segmentation_ops is NULL\n");
        return 1;
    }
    if (vt->vocoder_ops == nullptr) {
        std::fprintf(stderr, "vocoder_ops is NULL\n");
        return 1;
    }
    if (vt->stt_ops != nullptr || vt->tts_ops != nullptr || vt->vad_ops != nullptr) {
        std::fprintf(stderr, "speech ops should live in the Sherpa engine\n");
        return 1;
    }

    rac_plugin_register(vt);

    // Segmentation is unconditional; embeddings are present only on RAG builds.
    if (rac_plugin_find(RAC_PRIMITIVE_SEGMENT) != vt) {
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_VOCODE) != vt) {
        return 1;
    }
    if (vt->embedding_ops != nullptr && rac_plugin_find(RAC_PRIMITIVE_EMBED) != vt) {
        return 1;
    }

    // LLM / VLM / speech primitives must remain off ONNX.
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) != nullptr) {
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) != nullptr) {
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE) != nullptr) {
        return 1;
    }

    const rac_engine_manifest_t* manifest = rac_engine_manifest_find("onnx");
    const bool manifest_ok_with_rag = vt->embedding_ops != nullptr && manifest != nullptr &&
                                      manifest->primitives_count == 3 &&
                                      manifest->primitives[0] == RAC_PRIMITIVE_EMBED &&
                                      manifest->primitives[1] == RAC_PRIMITIVE_SEGMENT &&
                                      manifest->primitives[2] == RAC_PRIMITIVE_VOCODE;
    const bool manifest_ok_without_rag = vt->embedding_ops == nullptr && manifest != nullptr &&
                                         manifest->primitives_count == 2 &&
                                         manifest->primitives[0] == RAC_PRIMITIVE_SEGMENT &&
                                         manifest->primitives[1] == RAC_PRIMITIVE_VOCODE;
    if (manifest == nullptr || manifest->availability != RAC_ENGINE_AVAILABILITY_PUBLIC ||
        (!manifest_ok_with_rag && !manifest_ok_without_rag)) {
        std::fprintf(stderr, "ONNX manifest was not published correctly\n");
        return 1;
    }

    rac_plugin_unregister("onnx");
    std::fprintf(stdout,
                 "  ok: segmentation/vocoder slots populated, optional embedding slot coherent, "
                 "speech slots null\n");
    return 0;
}
