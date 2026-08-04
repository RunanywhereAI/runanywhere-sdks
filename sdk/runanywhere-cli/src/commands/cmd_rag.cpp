/**
 * @file cmd_rag.cpp
 * @brief `rcli rag query` / `rcli rag search` — retrieval-augmented generation
 *        via the commons RAG session ABI.
 *
 * Single-shot flow in one process (the CLI is stateless across invocations and
 * RAG indexes are in-memory only):
 *   rac_rag_session_create_proto(RAGConfiguration)   → session handle
 *     → rac_rag_ingest_proto(RAGDocument) per --doc / --file
 *     → rac_rag_query_proto(RAGQueryOptions)          → RAGResult
 *       or rac_rag_search_proto(RAGSearchRequest)     → RAGSearchResponse
 *   rac_rag_session_destroy_proto(session)
 *
 * Commons resolves the embedding (+ optional LLM) model ids to filesystem paths
 * via the model registry and owns the pipeline; this command only translates
 * argv to the rac_rag_* C ABI and renders the result.
 */

#include "commands/commands.h"

#if !defined(RAC_HAVE_RAG)

// The RAG pipeline is not folded into this binary (RAC_BACKEND_RAG=OFF, e.g. the
// Windows CLI preset), so the rac_rag_*_proto symbols are unavailable. Register
// no `rag` subcommand rather than fail to link.
namespace rcli::commands {

void register_rag(CLI::App& app, GlobalOptions& options) {
    (void)app;
    (void)options;
}

}  // namespace rcli::commands

#else

#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "rag.pb.h"
#include "rac/core/rac_core.h"
#include "rac/features/rag/rac_rag.h"

#include "io/output.h"
#include "io/proto.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

constexpr const char* kDefaultRagLlm = "smollm2-360m-q8_0";
constexpr const char* kDefaultRagEmbed = "all-minilm-l6-v2";

bool read_text_file(const std::string& path, std::string* out, std::string* error) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        *error = "cannot open file: " + path;
        return false;
    }
    std::ostringstream buffer;
    buffer << file.rdbuf();
    *out = buffer.str();
    return true;
}

struct RagParams {
    std::string llm_model = kDefaultRagLlm;
    std::string embed_model = kDefaultRagEmbed;
    std::vector<std::string> docs;
    std::vector<std::string> files;
    std::string system_prompt;
    int top_k = 0;
    int chunk_size = 0;
    int chunk_overlap = 0;
    int max_output_tokens = 0;
    float temperature = -1.0f;
    float similarity_threshold = -1.0f;
    bool require_llm = true;
};

// One session covers the whole invocation: open → ingest every document → ask
// or search. The CLI cannot split those verbs apart the way the SDK spec does
// because commons keeps RAG indexes in memory only
// (RAGConfiguration.index_path / persist_index are not honored).
bool collect_documents(const RagParams& params, std::vector<std::string>* documents) {
    *documents = params.docs;
    for (const auto& path : params.files) {
        std::string content;
        std::string error;
        if (!read_text_file(path, &content, &error)) {
            out::error_line(error);
            return false;
        }
        documents->push_back(content);
    }
    if (documents->empty()) {
        out::error_line("at least one document is required (--doc or --file)");
        return false;
    }
    return true;
}

bool open_and_ingest(const GlobalOptions& options, const RagParams& params,
                     const std::vector<std::string>& documents, rac_handle_t* session) {
    // Models must already be downloaded — the session resolves them from the
    // registry. (Pull them first with `rcli models download <id>`.)
    v1::RAGConfiguration config;
    config.set_embedding_model_id(params.embed_model);
    if (params.require_llm || !params.llm_model.empty()) {
        config.set_llm_model_id(params.llm_model);
    }
    if (params.top_k > 0) {
        config.set_top_k(params.top_k);
    }
    if (params.chunk_size > 0) {
        config.set_chunk_size(params.chunk_size);
    }
    if (params.chunk_overlap > 0) {
        config.set_chunk_overlap(params.chunk_overlap);
    }
    if (params.similarity_threshold >= 0.0f) {
        config.set_similarity_threshold(params.similarity_threshold);
    }

    const std::string config_bytes = proto::serialize(config);
    if (rac_rag_session_create_proto(reinterpret_cast<const uint8_t*>(config_bytes.data()),
                                     config_bytes.size(), session) != RAC_SUCCESS ||
        *session == nullptr) {
        if (params.require_llm || !params.llm_model.empty()) {
            out::error_line("RAG session create failed (check that '" + params.embed_model +
                            "' and '" + params.llm_model + "' are downloaded)");
        } else {
            out::error_line("RAG session create failed (check that '" + params.embed_model +
                            "' is downloaded)");
        }
        return false;
    }

    std::string error;
    for (size_t i = 0; i < documents.size(); ++i) {
        v1::RAGDocument document;
        document.set_id("doc-" + std::to_string(i));
        document.set_text(documents[i]);
        const std::string doc_bytes = proto::serialize(document);
        rac_proto_buffer_t stats_buffer;
        rac_proto_buffer_init(&stats_buffer);
        v1::RAGStatistics stats;
        if (rac_rag_ingest_proto(*session, reinterpret_cast<const uint8_t*>(doc_bytes.data()),
                                 doc_bytes.size(), &stats_buffer) != RAC_SUCCESS ||
            !proto::parse_proto_buffer(&stats_buffer, &stats, &error)) {
            out::error_line("RAG ingest failed: " + error);
            rac_rag_session_destroy_proto(*session);
            *session = nullptr;
            return false;
        }
        if (options.verbose) {
            out::status_line("ingested doc-" + std::to_string(i) + " (" +
                             std::to_string(documents[i].size()) + " bytes)");
        }
    }
    return true;
}

int run_rag_query(const GlobalOptions& options, const RagParams& params,
                  const std::string& question) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    if (question.empty()) {
        out::error_line("a question is required (positional argument)");
        return 2;
    }

    std::vector<std::string> documents;
    if (!collect_documents(params, &documents)) {
        return 2;
    }

    rac_handle_t session = nullptr;
    if (!open_and_ingest(options, params, documents, &session)) {
        return 1;
    }

    v1::RAGQueryOptions query;
    query.set_question(question);
    if (params.max_output_tokens > 0) {
        query.mutable_generation()->set_max_output_tokens(params.max_output_tokens);
    }
    if (params.temperature >= 0.0f) {
        query.mutable_generation()->set_temperature(params.temperature);
    }
    if (!params.system_prompt.empty()) {
        query.mutable_generation()->set_system_prompt(params.system_prompt);
    }
    if (params.similarity_threshold >= 0.0f) {
        query.set_similarity_threshold(params.similarity_threshold);
    }
    if (params.top_k > 0) {
        query.set_retrieval_top_k(params.top_k);
    }

    const std::string query_bytes = proto::serialize(query);
    rac_proto_buffer_t result_buffer;
    rac_proto_buffer_init(&result_buffer);
    v1::RAGResult result;
    std::string error;
    if (rac_rag_query_proto(session, reinterpret_cast<const uint8_t*>(query_bytes.data()),
                            query_bytes.size(), &result_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&result_buffer, &result, &error)) {
        out::error_line("RAG query failed: " + error);
        rac_rag_session_destroy_proto(session);
        return 1;
    }

    if (result.has_error()) {
        out::error_line("RAG query failed: " + (result.error().message().empty()
                                                    ? std::to_string(result.error().c_abi_code())
                                                    : result.error().message()));
        rac_rag_session_destroy_proto(session);
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("answer", result.answer())
            .field("retrieval_time_ms", static_cast<int64_t>(result.retrieval_time_ms()))
            .field("generation_time_ms", static_cast<int64_t>(result.generation_time_ms()))
            .field("total_time_ms", static_cast<int64_t>(result.total_time_ms()))
            .field("prompt_tokens", static_cast<int64_t>(result.usage().input_tokens()))
            .field("completion_tokens", static_cast<int64_t>(result.usage().output_tokens()));
        json.begin_array("matches");
        for (const v1::RAGSearchResult& match : result.retrieved_chunks()) {
            json.begin_array_object()
                .field("text", match.text())
                .field("score", static_cast<double>(match.similarity_score()))
                .field("source", match.source_document())
                .end_object();
        }
        json.end_array();
        out::result_line(json.end_object().str());
    } else {
        out::result_line(result.answer());
        if (options.verbose) {
            out::status_line("chunks=" + std::to_string(result.retrieved_chunks_size()) +
                             " retrieval=" + std::to_string(result.retrieval_time_ms()) + "ms" +
                             " generation=" + std::to_string(result.generation_time_ms()) + "ms");
        }
    }

    rac_rag_session_destroy_proto(session);
    return 0;
}

int run_rag_search(const GlobalOptions& options, const RagParams& params,
                   const std::string& question) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    if (question.empty()) {
        out::error_line("a question is required (positional argument)");
        return 2;
    }

    std::vector<std::string> documents;
    if (!collect_documents(params, &documents)) {
        return 2;
    }

    rac_handle_t session = nullptr;
    if (!open_and_ingest(options, params, documents, &session)) {
        return 1;
    }

    v1::RAGSearchRequest request;
    request.set_question(question);
    if (params.top_k > 0) {
        request.set_retrieval_top_k(params.top_k);
    }
    if (params.similarity_threshold >= 0.0f) {
        request.set_similarity_threshold(params.similarity_threshold);
    }

    const std::string request_bytes = proto::serialize(request);
    rac_proto_buffer_t response_buffer;
    rac_proto_buffer_init(&response_buffer);
    v1::RAGSearchResponse response;
    std::string error;
    if (rac_rag_search_proto(session, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                             request_bytes.size(), &response_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&response_buffer, &response, &error)) {
        out::error_line("RAG search failed: " + error);
        rac_rag_session_destroy_proto(session);
        return 1;
    }

    if (response.has_error()) {
        out::error_line("RAG search failed: " + (response.error().message().empty()
                                                     ? std::to_string(response.error().c_abi_code())
                                                     : response.error().message()));
        rac_rag_session_destroy_proto(session);
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("retrieval_time_ms", static_cast<int64_t>(response.retrieval_time_ms()))
            .field("request_id", response.request_id());
        json.begin_array("matches");
        for (const v1::RAGSearchResult& match : response.chunks()) {
            json.begin_array_object()
                .field("text", match.text())
                .field("score", static_cast<double>(match.similarity_score()))
                .field("source", match.source_document())
                .end_object();
        }
        json.end_array();
        out::result_line(json.end_object().str());
    } else {
        for (const v1::RAGSearchResult& match : response.chunks()) {
            out::result_line(match.text());
        }
        if (options.verbose) {
            out::status_line("chunks=" + std::to_string(response.chunks_size()) +
                             " retrieval=" + std::to_string(response.retrieval_time_ms()) + "ms");
        }
    }

    rac_rag_session_destroy_proto(session);
    return 0;
}

}  // namespace

namespace {

// Corpus and retrieval flags are the same for search and query; only `query`
// generates an answer, so only it takes the generation knobs.
void add_corpus_options(CLI::App* cmd, const std::shared_ptr<RagParams>& params) {
    cmd->add_option("--doc,-d", params->docs, "Document text to index; repeat for several");
    cmd->add_option("--file,-f", params->files, "Text file to index; repeat for several");
    cmd->add_option("--embedding-model,--embed", params->embed_model,
                    "Embedding model to index with (default: " + std::string(kDefaultRagEmbed) +
                        ")");
    cmd->add_option("--top-k", params->top_k, "Retrieve this many chunks per question");
    cmd->add_option("--chunk-size", params->chunk_size,
                    "Tokens per chunk when splitting documents");
    cmd->add_option("--chunk-overlap", params->chunk_overlap,
                    "Tokens shared between neighbouring chunks");
    cmd->add_option("--similarity-threshold", params->similarity_threshold,
                    "Discard chunks scoring below this");
}

}  // namespace

void register_rag(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("rag", "Answer questions over your own documents");
    cmd->require_subcommand(1);

    CLI::App* query_cmd = cmd->add_subcommand("query", "Answer a question from the documents");
    auto question = std::make_shared<std::string>();
    auto params = std::make_shared<RagParams>();
    query_cmd->add_option("question", *question, "Question to answer over the documents")
        ->required();
    add_corpus_options(query_cmd, params);
    query_cmd->add_option("--model,--llm", params->llm_model,
                          "LLM that writes the answer (default: " + std::string(kDefaultRagLlm) +
                              ")");
    query_cmd->add_option("--system-prompt", params->system_prompt,
                          "Steer the answer with a system instruction");
    query_cmd->add_option("--max-output-tokens,--max-tokens", params->max_output_tokens,
                          "Cap the answer length in tokens");
    query_cmd->add_option("--temperature", params->temperature,
                          "Raise for more random sampling");

    query_cmd->callback([&options, question, params]() {
        const int exit_code = run_rag_query(options, *params, *question);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });

    CLI::App* search_cmd =
        cmd->add_subcommand("search", "Retrieve matching chunks without generating an answer");
    auto search_question = std::make_shared<std::string>();
    auto search_params = std::make_shared<RagParams>();
    search_params->llm_model.clear();  // retrieval-only unless --model/--llm is passed
    search_params->require_llm = false;
    search_cmd->add_option("question", *search_question, "Query to retrieve chunks for")
        ->required();
    add_corpus_options(search_cmd, search_params);
    search_cmd->add_option("--model,--llm", search_params->llm_model,
                           "Optional LLM (needed only for multi-query / session rerank)");

    search_cmd->callback([&options, search_question, search_params]() {
        const int exit_code = run_rag_search(options, *search_params, *search_question);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands

#endif  // RAC_HAVE_RAG
