/**
 * @file rag_backend.cpp
 * @brief RAG Pipeline Implementation — calls through LLM + Embeddings vtables
 */

#include "rag_backend.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <chrono>

#include "rac/core/rac_logger.h"

#define LOG_TAG "RAG.Backend"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

static const std::string kICLSystemPrompt =
    "You are a question-answering assistant. Given context passages and a question, "
    "determine if the passages contain enough information to answer the question.\n\n"
    "Example 1 (Sufficient context):\n"
    "Context: \"The Eiffel Tower was completed in 1889 for the World's Fair in Paris.\"\n"
    "Question: \"When was the Eiffel Tower built?\"\n"
    "Assessment: Yes - the context directly states the completion year.\n\n"
    "Example 2 (Insufficient context):\n"
    "Context: \"Paris is the capital of France and known for its cuisine.\"\n"
    "Question: \"When was the Eiffel Tower built?\"\n"
    "Assessment: No - the context discusses Paris but not the Eiffel Tower's construction date.\n";

namespace runanywhere {
namespace rag {

RAGBackend::RAGBackend(
    const RAGBackendConfig& config,
    rac_handle_t llm_service,
    rac_handle_t embeddings_service,
    bool owns_services
) : config_(config),
    llm_service_(llm_service),
    embeddings_service_(embeddings_service),
    owns_services_(owns_services) {

    VectorStoreConfig store_config;
    store_config.dimension = config.embedding_dimension;
    vector_store_ = std::make_unique<VectorStoreUSearch>(store_config);

    ChunkerConfig chunker_config;
    chunker_config.chunk_size = config.chunk_size;
    chunker_config.chunk_overlap = config.chunk_overlap;
    chunker_ = std::make_unique<DocumentChunker>(chunker_config);

    initialized_ = (llm_service_ != nullptr && embeddings_service_ != nullptr);
    LOGI("RAG pipeline initialized: dim=%zu, chunk_size=%zu, has_llm=%d, has_embed=%d",
         config.embedding_dimension, config.chunk_size,
         llm_service_ != nullptr, embeddings_service_ != nullptr);
}

RAGBackend::~RAGBackend() {
    clear();
    if (owns_services_) {
        if (llm_service_) {
            rac_llm_destroy(llm_service_);
            llm_service_ = nullptr;
        }
        if (embeddings_service_) {
            rac_embeddings_destroy(embeddings_service_);
            embeddings_service_ = nullptr;
        }
    }
}

// =============================================================================
// Embedding helper — calls through embeddings service vtable
// =============================================================================

std::vector<float> RAGBackend::embed_text(const std::string& text) const {
    if (!embeddings_service_) return {};

    rac_embeddings_result_t result = {};
    rac_result_t status = rac_embeddings_embed(embeddings_service_, text.c_str(), nullptr, &result);

    if (status != RAC_SUCCESS || result.num_embeddings == 0 || !result.embeddings) {
        rac_embeddings_result_free(&result);
        return {};
    }

    std::vector<float> embedding(
        result.embeddings[0].data,
        result.embeddings[0].data + result.embeddings[0].dimension
    );

    rac_embeddings_result_free(&result);
    return embedding;
}

// =============================================================================
// Document management
// =============================================================================

bool RAGBackend::add_document(const std::string& text, const nlohmann::json& metadata) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!initialized_) {
        LOGE("Pipeline not initialized");
        return false;
    }

    auto chunks = chunker_->chunk_document(text);
    LOGI("Split document into %zu chunks", chunks.size());

    for (const auto& chunk_obj : chunks) {
        auto embedding = embed_text(chunk_obj.text);

        if (embedding.size() != config_.embedding_dimension) {
            LOGE("Embedding dimension mismatch: got %zu, expected %zu",
                 embedding.size(), config_.embedding_dimension);
            continue;
        }

        DocumentChunk chunk;
        chunk.id = "chunk_" + std::to_string(next_chunk_id_++);
        chunk.text = chunk_obj.text;
        chunk.embedding = std::move(embedding);
        chunk.metadata = metadata;
        chunk.metadata["source_text"] = text.substr(0, 100);

        if (!vector_store_->add_chunk(chunk)) {
            LOGE("Failed to add chunk to vector store");
            return false;
        }
    }

    LOGI("Successfully added %zu chunks from document", chunks.size());
    return true;
}

// =============================================================================
// Search — two-tier retrieval (parent chunks → sentence re-ranking)
// =============================================================================

std::vector<SearchResult> RAGBackend::search(const std::string& query_text, size_t top_k) const {
    size_t embedding_dimension;
    float similarity_threshold;
    bool initialized;
    const DocumentChunker* chunker;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        embedding_dimension = config_.embedding_dimension;
        similarity_threshold = config_.similarity_threshold;
        initialized = initialized_;
        chunker = chunker_.get();
    }

    return search_with_embedding(query_text, top_k, embedding_dimension, similarity_threshold, chunker);
}

std::vector<SearchResult> RAGBackend::search_with_embedding(
    const std::string& query_text,
    size_t top_k,
    size_t embedding_dimension,
    float similarity_threshold,
    const DocumentChunker* chunker
) const {
    if (!initialized_ || !chunker) return {};

    auto cosine_similarity = [](const std::vector<float>& a, const std::vector<float>& b) -> float {
        if (a.size() != b.size() || a.empty()) return 0.0f;
        float dot = 0.0f, norm_a = 0.0f, norm_b = 0.0f;
        for (size_t i = 0; i < a.size(); ++i) {
            dot += a[i] * b[i];
            norm_a += a[i] * a[i];
            norm_b += b[i] * b[i];
        }
        float denom = std::sqrt(norm_a) * std::sqrt(norm_b);
        return denom > 0.0f ? dot / denom : 0.0f;
    };

    try {
        static constexpr size_t kParentChunkCount = 5;
        auto query_embedding = embed_text(query_text);

        if (query_embedding.size() != embedding_dimension) {
            LOGE("Query embedding dimension mismatch");
            return {};
        }

        auto parent_chunks = vector_store_->search(query_embedding, kParentChunkCount, similarity_threshold);
        LOGI("Retrieved %zu parent chunks", parent_chunks.size());

        if (parent_chunks.empty()) return {};

        struct ScoredSentence {
            std::string text;
            float similarity;
            std::string parent_chunk_id;
            nlohmann::json parent_metadata;
        };

        std::vector<ScoredSentence> scored_sentences;

        for (const auto& parent : parent_chunks) {
            auto sentences = chunker->split_into_sentences(parent.text);

            for (const auto& sentence : sentences) {
                if (sentence.size() < 3) continue;

                auto sentence_embedding = embed_text(sentence);
                float sim = cosine_similarity(query_embedding, sentence_embedding);

                scored_sentences.push_back({sentence, sim, parent.chunk_id, parent.metadata});
            }
        }

        if (scored_sentences.empty()) return {};

        static constexpr size_t kTopSentences = 10;
        size_t result_count = std::min(kTopSentences, scored_sentences.size());

        std::partial_sort(
            scored_sentences.begin(),
            scored_sentences.begin() + static_cast<std::ptrdiff_t>(result_count),
            scored_sentences.end(),
            [](const ScoredSentence& a, const ScoredSentence& b) {
                return a.similarity > b.similarity;
            }
        );

        std::vector<SearchResult> results;
        results.reserve(result_count);

        for (size_t i = 0; i < result_count; ++i) {
            SearchResult r;
            r.id = scored_sentences[i].parent_chunk_id + "_s" + std::to_string(i);
            r.chunk_id = scored_sentences[i].parent_chunk_id;
            r.text = scored_sentences[i].text;
            r.similarity = scored_sentences[i].similarity;
            r.score = scored_sentences[i].similarity;
            r.metadata = scored_sentences[i].parent_metadata;
            results.push_back(std::move(r));
        }

        return results;

    } catch (const std::exception& e) {
        LOGE("Search failed: %s", e.what());
        return {};
    }
}

// =============================================================================
// Context helpers
// =============================================================================

std::string RAGBackend::build_context(const std::vector<SearchResult>& results) const {
    std::string context;
    for (size_t i = 0; i < results.size(); ++i) {
        if (i > 0) context += "\n\n";
        context += results[i].text;
    }
    return context;
}

std::string RAGBackend::format_prompt(const std::string& query, const std::string& context) const {
    std::string prompt = config_.prompt_template;

    size_t pos = prompt.find("{context}");
    if (pos != std::string::npos) prompt.replace(pos, 9, context);

    pos = prompt.find("{query}");
    if (pos != std::string::npos) prompt.replace(pos, 7, query);

    return prompt;
}

// =============================================================================
// Query — adaptive context accumulation via LLM service vtable
// =============================================================================

rac_result_t RAGBackend::query(
    const std::string& question,
    const rac_llm_options_t* options,
    rac_llm_result_t* out_result,
    nlohmann::json& out_metadata
) {
    rac_handle_t llm;
    size_t embedding_dimension;
    float similarity_threshold;
    size_t top_k;
    bool initialized;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        llm = llm_service_;
        embedding_dimension = config_.embedding_dimension;
        similarity_threshold = config_.similarity_threshold;
        top_k = config_.top_k;
        initialized = initialized_;
    }

    if (!initialized || !llm) {
        LOGE("Pipeline not initialized or LLM service not available");
        return RAC_ERROR_INVALID_STATE;
    }

    // 1. Clear LLM context
    rac_llm_clear_context(llm);

    // 2. Inject ICL system prompt
    rac_result_t status = rac_llm_inject_system_prompt(llm, kICLSystemPrompt.c_str());
    if (status != RAC_SUCCESS) {
        LOGI("inject_system_prompt not supported (status=%d), continuing", status);
    }

    // 3. Two-tier search
    auto search_results = search_with_embedding(
        question, top_k, embedding_dimension, similarity_threshold, chunker_.get());

    if (search_results.empty()) {
        LOGI("No relevant documents found");
        if (out_result) {
            out_result->text = strdup("I don't have enough information to answer that question.");
            out_result->completion_tokens = 0;
            out_result->prompt_tokens = 0;
            out_result->total_tokens = 0;
            out_result->total_time_ms = 0;
            out_result->tokens_per_second = 0;
            out_result->time_to_first_token_ms = 0;
        }
        out_metadata["reason"] = "no_context";
        return RAC_SUCCESS;
    }

    // 4. Adaptive context accumulation
    float confidence = 0.0f;
    size_t sentences_used = 0;

    for (const auto& sentence_result : search_results) {
        std::string append_text = (sentences_used == 0)
            ? sentence_result.text
            : ("\n" + sentence_result.text);

        rac_llm_append_context(llm, append_text.c_str());
        sentences_used++;

        rac_llm_probe_confidence(llm, "", question.c_str(), &confidence);

        LOGI("Adaptive loop: sentence %zu/%zu, confidence=%.4f",
             sentences_used, search_results.size(), confidence);

        if (confidence > kConfidenceThreshold) {
            LOGI("Confidence threshold reached at sentence %zu", sentences_used);
            break;
        }
    }

    bool threshold_reached = confidence > kConfidenceThreshold;

    if (!kKeepPartialContext && !threshold_reached) {
        rac_llm_clear_context(llm);
        rac_llm_inject_system_prompt(llm, kICLSystemPrompt.c_str());
        sentences_used = 0;
    }

    // 5. Generate answer from accumulated KV cache
    std::string query_suffix = "\n\nQuestion: " + question + "\n\nAnswer:";
    status = rac_llm_generate_from_context(llm, query_suffix.c_str(), options, out_result);

    if (status != RAC_SUCCESS) {
        LOGE("generate_from_context failed: %d", status);
        return status;
    }

    // 6. Populate metadata
    out_metadata["sentences_used"] = sentences_used;
    out_metadata["final_confidence"] = confidence;
    out_metadata["threshold_reached"] = threshold_reached;
    out_metadata["total_sentences"] = search_results.size();
    out_metadata["keep_partial_context"] = kKeepPartialContext;

    nlohmann::json sources = nlohmann::json::array();
    for (size_t i = 0; i < sentences_used && i < search_results.size(); ++i) {
        nlohmann::json source;
        source["id"] = search_results[i].id;
        source["score"] = search_results[i].score;
        if (search_results[i].metadata.contains("source_text")) {
            source["source"] = search_results[i].metadata["source_text"];
        }
        sources.push_back(source);
    }
    out_metadata["sources"] = sources;

    return RAC_SUCCESS;
}

// =============================================================================
// Utility
// =============================================================================

void RAGBackend::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (vector_store_) vector_store_->clear();
    next_chunk_id_ = 0;
}

nlohmann::json RAGBackend::get_statistics() const {
    std::lock_guard<std::mutex> lock(mutex_);
    nlohmann::json stats;
    if (vector_store_) stats = vector_store_->get_statistics();

    stats["config"] = {
        {"embedding_dimension", config_.embedding_dimension},
        {"top_k", config_.top_k},
        {"similarity_threshold", config_.similarity_threshold},
        {"chunk_size", config_.chunk_size},
        {"chunk_overlap", config_.chunk_overlap}
    };
    return stats;
}

size_t RAGBackend::document_count() const {
    return vector_store_ ? vector_store_->size() : 0;
}

} // namespace rag
} // namespace runanywhere
