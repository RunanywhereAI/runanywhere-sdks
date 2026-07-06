/**
 * @file cmd_embed.cpp
 * @brief `rcli embed [model] <text>` — text embeddings via the embeddings
 *        component.
 */

#include "commands/commands.h"

#include <algorithm>
#include <chrono>
#include <iomanip>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "rac/features/embeddings/rac_embeddings_component.h"

#include "commands/model_setup.h"
#include "io/output.h"

namespace rcli::commands {

namespace {

constexpr const char* kDefaultEmbeddingModel = "minilm";

std::string values_json(const rac_embedding_vector_t& vector) {
    std::ostringstream out;
    out << std::setprecision(8) << '[';
    const size_t count = vector.data ? vector.dimension : 0;
    for (size_t i = 0; i < count; ++i) {
        if (i > 0) {
            out << ',';
        }
        out << vector.data[i];
    }
    out << ']';
    return out.str();
}

std::string preview_values(const rac_embedding_vector_t& vector) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(5);
    const size_t count = vector.data ? std::min<size_t>(vector.dimension, 8) : 0;
    for (size_t i = 0; i < count; ++i) {
        if (i > 0) {
            out << ',';
        }
        out << vector.data[i];
    }
    return out.str();
}

void print_json_result(const ResolvedModelPaths& model, const std::vector<std::string>& texts,
                       const rac_embeddings_result_t& result, int64_t elapsed_ms) {
    std::ostringstream json;
    json << "{\"model\":\"" << out::json_escape(model.model_id) << "\",";
    json << "\"dimension\":" << static_cast<int64_t>(result.dimension) << ',';
    json << "\"count\":" << static_cast<int64_t>(result.num_embeddings) << ',';
    json << "\"tokens_used\":" << static_cast<int64_t>(result.total_tokens) << ',';
    json << "\"total_ms\":" << elapsed_ms << ',';
    json << "\"vectors\":[";
    for (size_t i = 0; i < result.num_embeddings; ++i) {
        if (i > 0) {
            json << ',';
        }
        const auto& vector = result.embeddings[i];
        const std::string text = i < texts.size() ? texts[i] : std::string();
        json << "{\"text\":\"" << out::json_escape(text) << "\",";
        json << "\"dimension\":" << static_cast<int64_t>(vector.dimension) << ',';
        json << "\"values\":" << values_json(vector) << '}';
    }
    json << "]}";
    out::result_line(json.str());
}

void print_text_result(const ResolvedModelPaths& model, const rac_embeddings_result_t& result,
                       int64_t elapsed_ms, bool verbose) {
    out::result_line("model\t" + model.model_id);
    out::result_line("dimension\t" + std::to_string(result.dimension));
    out::result_line("count\t" + std::to_string(result.num_embeddings));
    for (size_t i = 0; i < result.num_embeddings; ++i) {
        out::result_line("vector[" + std::to_string(i) + "]\t" +
                         preview_values(result.embeddings[i]));
    }
    if (verbose) {
        out::status_line("(" + std::to_string(elapsed_ms) + " ms)");
    }
}

int run_embed(const GlobalOptions& options, const std::string& ref,
              const std::vector<std::string>& texts) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    if (texts.empty()) {
        out::error_line("at least one text input is required");
        return 2;
    }

    ResolvedModelPaths model;
    const int setup =
        ensure_model_ready(options, ref.empty() ? kDefaultEmbeddingModel : ref, &model);
    if (setup != 0) {
        return setup;
    }

    rac_handle_t embeddings = nullptr;
    if (rac_embeddings_component_create(&embeddings) != RAC_SUCCESS) {
        out::error_line("failed to create embeddings component");
        return 1;
    }

    rac_result_t rc = rac_embeddings_component_load_model(
        embeddings, model.primary_path.c_str(), model.model_id.c_str(), model.display_name.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load embeddings model: " + out::describe_result(rc));
        rac_embeddings_component_destroy(embeddings);
        return 1;
    }

    std::vector<const char*> c_texts;
    c_texts.reserve(texts.size());
    for (const auto& text : texts) {
        c_texts.push_back(text.c_str());
    }

    const auto started = std::chrono::steady_clock::now();
    rac_embeddings_result_t result = {};
    rc = rac_embeddings_component_embed_batch(embeddings, c_texts.data(), c_texts.size(),
                                              nullptr, &result);
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now() - started)
                             .count();

    int exit_code = 0;
    if (rc != RAC_SUCCESS) {
        out::error_line("embedding failed: " + out::describe_result(rc));
        exit_code = 1;
    } else if (options.json) {
        print_json_result(model, texts, result, static_cast<int64_t>(elapsed));
    } else {
        print_text_result(model, result, static_cast<int64_t>(elapsed), options.verbose);
    }

    rac_embeddings_result_free(&result);
    rac_embeddings_component_destroy(embeddings);
    return exit_code;
}

}  // namespace

void register_embed(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("embed", "Generate text embeddings");
    auto ref = std::make_shared<std::string>();
    auto positional_text = std::make_shared<std::string>();
    auto option_texts = std::make_shared<std::vector<std::string>>();
    cmd->add_option("model", *ref,
                    "Embedding model (default: " + std::string(kDefaultEmbeddingModel) + ")");
    cmd->add_option("input", *positional_text, "Text to embed");
    cmd->add_option("--text,-t", *option_texts,
                    "Additional text to embed; repeat for batch embeddings");
    cmd->callback([&options, ref, positional_text, option_texts]() {
        std::vector<std::string> texts;
        if (!positional_text->empty()) {
            texts.push_back(*positional_text);
        }
        texts.insert(texts.end(), option_texts->begin(), option_texts->end());
        const int exit_code = run_embed(options, *ref, texts);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
