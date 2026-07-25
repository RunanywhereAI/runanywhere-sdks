/**
 * @file cmd_rag.cpp
 * @brief `rcli rag query` — retrieval-augmented generation via the commons
 *        RAG session ABI.
 *
 * Single-shot flow in one process (the CLI is stateless across invocations and
 * RAG indexes are in-memory only):
 *   rac_rag_session_create_proto(RAGConfiguration)   → session handle
 *     → rac_rag_ingest_proto(RAGDocument) per --doc / --file
 *     → rac_rag_query_proto(RAGQueryOptions)          → RAGResult
 *   rac_rag_session_destroy_proto(session)
 *
 * Commons resolves the embedding + LLM model ids to filesystem paths via the
 * model registry and owns the full embed → retrieve → generate pipeline; this
 * command only translates argv to the rac_rag_* C ABI and renders the result.
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

int run_rag_query(const GlobalOptions& options, const std::string& llm_model,
                  const std::string& embed_model, const std::vector<std::string>& docs,
                  const std::vector<std::string>& files, const std::string& question,
                  int top_k, int max_tokens, float temperature) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    if (question.empty()) {
        out::error_line("a question is required (positional argument)");
        return 2;
    }

    std::vector<std::string> documents = docs;
    for (const auto& path : files) {
        std::string content;
        std::string error;
        if (!read_text_file(path, &content, &error)) {
            out::error_line(error);
            return 2;
        }
        documents.push_back(content);
    }
    if (documents.empty()) {
        out::error_line("at least one document is required (--doc or --file)");
        return 2;
    }

    // Both models must already be downloaded — the session resolves them from
    // the registry. (Pull them first with `rcli pull <id>` if missing.)
    // Create the RAG session.
    v1::RAGConfiguration config;
    config.set_embedding_model_id(embed_model);
    config.set_llm_model_id(llm_model);
    if (top_k > 0) {
        config.set_top_k(top_k);
    }

    const std::string config_bytes = proto::serialize(config);
    rac_handle_t session = nullptr;
    if (rac_rag_session_create_proto(reinterpret_cast<const uint8_t*>(config_bytes.data()),
                                     config_bytes.size(), &session) != RAC_SUCCESS ||
        session == nullptr) {
        out::error_line("RAG session create failed (check that '" + embed_model + "' and '" +
                        llm_model + "' are downloaded)");
        return 1;
    }

    // Ingest each document.
    std::string error;
    for (size_t i = 0; i < documents.size(); ++i) {
        v1::RAGDocument document;
        document.set_id("doc-" + std::to_string(i));
        document.set_text(documents[i]);
        const std::string doc_bytes = proto::serialize(document);
        rac_proto_buffer_t stats_buffer;
        rac_proto_buffer_init(&stats_buffer);
        v1::RAGStatistics stats;
        if (rac_rag_ingest_proto(session, reinterpret_cast<const uint8_t*>(doc_bytes.data()),
                                 doc_bytes.size(), &stats_buffer) != RAC_SUCCESS ||
            !proto::parse_proto_buffer(&stats_buffer, &stats, &error)) {
            out::error_line("RAG ingest failed: " + error);
            rac_rag_session_destroy_proto(session);
            return 1;
        }
        if (options.verbose) {
            out::status_line("ingested doc-" + std::to_string(i) + " (" +
                             std::to_string(documents[i].size()) + " bytes)");
        }
    }

    // Query.
    v1::RAGQueryOptions query;
    query.set_question(question);
    if (max_tokens > 0) {
        query.set_max_tokens(max_tokens);
    }
    if (temperature >= 0.0f) {
        query.set_temperature(temperature);
    }
    if (top_k > 0) {
        query.set_retrieval_top_k(top_k);
    }

    const std::string query_bytes = proto::serialize(query);
    rac_proto_buffer_t result_buffer;
    rac_proto_buffer_init(&result_buffer);
    v1::RAGResult result;
    if (rac_rag_query_proto(session, reinterpret_cast<const uint8_t*>(query_bytes.data()),
                            query_bytes.size(), &result_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&result_buffer, &result, &error)) {
        out::error_line("RAG query failed: " + error);
        rac_rag_session_destroy_proto(session);
        return 1;
    }

    if (result.error_code() != 0 || result.has_error_message()) {
        out::error_line("RAG query failed: " + (result.error_message().empty()
                                                    ? std::to_string(result.error_code())
                                                    : result.error_message()));
        rac_rag_session_destroy_proto(session);
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("answer", result.answer())
            .field("retrieved_chunks", static_cast<int64_t>(result.retrieved_chunks_size()))
            .field("retrieval_time_ms", static_cast<int64_t>(result.retrieval_time_ms()))
            .field("generation_time_ms", static_cast<int64_t>(result.generation_time_ms()))
            .field("total_time_ms", static_cast<int64_t>(result.total_time_ms()))
            .field("prompt_tokens", static_cast<int64_t>(result.prompt_tokens()))
            .field("completion_tokens", static_cast<int64_t>(result.completion_tokens()));
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

}  // namespace

void register_rag(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("rag", "Retrieval-augmented generation");
    CLI::App* query_cmd = cmd->add_subcommand("query", "Ingest documents and answer a question");

    auto question = std::make_shared<std::string>();
    auto docs = std::make_shared<std::vector<std::string>>();
    auto files = std::make_shared<std::vector<std::string>>();
    auto llm_model = std::make_shared<std::string>(kDefaultRagLlm);
    auto embed_model = std::make_shared<std::string>(kDefaultRagEmbed);
    auto top_k = std::make_shared<int>(0);
    auto max_tokens = std::make_shared<int>(0);
    auto temperature = std::make_shared<float>(-1.0f);

    query_cmd->add_option("question", *question, "Question to answer over the ingested documents")
        ->required();
    query_cmd->add_option("--doc,-d", *docs, "Inline document text (repeat for multiple)");
    query_cmd->add_option("--file,-f", *files, "Path to a text file to ingest (repeat for multiple)");
    query_cmd->add_option("--llm", *llm_model, "LLM model id (default: " + std::string(kDefaultRagLlm) + ")")
        ->default_val(kDefaultRagLlm);
    query_cmd->add_option("--embed", *embed_model,
                          "Embedding model id (default: " + std::string(kDefaultRagEmbed) + ")")
        ->default_val(kDefaultRagEmbed);
    query_cmd->add_option("--top-k", *top_k, "Number of chunks to retrieve");
    query_cmd->add_option("--max-tokens", *max_tokens, "Max answer tokens");
    query_cmd->add_option("--temperature", *temperature, "Sampling temperature");

    query_cmd->callback([&options, question, docs, files, llm_model, embed_model, top_k, max_tokens,
                         temperature]() {
        const int exit_code = run_rag_query(options, *llm_model, *embed_model, *docs, *files,
                                            *question, *top_k, *max_tokens, *temperature);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands

#endif  // RAC_HAVE_RAG
