/**
 * @file rag_backend.cpp
 * @brief RAG Pipeline Implementation — calls through LLM + Embeddings vtables
 */

#include "rag_backend.h"

#include <algorithm>
#include <cstring>
#include <unordered_set>

#include "rac/core/rac_logger.h"

#define LOG_TAG "RAG.Backend"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

static const std::string kSystemPrompt =
    "You are a helpful question-answering assistant. "
    "Answer the question using only the provided context passages. "
    "If the context does not contain enough information, say so.";

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

    bm25_index_ = std::make_unique<BM25Index>();

    ChunkerConfig chunker_config;
    chunker_config.chunk_size = config.chunk_size;
    chunker_config.chunk_overlap = config.chunk_overlap;
    chunker_ = std::make_unique<DocumentChunker>(chunker_config);

    initialized_ = (embeddings_service_ != nullptr);
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

std::vector<std::vector<float>> RAGBackend::embed_texts_batch(
    const std::vector<std::string>& texts
) const {
    if (!embeddings_service_ || texts.empty()) return {};

    std::vector<const char*> c_texts;
    c_texts.reserve(texts.size());
    for (const auto& t : texts) {
        c_texts.push_back(t.c_str());
    }

    rac_embeddings_result_t result = {};
    rac_result_t status = rac_embeddings_embed_batch(
        embeddings_service_, c_texts.data(), c_texts.size(), nullptr, &result);

    if (status != RAC_SUCCESS || result.num_embeddings == 0 || !result.embeddings) {
        rac_embeddings_result_free(&result);
        return {};
    }

    std::vector<std::vector<float>> embeddings;
    embeddings.reserve(result.num_embeddings);
    for (size_t i = 0; i < result.num_embeddings; ++i) {
        embeddings.emplace_back(
            result.embeddings[i].data,
            result.embeddings[i].data + result.embeddings[i].dimension
        );
    }

    rac_embeddings_result_free(&result);
    return embeddings;
}

// =============================================================================
// Document management
// =============================================================================

bool RAGBackend::add_document(const std::string& text, const nlohmann::json& metadata) {
    size_t embedding_dimension;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!initialized_) {
            LOGE("Pipeline not initialized");
            return false;
        }
        embedding_dimension = config_.embedding_dimension;
    }

    auto chunks = chunker_->chunk_document(text);
    LOGI("Split document into %zu chunks", chunks.size());

    if (chunks.empty()) return true;

    std::vector<std::string> chunk_texts;
    chunk_texts.reserve(chunks.size());
    for (const auto& chunk_obj : chunks) {
        chunk_texts.push_back(chunk_obj.text);
    }

    auto embeddings = embed_texts_batch(chunk_texts);

    if (embeddings.empty()) {
        LOGI("Batch embedding unavailable, falling back to single embedding");
        embeddings.reserve(chunks.size());
        for (const auto& chunk_obj : chunks) {
            embeddings.push_back(embed_text(chunk_obj.text));
        }
    }

    if (embeddings.size() != chunks.size()) {
        LOGE("Embedding count mismatch: got %zu, expected %zu",
             embeddings.size(), chunks.size());
        return false;
    }

    std::lock_guard<std::mutex> lock(mutex_);

    std::string source_preview = text.substr(0, 100);
    std::vector<DocumentChunk> doc_chunks;
    doc_chunks.reserve(chunks.size());

    for (size_t i = 0; i < chunks.size(); ++i) {
        if (embeddings[i].size() != embedding_dimension) {
            LOGE("Embedding dimension mismatch at chunk %zu: got %zu, expected %zu",
                 i, embeddings[i].size(), embedding_dimension);
            continue;
        }

        DocumentChunk chunk;
        chunk.id = "chunk_" + std::to_string(next_chunk_id_++);
        chunk.text = chunks[i].text;
        chunk.embedding = std::move(embeddings[i]);
        chunk.metadata = metadata;
        chunk.metadata["source_text"] = source_preview;
        doc_chunks.push_back(std::move(chunk));
    }

    if (!doc_chunks.empty() && !vector_store_->add_chunks_batch(doc_chunks)) {
        LOGE("Failed to add chunks batch to vector store");
        return false;
    }

    if (bm25_index_ && !doc_chunks.empty()) {
        std::vector<std::pair<std::string, std::string>> bm25_chunks;
        bm25_chunks.reserve(doc_chunks.size());
        for (const auto& chunk : doc_chunks) {
            bm25_chunks.emplace_back(chunk.id, chunk.text);
        }
        bm25_index_->add_chunks_batch(bm25_chunks);
    }

    LOGI("Successfully added %zu chunks from document", doc_chunks.size());
    return true;
}

// =============================================================================
// Search — retrieve top-k chunks from vector store
// =============================================================================

std::vector<SearchResult> RAGBackend::search(const std::string& query_text, size_t top_k) const {
    size_t embedding_dimension;
    float similarity_threshold;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        embedding_dimension = config_.embedding_dimension;
        similarity_threshold = config_.similarity_threshold;
    }

    return search_with_embedding(query_text, top_k, embedding_dimension, similarity_threshold);
}

std::vector<SearchResult> RAGBackend::search_with_embedding(
    const std::string& query_text,
    size_t top_k,
    size_t embedding_dimension,
    float similarity_threshold
) const {
    if (!initialized_) return {};

    try {
        auto query_embedding = embed_text(query_text);

        if (query_embedding.size() != embedding_dimension) {
            LOGE("Query embedding dimension mismatch");
            return {};
        }

        auto dense_results = vector_store_->search(query_embedding, top_k, similarity_threshold);

        // BM25 keyword search
        std::vector<std::pair<std::string, float>> bm25_results;
        if (bm25_index_) {
            bm25_results = bm25_index_->search(query_text, top_k);
        }

        auto fused = fuse_results(dense_results, bm25_results, top_k);
        LOGI("Hybrid search: %zu dense, %zu bm25, %zu fused",
             dense_results.size(), bm25_results.size(), fused.size());

        return fused;

    } catch (const std::exception& e) {
        LOGE("Search failed: %s", e.what());
        return {};
    }
}

// =============================================================================
// Reciprocal Rank Fusion (RRF) — merges dense + BM25 results
// =============================================================================

std::vector<SearchResult> RAGBackend::fuse_results(
    const std::vector<SearchResult>& dense_results,
    const std::vector<std::pair<std::string, float>>& bm25_results,
    size_t top_k
) const {
    static constexpr float kRRFConstant = 60.0f;
    static constexpr float kMaxRRFScore = 2.0f / 61.0f;

    if (bm25_results.empty()) return dense_results;

    size_t missing_rank = top_k + 1;

    // Build RRF scores: chunk_id -> accumulated rrf score
    std::unordered_map<std::string, float> rrf_scores;

    for (size_t i = 0; i < dense_results.size(); ++i) {
        float rank_score = 1.0f / (kRRFConstant + static_cast<float>(i + 1));
        rrf_scores[dense_results[i].id] += rank_score;
    }

    for (size_t i = 0; i < bm25_results.size(); ++i) {
        float rank_score = 1.0f / (kRRFConstant + static_cast<float>(i + 1));
        rrf_scores[bm25_results[i].first] += rank_score;
    }

    float missing_score = 1.0f / (kRRFConstant + static_cast<float>(missing_rank));

    std::unordered_set<std::string> dense_ids;
    for (const auto& r : dense_results) dense_ids.insert(r.id);

    std::unordered_set<std::string> bm25_ids;
    for (const auto& r : bm25_results) bm25_ids.insert(r.first);

    for (auto& [id, score] : rrf_scores) {
        if (dense_ids.find(id) == dense_ids.end()) {
            score += missing_score; // Not in dense → add missing-rank dense score
        }
        if (bm25_ids.find(id) == bm25_ids.end()) {
            score += missing_score; // Not in BM25 → add missing-rank BM25 score
        }
    }

    std::unordered_map<std::string, const SearchResult*> dense_map;
    for (const auto& r : dense_results) {
        dense_map[r.id] = &r;
    }

    std::vector<std::pair<std::string, float>> sorted_ids;
    sorted_ids.reserve(rrf_scores.size());
    for (const auto& [id, score] : rrf_scores) {
        sorted_ids.emplace_back(id, score);
    }
    std::sort(sorted_ids.begin(), sorted_ids.end(),
              [](const auto& a, const auto& b) { return a.second > b.second; });

    if (sorted_ids.size() > top_k) {
        sorted_ids.resize(top_k);
    }

    std::vector<SearchResult> fused;
    fused.reserve(sorted_ids.size());

    for (const auto& [id, rrf_score] : sorted_ids) {
        float normalized = rrf_score / kMaxRRFScore;
        normalized = std::min(1.0f, std::max(0.0f, normalized));

        auto dense_it = dense_map.find(id);
        if (dense_it != dense_map.end()) {
            SearchResult result = *(dense_it->second);
            result.score = normalized;
            result.similarity = normalized;
            fused.push_back(std::move(result));
        } else {
            SearchResult result;
            result.id = id;
            result.chunk_id = id;
            result.score = normalized;
            result.similarity = normalized;

            if (vector_store_) {
                auto chunk = vector_store_->get_chunk(id);
                if (chunk) {
                    result.text = chunk->text;
                    result.metadata = chunk->metadata;
                }
            }

            fused.push_back(std::move(result));
        }
    }

    return fused;
}

// =============================================================================
// Context helpers
// =============================================================================

std::string RAGBackend::build_context(const std::vector<SearchResult>& results) const {
    static constexpr size_t kCharsPerToken = 4;
    const size_t max_chars = config_.max_context_tokens * kCharsPerToken;

    std::string context;
    for (size_t i = 0; i < results.size(); ++i) {
        const std::string& chunk_text = results[i].text;
        size_t separator_len = (i > 0) ? 2 : 0; // "\n\n"

        if (context.size() + separator_len + chunk_text.size() > max_chars) {
            LOGI("Context budget reached at chunk %zu/%zu (%zu chars, limit ~%zu)",
                 i, results.size(), context.size(), max_chars);
            break;
        }

        if (i > 0) context += "\n\n";
        context += chunk_text;
    }
    return context;
}

std::string RAGBackend::format_prompt(const std::string& query, const std::string& context) const {
    std::string prompt = config_.prompt_template;

    for (size_t pos = prompt.find("{query}"); pos != std::string::npos;
         pos = prompt.find("{query}", pos + query.size())) {
        prompt.replace(pos, 7, query);
    }

    for (size_t pos = prompt.find("{context}"); pos != std::string::npos;
         pos = prompt.find("{context}", pos + context.size())) {
        prompt.replace(pos, 9, context);
    }

    return prompt;
}

// =============================================================================
// Query — insert top N chunks then generate
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

    // 1. Retrieve top-k chunks
    auto search_results = search_with_embedding(
        question, top_k, embedding_dimension, similarity_threshold);

    if (search_results.empty()) {
        LOGI("No relevant documents found");
        if (out_result) {
            out_result->text = rac_strdup("I don't have enough information to answer that question.");
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

    // 2. Build context from retrieved chunks
    std::string assembled_context = build_context(search_results);
    LOGI("Built context from %zu chunks (%zu chars)", search_results.size(), assembled_context.size());

    // 3. Format the full prompt using the prompt template (context + query together)
    std::string full_prompt = format_prompt(question, assembled_context);

    // 4. Generate via standard rac_llm_generate so the chat template is applied
    //    uniformly to the entire prompt (system + context + question).
    //    This avoids the KV cache / chat template mismatch that occurs when raw
    //    context is injected via append_context and only the query gets templated.
    rac_llm_options_t rag_options = options ? *options : RAC_LLM_OPTIONS_DEFAULT;
    if (!rag_options.system_prompt || rag_options.system_prompt[0] == '\0') {
        rag_options.system_prompt = kSystemPrompt.c_str();
    }

    rac_result_t status = rac_llm_generate(llm, full_prompt.c_str(), &rag_options, out_result);

    if (status != RAC_SUCCESS) {
        LOGE("rac_llm_generate failed: %d", status);
        return status;
    }

    // 6. Populate metadata
    out_metadata["chunks_used"] = search_results.size();
    out_metadata["context_used"] = assembled_context;

    nlohmann::json sources = nlohmann::json::array();
    for (const auto& result : search_results) {
        nlohmann::json source;
        source["id"] = result.id;
        source["score"] = result.score;
        source["text"] = result.text;
        if (result.metadata.contains("source_text")) {
            source["source"] = result.metadata["source_text"];
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
    if (bm25_index_) bm25_index_->clear();
    next_chunk_id_ = 0;
}

nlohmann::json RAGBackend::get_statistics() const {
    std::lock_guard<std::mutex> lock(mutex_);
    nlohmann::json stats;
    if (vector_store_) stats = vector_store_->get_statistics();

    stats["bm25_chunks"] = bm25_index_ ? bm25_index_->size() : 0;
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
    std::lock_guard<std::mutex> lock(mutex_);
    return vector_store_ ? vector_store_->size() : 0;
}

} // namespace rag
} // namespace runanywhere
