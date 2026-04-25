/**
 * @file rag_pipeline_graph.cpp
 * @brief GraphScheduler-driven implementation of the RAG query DAG.
 *
 * See rag_pipeline_graph.h for the high-level shape. This file owns the
 * node lambdas (embed/retrieve/assemble/llm) and the per-query
 * scheduler lifecycle.
 */

#include "rag_pipeline_graph.h"

#include <algorithm>
#include <atomic>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
#include <utility>

#include "bm25_index.h"
#include "rac/core/rac_logger.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/graph/graph_scheduler.hpp"
#include "rac/graph/pipeline_node.hpp"
#include "rac/graph/stream_edge.hpp"
#include "vector_store_usearch.h"

#define LOG_TAG "RAG.Graph"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

namespace {

// ---------------------------------------------------------------------------
// Edge payloads
// ---------------------------------------------------------------------------

struct EmbeddedQuery {
    std::string text;
    std::vector<float> embedding;
};

struct RetrievedChunks {
    std::string query_text;
    std::vector<SearchResult> results;
};

struct AssembledPrompt {
    std::string prompt;
    std::string context_used;
    std::vector<SearchResult> sources;
};

// Shared state populated by the LLM sink and read after the graph joins.
struct GraphSinkState {
    std::mutex mu;
    std::string accumulated_answer;
    std::vector<SearchResult> sources;
    std::string assembled_context;
    rac_result_t status{RAC_SUCCESS};
    std::atomic<bool> cancel_requested{false};
};

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

    if (bm25_results.empty()) return dense_results;

    const size_t missing_rank = top_k + 1;

    std::unordered_map<std::string, float> rrf_scores;
    for (size_t i = 0; i < dense_results.size(); ++i) {
        rrf_scores[dense_results[i].id] +=
            1.0f / (kRRFConstant + static_cast<float>(i + 1));
    }
    for (size_t i = 0; i < bm25_results.size(); ++i) {
        rrf_scores[bm25_results[i].first] +=
            1.0f / (kRRFConstant + static_cast<float>(i + 1));
    }

    const float missing_score =
        1.0f / (kRRFConstant + static_cast<float>(missing_rank));

    std::unordered_set<std::string> dense_ids;
    for (const auto& r : dense_results) dense_ids.insert(r.id);
    std::unordered_set<std::string> bm25_ids;
    for (const auto& r : bm25_results) bm25_ids.insert(r.first);

    for (auto& [id, score] : rrf_scores) {
        if (dense_ids.find(id) == dense_ids.end()) score += missing_score;
        if (bm25_ids.find(id) == bm25_ids.end()) score += missing_score;
    }

    std::unordered_map<std::string, const SearchResult*> dense_map;
    for (const auto& r : dense_results) dense_map[r.id] = &r;

    std::vector<std::pair<std::string, float>> sorted_ids;
    sorted_ids.reserve(rrf_scores.size());
    for (const auto& [id, score] : rrf_scores) sorted_ids.emplace_back(id, score);
    std::sort(sorted_ids.begin(), sorted_ids.end(),
              [](const auto& a, const auto& b) { return a.second > b.second; });
    if (sorted_ids.size() > top_k) sorted_ids.resize(top_k);

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

std::string build_context(const std::vector<SearchResult>& results,
                          size_t max_context_tokens) {
    static constexpr size_t kCharsPerToken = 4;
    const size_t max_chars = max_context_tokens * kCharsPerToken;

    std::string context;
    for (size_t i = 0; i < results.size(); ++i) {
        const std::string& chunk_text = results[i].text;
        const size_t separator_len = (i > 0) ? 2 : 0;
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

std::string format_prompt(const std::string& query, const std::string& context,
                          const std::string& tmpl) {
    std::string prompt = tmpl;
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

// ---------------------------------------------------------------------------
// Token sink helpers
// ---------------------------------------------------------------------------

struct LLMStreamCtx {
    GraphSinkState* state;
    const RAGTokenSink* on_token;
};

rac_bool_t llm_stream_trampoline(const char* token, void* user_data) {
    auto* ctx = static_cast<LLMStreamCtx*>(user_data);
    if (!token || !ctx) return RAC_TRUE;

    const std::string s(token);
    {
        std::lock_guard<std::mutex> lock(ctx->state->mu);
        ctx->state->accumulated_answer.append(s);
    }

    if (ctx->on_token && *ctx->on_token) {
        const bool keep_going = (*ctx->on_token)(s);
        if (!keep_going) {
            ctx->state->cancel_requested.store(true, std::memory_order_release);
            return RAC_FALSE;
        }
    }
    return RAC_TRUE;
}

}  // namespace

// ---------------------------------------------------------------------------
// run_rag_query — assemble a 4-node DAG, run it once, return the result.
// ---------------------------------------------------------------------------

rac_result_t run_rag_query(const RAGGraphInputs& inputs, RAGTokenSink on_token,
                           RAGGraphResult& out_result) {
    out_result = RAGGraphResult{};

    if (!inputs.embeddings_service || !inputs.llm_service || !inputs.vector_store) {
        LOGE("run_rag_query: missing embeddings/llm/vector_store handle");
        return RAC_ERROR_INVALID_STATE;
    }

    auto state = std::make_shared<GraphSinkState>();
    auto sink_callback = std::make_shared<RAGTokenSink>(std::move(on_token));

    using rac::graph::GraphScheduler;
    using rac::graph::make_primitive_node;
    using rac::graph::OverflowPolicy;
    using rac::graph::StreamEdge;

    // Capture-by-value of all inputs needed by each node — `inputs` may
    // reference stack memory that could be reused after we return, so
    // copy the small fields. Pointers (vector_store, bm25_index, service
    // handles) are borrowed for the call duration; the caller guarantees
    // they outlive the scheduler join below.
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

    // -------------------- EmbedNode --------------------
    auto embed_node = make_primitive_node<std::string, EmbeddedQuery>(
        "RAG.Embed",
        [embeddings_handle, embed_dim, state](std::string text,
                                              StreamEdge<EmbeddedQuery>& out) {
            rac_embeddings_result_t result = {};
            rac_result_t status = rac_embeddings_embed(embeddings_handle, text.c_str(),
                                                       nullptr, &result);
            if (status != RAC_SUCCESS || result.num_embeddings == 0 ||
                !result.embeddings) {
                LOGE("EmbedNode: embed failed (%d)", status);
                rac_embeddings_result_free(&result);
                std::lock_guard<std::mutex> lock(state->mu);
                if (state->status == RAC_SUCCESS) {
                    state->status = (status != RAC_SUCCESS)
                                        ? status
                                        : RAC_ERROR_PROCESSING_FAILED;
                }
                return;
            }

            EmbeddedQuery payload;
            payload.text = std::move(text);
            payload.embedding.assign(result.embeddings[0].data,
                                     result.embeddings[0].data +
                                         result.embeddings[0].dimension);
            rac_embeddings_result_free(&result);

            if (payload.embedding.size() != embed_dim) {
                LOGE("EmbedNode: dim mismatch (%zu vs %zu)",
                     payload.embedding.size(), embed_dim);
                std::lock_guard<std::mutex> lock(state->mu);
                if (state->status == RAC_SUCCESS) {
                    state->status = RAC_ERROR_PROCESSING_FAILED;
                }
                return;
            }
            out.push(std::move(payload));
        });

    // -------------------- RetrieveNode --------------------
    auto retrieve_node = make_primitive_node<EmbeddedQuery, RetrievedChunks>(
        "RAG.Retrieve",
        [vstore, bm25, top_k, sim_thresh, state](EmbeddedQuery in,
                                                 StreamEdge<RetrievedChunks>& out) {
            try {
                auto dense = vstore->search(in.embedding, top_k, sim_thresh);
                std::vector<std::pair<std::string, float>> bm25_results;
                if (bm25) bm25_results = bm25->search(in.text, top_k);

                RetrievedChunks payload;
                payload.query_text = std::move(in.text);
                payload.results = fuse_results(dense, bm25_results, vstore, top_k);
                LOGI("RetrieveNode: %zu dense, %zu bm25, %zu fused",
                     dense.size(), bm25_results.size(), payload.results.size());
                out.push(std::move(payload));
            } catch (const std::exception& e) {
                LOGE("RetrieveNode: %s", e.what());
                std::lock_guard<std::mutex> lock(state->mu);
                if (state->status == RAC_SUCCESS) {
                    state->status = RAC_ERROR_PROCESSING_FAILED;
                }
            }
        });

    // -------------------- ContextAssemblyNode --------------------
    auto assemble_node = make_primitive_node<RetrievedChunks, AssembledPrompt>(
        "RAG.Assemble",
        [max_ctx_tokens, prompt_tmpl,
         state](RetrievedChunks in, StreamEdge<AssembledPrompt>& out) {
            if (in.results.empty()) {
                std::lock_guard<std::mutex> lock(state->mu);
                state->accumulated_answer =
                    "I don't have enough information to answer that question.";
                // Leaving sources empty + status SUCCESS — caller treats this
                // as a graceful no-context response, matching legacy semantics.
                return;
            }

            AssembledPrompt payload;
            payload.context_used = build_context(in.results, max_ctx_tokens);
            payload.prompt =
                format_prompt(in.query_text, payload.context_used, prompt_tmpl);
            payload.sources = std::move(in.results);
            {
                std::lock_guard<std::mutex> lock(state->mu);
                state->sources = payload.sources;
                state->assembled_context = payload.context_used;
            }
            LOGI("AssembleNode: built prompt, %zu chars context, %zu sources",
                 payload.context_used.size(), payload.sources.size());
            out.push(std::move(payload));
        });

    // -------------------- LLMNode --------------------
    // We deliberately do NOT push tokens through the output edge here — the
    // streaming callback fires on every token from inside generate_stream and
    // accumulates into `state` directly. Pushing each token onto a typed edge
    // would add an extra hop without any real consumer downstream.
    auto llm_node = make_primitive_node<AssembledPrompt, std::string>(
        "RAG.LLM",
        [llm_handle, llm_options, sink_callback,
         state](AssembledPrompt in, StreamEdge<std::string>& /*out*/) {
            if (in.prompt.empty()) return;

            LLMStreamCtx ctx{state.get(), sink_callback.get()};
            rac_result_t status = rac_llm_generate_stream(
                llm_handle, in.prompt.c_str(), &llm_options, llm_stream_trampoline,
                &ctx);
            if (status != RAC_SUCCESS) {
                LOGE("LLMNode: generate_stream failed (%d)", status);
                std::lock_guard<std::mutex> lock(state->mu);
                if (state->status == RAC_SUCCESS) state->status = status;
            }
        });

    // -------------------- Wire + run --------------------
    GraphScheduler scheduler(/*thread_pool_size=*/4);
    scheduler.add_node(embed_node);
    scheduler.add_node(retrieve_node);
    scheduler.add_node(assemble_node);
    scheduler.add_node(llm_node);

    scheduler.connect(*embed_node, *retrieve_node);
    scheduler.connect(*retrieve_node, *assemble_node);
    scheduler.connect(*assemble_node, *llm_node);

    scheduler.start();

    {
        auto in = embed_node->input();
        in->push(question);
        in->close();
    }

    scheduler.wait();

    if (state->cancel_requested.load(std::memory_order_acquire)) {
        scheduler.cancel_all();
    }

    {
        std::lock_guard<std::mutex> lock(state->mu);
        out_result.answer = std::move(state->accumulated_answer);
        out_result.assembled_context = std::move(state->assembled_context);
        out_result.sources = std::move(state->sources);
        out_result.status = state->status;
    }

    return out_result.status;
}

}  // namespace rag
}  // namespace runanywhere
