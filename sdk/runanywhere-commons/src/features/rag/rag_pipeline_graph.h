/**
 * @file rag_pipeline_graph.h
 * @brief RAG query orchestration as a GraphScheduler-driven DAG.
 *
 * Second real consumer of the streaming graph runtime
 * after the unit-test suite. Replaces the old hand-rolled imperative
 * `RAGBackend::query()` step-by-step orchestration with a typed DAG:
 *
 *     Query(string)
 *         → Embed(string -> vector<float>)
 *         → Retrieve(embedding + query -> chunks)
 *         → ContextAssembly(chunks + query -> prompt)
 *         → LLM(prompt -> tokens)
 *
 * The graph is built per query: nodes are created, the scheduler is
 * started, the question is pushed, the input edge is closed, every node
 * drains, the scheduler joins, and tokens are forwarded to the caller's
 * callback as they stream out of the LLM node.
 *
 * Rerank: optional LLM-pointwise stage between Retrieve and ContextAssembly,
 * enabled per query via RAGGraphInputs::rerank. Fused candidates are scored
 * 1-5 for relevance by the same LLM handle used for generation (no
 * cross-encoder — the `RAC_PRIMITIVE_RERANK` primitive / `rerank_ops` vtable
 * slot were removed in plugin ABI v4) and reordered before context assembly.
 * Any failure falls back to the fused order.
 */

#ifndef RUNANYWHERE_RAG_PIPELINE_GRAPH_H
#define RUNANYWHERE_RAG_PIPELINE_GRAPH_H

#include "vector_store_usearch.h"

#include <functional>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_types.h"

namespace runanywhere {
namespace rag {

class BM25Index;
class VectorStoreUSearch;

/**
 * @brief Per-query inputs for the RAG graph.
 *
 * All pointer/handle fields are borrowed — they must outlive `run_rag_query()`
 * but the graph does NOT take ownership.
 */
struct RAGGraphInputs {
    rac_handle_t llm_service = nullptr;
    rac_handle_t embeddings_service = nullptr;
    const VectorStoreUSearch* vector_store = nullptr;
    const BM25Index* bm25_index = nullptr;

    std::string question;
    rac_llm_options_t llm_options{};
    std::string system_prompt;
    std::string prompt_template;

    size_t embedding_dimension = 384;
    size_t top_k = 10;
    float similarity_threshold = 0.0f;
    size_t max_context_tokens = 2048;

    // When true, fused candidates are reranked by LLM-pointwise relevance
    // scoring (reusing llm_service) before context assembly.
    bool rerank = false;

    // Multi-query expansion: rewrite the question into `multi_query_count`
    // variants (via llm_service), retrieve for each, RRF-fuse all rankings.
    bool enable_multi_query = false;
    size_t multi_query_count = 3;

    // Scoped retrieval: only chunks whose document_id starts with this prefix
    // are eligible. Empty = whole index.
    std::string scope_prefix;
};

/**
 * @brief Output of a single RAG query.
 *
 * `answer` accumulates the streamed tokens (always populated, even when
 * the caller also receives them through the callback). `sources` mirrors
 * the chunks that fed the prompt. `status` carries the first non-success
 * result code seen by any node.
 */
struct RAGGraphResult {
    std::string answer;
    std::string assembled_context;
    std::vector<SearchResult> sources;
    rac_result_t status = RAC_SUCCESS;
};

/**
 * @brief Token sink invoked once per LLM token as it streams out of the
 *        LLM node. Return false to request cancellation.
 */
using RAGTokenSink = std::function<bool(const std::string& token)>;

/**
 * @brief Run a single RAG query through a GraphScheduler-driven DAG.
 *
 * Constructs nodes for embed / retrieve / context-assembly / LLM, wires
 * them with bounded backpressured edges, drives one question through,
 * and joins the scheduler. Streaming tokens from the LLM node are
 * forwarded to `on_token` (if non-null) and accumulated into
 * `out_result.answer`.
 *
 * Thread-safety: the function itself is reentrant (each call owns its
 * own scheduler + nodes). Concurrent callers must ensure the borrowed
 * vector store / BM25 index / service handles tolerate parallel access.
 *
 * @return RAC_SUCCESS on success; first failure status otherwise.
 */
rac_result_t run_rag_query(const RAGGraphInputs& inputs, RAGTokenSink on_token,
                           RAGGraphResult& out_result);

}  // namespace rag
}  // namespace runanywhere

#endif  // RUNANYWHERE_RAG_PIPELINE_GRAPH_H
