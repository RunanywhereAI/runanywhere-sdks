/**
 * @file test_plugin_entry_llamacpp.cpp
 * @brief Verifies the llama.cpp plugin entry point returns a well-formed vtable.
 *
 * This test does NOT load a model — that's handled by
 * downstream integration tests. It only asserts:
 *   - The entry symbol is present.
 *   - The returned vtable has abi_version == RAC_PLUGIN_API_VERSION.
 *   - The LLM, embeddings, and VLM op slots are non-NULL.
 *   - Every required embeddings function pointer is non-NULL.
 *   - Registering + finding via the unified registry round-trips.
 */

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/rerank/rac_rerank_service.h"
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
    if (vt->embedding_ops == nullptr || vt->embedding_ops->create == nullptr ||
        vt->embedding_ops->initialize == nullptr || vt->embedding_ops->embed == nullptr ||
        vt->embedding_ops->embed_batch == nullptr || vt->embedding_ops->cleanup == nullptr ||
        vt->embedding_ops->destroy == nullptr) {
        std::fprintf(stderr, "llama.cpp embeddings ops are incomplete\n");
        return 1;
    }
    if (vt->vlm_ops == nullptr) {
        std::fprintf(stderr, "vlm_ops is NULL — VLM primitive not served\n");
        return 1;
    }
    // Reranking (rank-pooling GGUFs) is served as a modality of llama.cpp
    // (RAC_PRIMITIVE_RERANK, revived in plugin ABI v8).
    if (vt->rerank_ops == nullptr || vt->rerank_ops->create == nullptr ||
        vt->rerank_ops->initialize == nullptr || vt->rerank_ops->rerank == nullptr ||
        vt->rerank_ops->cleanup == nullptr || vt->rerank_ops->destroy == nullptr) {
        std::fprintf(stderr, "llama.cpp rerank ops are incomplete\n");
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
    if (rac_plugin_find(RAC_PRIMITIVE_EMBED) != vt || rac_plugin_find(RAC_PRIMITIVE_VLM) != vt ||
        rac_plugin_find(RAC_PRIMITIVE_RERANK) != vt) {
        std::fprintf(stderr, "llama.cpp embedding/VLM/rerank registry routing failed\n");
        return 1;
    }
    if (rac_engine_vtable_slot(vt, RAC_PRIMITIVE_RERANK) != vt->rerank_ops) {
        std::fprintf(stderr, "rac_engine_vtable_slot did not resolve rerank_ops\n");
        return 1;
    }
    const rac_engine_manifest_t* manifest = rac_engine_manifest_find("llamacpp");
    if (manifest == nullptr || manifest->availability != RAC_ENGINE_AVAILABILITY_PUBLIC ||
        manifest->primitives_count != 4 || manifest->primitives[0] != RAC_PRIMITIVE_GENERATE_TEXT ||
        manifest->primitives[1] != RAC_PRIMITIVE_EMBED ||
        manifest->primitives[2] != RAC_PRIMITIVE_VLM ||
        manifest->primitives[3] != RAC_PRIMITIVE_RERANK) {
        std::fprintf(stderr, "llama.cpp manifest was not published correctly\n");
        return 1;
    }

    const char* embedding_model = std::getenv("RAC_TEST_LLAMACPP_EMBED_MODEL");
    if (embedding_model != nullptr && embedding_model[0] != '\0') {
        void* implementation = nullptr;
        if (vt->embedding_ops->create("llamacpp-embedding-smoke", nullptr, &implementation) !=
                RAC_SUCCESS ||
            implementation == nullptr) {
            std::fprintf(stderr, "failed to create llama.cpp embeddings implementation\n");
            return 1;
        }
        if (vt->embedding_ops->initialize(implementation, embedding_model) != RAC_SUCCESS) {
            std::fprintf(stderr, "failed to initialize llama.cpp embedding model: %s\n",
                         embedding_model);
            vt->embedding_ops->destroy(implementation);
            return 1;
        }
        const rac_embeddings_options_t options = RAC_EMBEDDINGS_OPTIONS_DEFAULT;
        rac_embeddings_result_t result{};
        if (vt->embedding_ops->embed(implementation, "on-device semantic retrieval", &options,
                                     &result) != RAC_SUCCESS ||
            result.num_embeddings != 1 || result.dimension == 0 || result.embeddings == nullptr ||
            result.embeddings[0].data == nullptr) {
            std::fprintf(stderr, "real llama.cpp embedding smoke failed\n");
            rac_embeddings_result_free(&result);
            vt->embedding_ops->destroy(implementation);
            return 1;
        }
        double norm_squared = 0.0;
        for (size_t index = 0; index < result.dimension; ++index) {
            const float value = result.embeddings[0].data[index];
            if (!std::isfinite(value)) {
                std::fprintf(stderr, "embedding contains a non-finite value\n");
                rac_embeddings_result_free(&result);
                vt->embedding_ops->destroy(implementation);
                return 1;
            }
            norm_squared += static_cast<double>(value) * static_cast<double>(value);
        }
        if (std::abs(std::sqrt(norm_squared) - 1.0) > 1e-3) {
            std::fprintf(stderr, "embedding is not L2-normalized (norm=%f)\n",
                         std::sqrt(norm_squared));
            rac_embeddings_result_free(&result);
            vt->embedding_ops->destroy(implementation);
            return 1;
        }
        std::fprintf(stdout, "  ok: real embedding model dimension=%zu tokens=%d\n",
                     result.dimension, result.total_tokens);
        rac_embeddings_result_free(&result);

        std::string long_text;
        long_text.reserve(4200);
        for (int index = 0; index < 700; ++index) {
            long_text += "token ";
        }
        rac_embeddings_options_t long_options = RAC_EMBEDDINGS_OPTIONS_DEFAULT;
        if (vt->embedding_ops->embed(implementation, long_text.c_str(), &long_options, &result) !=
                RAC_SUCCESS ||
            result.total_tokens <= RAC_EMBEDDINGS_DEFAULT_MAX_TOKENS) {
            std::fprintf(stderr, "default sliding-window embedding failed\n");
            rac_embeddings_result_free(&result);
            vt->embedding_ops->destroy(implementation);
            return 1;
        }
        rac_embeddings_result_free(&result);

        long_options.truncate = 0;
        if (vt->embedding_ops->embed(implementation, long_text.c_str(), &long_options, &result) !=
            RAC_ERROR_TEXT_TOO_LONG) {
            std::fprintf(stderr, "truncate=false did not reject an overlong input\n");
            rac_embeddings_result_free(&result);
            vt->embedding_ops->destroy(implementation);
            return 1;
        }

        long_options.truncate = 1;
        long_options.n_threads = 2;
        if (vt->embedding_ops->embed(implementation, long_text.c_str(), &long_options, &result) !=
                RAC_SUCCESS ||
            result.total_tokens != RAC_EMBEDDINGS_DEFAULT_MAX_TOKENS) {
            std::fprintf(stderr, "truncate=true did not enforce the context window\n");
            rac_embeddings_result_free(&result);
            vt->embedding_ops->destroy(implementation);
            return 1;
        }
        rac_embeddings_result_free(&result);
        std::fprintf(stdout, "  ok: long-input sliding/reject/truncate policies\n");
        vt->embedding_ops->cleanup(implementation);
        vt->embedding_ops->destroy(implementation);
    }
    rac_plugin_unregister("llamacpp");

    std::fprintf(stdout, "  ok: vtable well-formed, registry round-trip ok\n");
    return 0;
}
