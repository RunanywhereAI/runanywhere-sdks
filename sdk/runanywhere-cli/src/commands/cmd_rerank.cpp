/**
 * @file cmd_rerank.cpp
 * @brief `rcli rerank <query> --doc … ` — cross-encoder relevance scoring.
 *
 * Same component sequence the other model-backed commands use:
 *   ensure_model_ready (resolve + auto-pull + resolve paths)
 *     → rac_rerank_component_create / load_model
 *     → rac_rerank_component_rerank_proto(RerankRequest) → RerankResult
 *     → rac_rerank_component_destroy
 * Scoring and ordering belong to the engine; this file only translates argv to
 * proto bytes and renders the ranked list.
 */

#include "commands/commands.h"

#include <cstdio>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "rac/features/rerank/rac_rerank_component.h"
#include "rerank.pb.h"

#include "commands/model_setup.h"
#include "io/output.h"
#include "io/proto.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

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

int run_rerank(const GlobalOptions& options, const std::string& model_ref,
               const std::string& query, const std::vector<std::string>& docs,
               const std::vector<std::string>& files, int top_n) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }
    if (model_ref.empty()) {
        out::error_line("--model is required (a reranker model id or on-disk path)");
        return 2;
    }

    std::vector<std::string> documents = docs;
    for (const std::string& path : files) {
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

    ResolvedModelPaths model;
    const int setup = ensure_model_ready(options, model_ref, &model);
    if (setup != 0) {
        return setup;
    }

    rac_handle_t reranker = nullptr;
    if (rac_rerank_component_create(&reranker) != RAC_SUCCESS) {
        out::error_line("failed to create rerank component");
        return 1;
    }
    rac_result_t rc = rac_rerank_component_load_model(reranker, model.primary_path.c_str(),
                                                      model.model_id.c_str(),
                                                      model.display_name.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load reranker: " + out::describe_result(rc));
        rac_rerank_component_destroy(reranker);
        return 1;
    }

    v1::RerankRequest request;
    request.set_query(query);
    for (const std::string& document : documents) {
        request.add_documents(document);
    }
    if (top_n > 0) {
        request.mutable_options()->set_top_n(static_cast<uint32_t>(top_n));
    }

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    std::string error;
    v1::RerankResult result;
    if (rac_rerank_component_rerank_proto(reranker, reinterpret_cast<const uint8_t*>(bytes.data()),
                                          bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("rerank failed: " + error);
        rac_rerank_component_destroy(reranker);
        return 1;
    }
    rac_rerank_component_destroy(reranker);

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("model", result.model_id().empty() ? model.model_id : result.model_id())
            .field("processing_time_ms", static_cast<int64_t>(result.processing_time_ms()))
            .begin_array("results");
        // RerankScoredItem.rank is gone -- items() is already sorted by score
        // descending, so the loop position IS the rank (1-based for display).
        int rank = 0;
        for (const v1::RerankScoredItem& item : result.items()) {
            ++rank;
            json.begin_array_object()
                .field("index", static_cast<int64_t>(item.index()))
                .field("rank", static_cast<int64_t>(rank))
                .field("relevance_score", static_cast<double>(item.relevance_score()))
                .end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
        return 0;
    }

    std::vector<std::vector<std::string>> rows;
    int rank = 0;
    for (const v1::RerankScoredItem& item : result.items()) {
        ++rank;
        char score[32];
        std::snprintf(score, sizeof(score), "%.4f", static_cast<double>(item.relevance_score()));
        const size_t index = item.index();
        std::string preview = index < documents.size() ? documents[index] : std::string();
        if (preview.size() > 60) {
            preview = preview.substr(0, 57) + "...";
        }
        rows.push_back({std::to_string(rank), std::to_string(index), score, preview});
    }
    out::table({"RANK", "INDEX", "SCORE", "DOCUMENT"}, rows);
    return 0;
}

}  // namespace

void register_rerank(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("rerank", "Score documents against a query, best first");
    auto query = std::make_shared<std::string>();
    auto model = std::make_shared<std::string>();
    auto docs = std::make_shared<std::vector<std::string>>();
    auto files = std::make_shared<std::vector<std::string>>();
    auto top_n = std::make_shared<int>(0);
    cmd->add_option("query", *query, "Query the documents are scored against")->required();
    cmd->add_option("--model,-m", *model, "Reranker model id or on-disk path")->required();
    cmd->add_option("--doc,-d", *docs, "Document text to score; repeat for several");
    cmd->add_option("--file,-f", *files, "Text file to score; repeat for several");
    cmd->add_option("--top-n", *top_n, "Return only this many best matches");
    cmd->callback([&options, query, model, docs, files, top_n]() {
        const int exit_code = run_rerank(options, *model, *query, *docs, *files, *top_n);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
