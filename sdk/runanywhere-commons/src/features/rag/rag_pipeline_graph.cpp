/**
 * @file rag_pipeline_graph.cpp
 * @brief Sequential implementation of the RAG query pipeline.
 */

#include "rag_pipeline_graph.h"

#include "bm25_index.h"
#include "vector_store_usearch.h"

#include <algorithm>
#include <exception>
#include <unordered_map>
#include <unordered_set>
#include <utility>

#include "rac/core/rac_logger.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"

#define LOG_TAG "RAG.Graph"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

namespace runanywhere::rag {

namespace {

// ---------------------------------------------------------------------------
// Reciprocal Rank Fusion — pulled verbatim from the previous RAGBackend
// implementation so the graph path matches retrieval semantics 1:1.
// ---------------------------------------------------------------------------

std::vector<SearchResult>
fuse_results(const std::vector<SearchResult>& dense_results,
             const std::vector<std::pair<std::string, float>>& bm25_results,
             const VectorStoreUSearch* vector_store, size_t top_k) {
    static constexpr float kRRFConstant = 60.0f;
    static constexpr float kMaxRRFScore = 2.0f / 61.0f;

    if (bm25_results.empty())
        return dense_results;

    const size_t missing_rank = top_k + 1;

    std::unordered_map<std::string, float> rrf_scores;
    for (size_t i = 0; i < dense_results.size(); ++i) {
        rrf_scores[dense_results[i].id] += 1.0f / (kRRFConstant + static_cast<float>(i + 1));
    }
    for (size_t i = 0; i < bm25_results.size(); ++i) {
        rrf_scores[bm25_results[i].first] += 1.0f / (kRRFConstant + static_cast<float>(i + 1));
    }

    const float missing_score = 1.0f / (kRRFConstant + static_cast<float>(missing_rank));

    std::unordered_set<std::string> dense_ids;
    for (const auto& r : dense_results)
        dense_ids.insert(r.id);
    std::unordered_set<std::string> bm25_ids;
    for (const auto& r : bm25_results)
        bm25_ids.insert(r.first);

    for (auto& [id, score] : rrf_scores) {
        if (dense_ids.find(id) == dense_ids.end())
            score += missing_score;
        if (bm25_ids.find(id) == bm25_ids.end())
            score += missing_score;
    }

    std::unordered_map<std::string, const SearchResult*> dense_map;
    for (const auto& r : dense_results)
        dense_map[r.id] = &r;

    std::vector<std::pair<std::string, float>> sorted_ids;
    sorted_ids.reserve(rrf_scores.size());
    for (const auto& [id, score] : rrf_scores)
        sorted_ids.emplace_back(id, score);
    std::sort(sorted_ids.begin(), sorted_ids.end(),
              [](const auto& a, const auto& b) { return a.second > b.second; });
    if (sorted_ids.size() > top_k)
        sorted_ids.resize(top_k);

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
            if (vector_store) {
                auto chunk = vector_store->get_chunk(id);
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

std::string build_context(const std::vector<SearchResult>& results, size_t max_context_tokens) {
    static constexpr size_t kCharsPerToken = 4;
    const size_t max_chars = max_context_tokens * kCharsPerToken;

    std::string context;
    for (size_t i = 0; i < results.size(); ++i) {
        const std::string& chunk_text = results[i].text;
        const size_t separator_len = (i > 0) ? 2 : 0;
        if (context.size() + separator_len + chunk_text.size() > max_chars) {
            LOGI("Context budget reached at chunk %zu/%zu (%zu chars, limit ~%zu)", i,
                 results.size(), context.size(), max_chars);
            break;
        }
        if (i > 0)
            context += "\n\n";
        context += chunk_text;
    }
    return context;
}

std::string format_prompt(const std::string& query, const std::string& context,
                          const std::string& tmpl) {
    static constexpr const char* kQueryPlaceholder = "{query}";
    static constexpr const char* kContextPlaceholder = "{context}";
    static constexpr size_t kQueryPlaceholderSize = 7;
    static constexpr size_t kContextPlaceholderSize = 9;

    std::string prompt;
    prompt.reserve(tmpl.size() + query.size() + context.size());

    for (size_t pos = 0; pos < tmpl.size();) {
        if (tmpl.compare(pos, kQueryPlaceholderSize, kQueryPlaceholder) == 0) {
            prompt.append(query);
            pos += kQueryPlaceholderSize;
        } else if (tmpl.compare(pos, kContextPlaceholderSize, kContextPlaceholder) == 0) {
            prompt.append(context);
            pos += kContextPlaceholderSize;
        } else {
            prompt.push_back(tmpl[pos]);
            ++pos;
        }
    }

    return prompt;
}

// ---------------------------------------------------------------------------
// Token sink helpers
// ---------------------------------------------------------------------------

struct LLMStreamCtx {
    std::string* accumulated_answer;
    const RAGTokenSink* on_token;
};

rac_bool_t llm_stream_trampoline(const char* token, void* user_data) {
    auto* ctx = static_cast<LLMStreamCtx*>(user_data);
    if (!token || !ctx)
        return RAC_TRUE;

    const std::string s(token);
    ctx->accumulated_answer->append(s);

    if (ctx->on_token && *ctx->on_token) {
        const bool keep_going = (*ctx->on_token)(s);
        if (!keep_going) {
            return RAC_FALSE;
        }
    }
    return RAC_TRUE;
}

}  // namespace

// ---------------------------------------------------------------------------
// run_rag_query — run embed → retrieve → assemble → LLM once, then return the result.
// ---------------------------------------------------------------------------

rac_result_t run_rag_query(const RAGGraphInputs& inputs, RAGTokenSink on_token,
                           RAGGraphResult& out_result) {
    out_result = RAGGraphResult{};

    if (!inputs.embeddings_service || !inputs.llm_service || !inputs.vector_store) {
        LOGE("run_rag_query: missing embeddings/llm/vector_store handle");
        return RAC_ERROR_INVALID_STATE;
    }

    const std::string question = inputs.question;
    const rac_handle_t embeddings_handle = inputs.embeddings_service;
    const rac_handle_t llm_handle = inputs.llm_service;
    const VectorStoreUSearch* vstore = inputs.vector_store;
    const BM25Index* bm25 = inputs.bm25_index;
    const size_t embed_dim = inputs.embedding_dimension;
    const size_t top_k = inputs.top_k;
    const size_t max_ctx_tokens = inputs.max_context_tokens;
    const std::string prompt_tmpl = inputs.prompt_template;
    rac_llm_options_t llm_options = inputs.llm_options;
    const std::string sys_prompt = inputs.system_prompt;
    if (!llm_options.system_prompt && !sys_prompt.empty()) {
        llm_options.system_prompt = sys_prompt.c_str();
    }

    rac_embeddings_result_t embedding_result = {};
    rac_result_t status =
        rac_embeddings_embed(embeddings_handle, question.c_str(), nullptr, &embedding_result);
    if (status != RAC_SUCCESS || embedding_result.num_embeddings == 0 ||
        !embedding_result.embeddings) {
        LOGE("RAG embed failed (%d)", status);
        rac_embeddings_result_free(&embedding_result);
        out_result.status = (status != RAC_SUCCESS) ? status : RAC_ERROR_PROCESSING_FAILED;
        return out_result.status;
    }

    std::vector<float> query_embedding(embedding_result.embeddings[0].data,
                                       embedding_result.embeddings[0].data +
                                           embedding_result.embeddings[0].dimension);
    rac_embeddings_result_free(&embedding_result);

    if (query_embedding.size() != embed_dim) {
        LOGE("RAG embed dim mismatch (%zu vs %zu)", query_embedding.size(), embed_dim);
        out_result.status = RAC_ERROR_PROCESSING_FAILED;
        return out_result.status;
    }

    std::vector<SearchResult> results;
    try {
        // Candidate gathering must not apply an absolute cosine floor: all-MiniLM
        // scores are low/near-zero even for relevant chunks, so any floor drops
        // real matches (a multi-chunk doc then retrieves nothing -> "no info").
        // Gather top_k and let fusion/rerank select; the configured
        // similarity_threshold is intentionally ignored for gathering.
        auto dense_results = vstore->search(query_embedding, top_k, 0.0f);
        std::vector<std::pair<std::string, float>> bm25_results;
        if (bm25) {
            bm25_results = bm25->search(question, top_k);
        }

        results = fuse_results(dense_results, bm25_results, vstore, top_k);
        LOGI("RAG retrieve: %zu dense, %zu bm25, %zu fused", dense_results.size(),
             bm25_results.size(), results.size());
    } catch (const std::exception& e) {
        LOGE("RAG retrieve failed: %s", e.what());
        out_result.status = RAC_ERROR_PROCESSING_FAILED;
        return out_result.status;
    }

    if (results.empty()) {
        out_result.answer = "I don't have enough information to answer that question.";
        return RAC_SUCCESS;
    }

    out_result.assembled_context = build_context(results, max_ctx_tokens);
    const std::string prompt = format_prompt(question, out_result.assembled_context, prompt_tmpl);
    out_result.sources = std::move(results);

    LOGI("RAG assemble: built prompt, %zu chars context, %zu sources",
         out_result.assembled_context.size(), out_result.sources.size());

    if (!prompt.empty()) {
        LLMStreamCtx ctx{&out_result.answer, &on_token};
        status = rac_llm_generate_stream(llm_handle, prompt.c_str(), &llm_options,
                                         llm_stream_trampoline, &ctx);
        if (status != RAC_SUCCESS) {
            LOGE("RAG LLM generate_stream failed (%d)", status);
            out_result.status = status;
            return out_result.status;
        }
    }

    return out_result.status;
}

}  // namespace runanywhere::rag
