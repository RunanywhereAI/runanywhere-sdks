/**
 * @file rag_pipeline_graph.cpp
 * @brief Sequential implementation of the RAG query pipeline.
 */

#include "rag_pipeline_graph.h"

#include "bm25_index.h"
#include "rag_fusion.h"
#include "rag_rerank.h"
#include "vector_store_usearch.h"

#include <algorithm>
#include <cctype>
#include <exception>
#include <unordered_map>
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

// Embed a single query string; returns an empty vector on failure.
std::vector<float> embed_one(rac_handle_t embeddings_handle, const std::string& text) {
    rac_embeddings_result_t er = {};
    const rac_result_t st = rac_embeddings_embed(embeddings_handle, text.c_str(), nullptr, &er);
    std::vector<float> v;
    if (st == RAC_SUCCESS && er.num_embeddings > 0 && er.embeddings) {
        v.assign(er.embeddings[0].data, er.embeddings[0].data + er.embeddings[0].dimension);
    }
    rac_embeddings_result_free(&er);
    return v;
}

// True when a chunk's document_id (ingest metadata) starts with `prefix`.
bool chunk_matches_scope(const VectorStoreUSearch* vstore, const std::string& id,
                         const std::string& prefix) {
    const auto chunk = vstore->get_chunk(id);
    if (!chunk)
        return false;
    const auto it = chunk->metadata.find("document_id");
    if (it == chunk->metadata.end() || !it->is_string())
        return false;
    const std::string doc = it->get<std::string>();
    return doc.size() >= prefix.size() && doc.compare(0, prefix.size(), prefix) == 0;
}

// Multi-query expansion: ask the answer LLM to rewrite the query into `count`
// alternative phrasings (port of ToolNeuron RagQueryRewriter). Returns [] on any
// failure so the caller falls back to the single original query.
std::vector<std::string> generate_query_variants(rac_handle_t llm_handle, const std::string& query,
                                                 size_t count) {
    std::vector<std::string> out;
    if (!llm_handle || query.empty() || count == 0)
        return out;

    const std::string prompt =
        "Rewrite the user's search query into " + std::to_string(count) +
        " distinct alternative phrasings that capture the same intent but use different words. "
        "Output exactly " +
        std::to_string(count) +
        " lines, each starting with '- '. No numbering, no commentary.\n\nQuery: " + query +
        "\n\nVariants:\n";

    rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
    opts.temperature = 0.0f;
    opts.max_tokens = 200;
    opts.system_prompt = nullptr;

    rac_llm_result_t r = {};
    if (rac_llm_generate(llm_handle, prompt.c_str(), &opts, &r) != RAC_SUCCESS || !r.text) {
        rac_llm_result_free(&r);
        return out;
    }
    const std::string text(r.text);
    rac_llm_result_free(&r);

    return parse_query_variants(text, query, count);
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
    const float sim_thresh = inputs.similarity_threshold;
    const size_t max_ctx_tokens = inputs.max_context_tokens;
    const std::string prompt_tmpl = inputs.prompt_template;
    rac_llm_options_t llm_options = inputs.llm_options;
    const std::string sys_prompt = inputs.system_prompt;
    if (!llm_options.system_prompt && !sys_prompt.empty()) {
        llm_options.system_prompt = sys_prompt.c_str();
    }

    // Query set: the original question plus, when enabled, LLM-generated
    // rewrites (multi-query expansion).
    std::vector<std::string> queries;
    queries.push_back(question);
    if (inputs.enable_multi_query) {
        auto variants = generate_query_variants(llm_handle, question, inputs.multi_query_count);
        LOGI("RAG multi-query: %zu variants", variants.size());
        for (auto& v : variants)
            queries.push_back(std::move(v));
    }

    // Under a scope filter, fetch a wider candidate pool per query so enough
    // survive the document_id-prefix filter to still fill top_k.
    const bool scoped = !inputs.scope_prefix.empty();
    const size_t fetch_k = scoped ? std::min<size_t>(top_k * 8, 200) : top_k;

    std::vector<SearchResult> results;
    rac_result_t status = RAC_SUCCESS;
    try {
        std::vector<std::vector<std::string>> rankings;
        bool embedded_any = false;
        for (size_t qi = 0; qi < queries.size(); ++qi) {
            const std::string& q = queries[qi];
            const std::vector<float> emb = embed_one(embeddings_handle, q);
            if (emb.size() != embed_dim) {
                // The original query MUST embed; variants may be skipped.
                if (qi == 0) {
                    LOGE("RAG embed failed/dim mismatch for primary query");
                    out_result.status = RAC_ERROR_PROCESSING_FAILED;
                    return out_result.status;
                }
                continue;
            }
            embedded_any = true;

            // Candidate gathering must never apply an absolute cosine floor:
            // gather top-k and let fusion + rerank select (real-RAG). all-MiniLM
            // scores are low/near-zero even for relevant chunks, so any floor
            // here silently drops real matches. The configured
            // similarity_threshold is intentionally ignored for gathering.
            auto dense = vstore->search(emb, fetch_k, 0.0f);
            LOGI("RAG dense: query %zu -> %zu candidates (cfg sim_thresh=%.3f ignored for gather)",
                 qi, dense.size(), sim_thresh);
            std::vector<std::string> dense_ids;
            for (const auto& d : dense) {
                if (!scoped || chunk_matches_scope(vstore, d.id, inputs.scope_prefix))
                    dense_ids.push_back(d.id);
            }
            if (!dense_ids.empty())
                rankings.push_back(std::move(dense_ids));

            if (bm25) {
                const auto bm = bm25->search(q, fetch_k);
                std::vector<std::string> bm_ids;
                for (const auto& [id, score] : bm) {
                    (void)score;
                    if (!scoped || chunk_matches_scope(vstore, id, inputs.scope_prefix))
                        bm_ids.push_back(id);
                }
                if (!bm_ids.empty())
                    rankings.push_back(std::move(bm_ids));
            }
        }
        (void)embedded_any;

        results = fuse_rankings(rankings, vstore, top_k);
        LOGI("RAG retrieve: %zu queries, %zu rankings, %zu fused%s", queries.size(),
             rankings.size(), results.size(), scoped ? " (scoped)" : "");

        if (inputs.rerank) {
            rerank_llm_pointwise(llm_handle, question, llm_options, results);
        }
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
