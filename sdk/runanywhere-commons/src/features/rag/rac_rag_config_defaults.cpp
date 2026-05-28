/**
 * @file rac_rag_config_defaults.cpp
 * @brief Canonical RAGConfiguration defaults helper (P2-T14).
 *
 * Commons-owned port of Swift's `RARAGConfiguration.defaults()`
 * (sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/
 * RAGProto+Helpers.swift) so every platform SDK consumes the same
 * default-population logic via a single C ABI.
 *
 * Canonical defaults (mirrored from Swift):
 *   embedding_dimension   = 384
 *   top_k                 = 5
 *   similarity_threshold  = 0.7
 *   chunk_size            = 512
 *   chunk_overlap         = 64
 *
 * Field-merge semantics mirror Swift's per-field setter pattern:
 *   - Inbound numeric fields are `optional` in the proto, so we use the
 *     generated `has_*()` accessors: presence == "caller-supplied override",
 *     absence == "use canonical default". This preserves explicit-zero
 *     values (e.g. chunk_overlap=0 = no overlap).
 *   - Inbound bool fields pass through verbatim (schema zero is the natural
 *     default; no separate canonical default exists).
 *   - String / id fields pass through verbatim from the inbound request
 *     (proto zero is the empty string; that is what Swift's
 *     `RARAGConfiguration.defaults(embeddingModelID: "", llmModelID: "")`
 *     yields when callers don't override).
 *
 * Lives in a NEW source file rather than appending to rac_rag_proto_abi.cpp
 * to stay merge-safe while concurrent agents edit feature/rag sources.
 */

#include <cstdint>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "rag.pb.h"
#endif

namespace {

#if defined(RAC_HAVE_PROTOBUF)

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return size == 0 || bytes != nullptr;
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize RAGConfiguration defaults");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" rac_result_t
rac_rag_request_with_defaults_proto(const uint8_t* in_request_bytes, size_t in_size,
                                    rac_proto_buffer_t* out_RARAGConfiguration) {
    if (!out_RARAGConfiguration) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_request_bytes;
    (void)in_size;
    return rac_proto_buffer_set_error(out_RARAGConfiguration, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!valid_bytes(in_request_bytes, in_size)) {
        return rac_proto_buffer_set_error(out_RARAGConfiguration, RAC_ERROR_DECODING_ERROR,
                                          "RAGConfiguration request bytes are invalid");
    }

    runanywhere::v1::RAGConfiguration request;
    if (in_size > 0 &&
        !request.ParseFromArray(parse_data(in_request_bytes, in_size), static_cast<int>(in_size))) {
        return rac_proto_buffer_set_error(out_RARAGConfiguration, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse RAGConfiguration request");
    }

    // Start from the canonical defaults, then layer caller overrides over them.
    // Numeric overrides apply when the field is *present* on the wire
    // (proto3 `optional` semantics), which preserves explicit-zero values
    // such as chunk_overlap=0 ("no overlap"). Strings pass through verbatim —
    // empty inbound string means "no caller-supplied id", which mirrors
    // Swift's `defaults(embeddingModelID: "", llmModelID: "")` behavior.
    runanywhere::v1::RAGConfiguration cfg;
    cfg.set_embedding_dimension(384);
    cfg.set_top_k(5);
    cfg.set_similarity_threshold(0.7f);
    cfg.set_chunk_size(512);
    cfg.set_chunk_overlap(64);

    // String/id fields — pass through verbatim from the inbound request.
    cfg.set_embedding_model_id(request.embedding_model_id());
    cfg.set_llm_model_id(request.llm_model_id());
    if (request.has_prompt_template()) {
        cfg.set_prompt_template(request.prompt_template());
    }
    if (request.has_embedding_config_json()) {
        cfg.set_embedding_config_json(request.embedding_config_json());
    }
    if (request.has_llm_config_json()) {
        cfg.set_llm_config_json(request.llm_config_json());
    }
    if (request.has_index_path()) {
        cfg.set_index_path(request.index_path());
    }
    if (request.has_reranker_model_id()) {
        cfg.set_reranker_model_id(request.reranker_model_id());
    }

    // Numeric overrides — presence (has_*) wins, so explicit zero is honored.
    if (request.has_embedding_dimension()) {
        cfg.set_embedding_dimension(request.embedding_dimension());
    }
    if (request.has_top_k()) {
        cfg.set_top_k(request.top_k());
    }
    if (request.has_similarity_threshold()) {
        cfg.set_similarity_threshold(request.similarity_threshold());
    }
    if (request.has_chunk_size()) {
        cfg.set_chunk_size(request.chunk_size());
    }
    if (request.has_chunk_overlap()) {
        cfg.set_chunk_overlap(request.chunk_overlap());
    }
    if (request.has_max_context_tokens()) {
        cfg.set_max_context_tokens(request.max_context_tokens());
    }

    // Bool / passthrough — inbound wins regardless of value (no separate
    // canonical default, schema zero is the natural default).
    cfg.set_persist_index(request.persist_index());
    cfg.set_rerank_results(request.rerank_results());

    return copy_proto(cfg, out_RARAGConfiguration);
#endif
}
