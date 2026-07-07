/**
 * @file cmd_embed.cpp
 * @brief `rcli embed [input]` — text embeddings via the commons lifecycle path.
 */

#include "commands/commands.h"

#include <algorithm>
#include <iomanip>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "embeddings_options.pb.h"
#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/embeddings/rac_embeddings_service.h"

#include "catalog/model_ref.h"
#include "commands/engine_options.h"
#include "io/output.h"
#include "io/proto.h"
#include "progress/progress_bar.h"

namespace rcli::commands {

namespace {

constexpr const char* kDefaultEmbeddingModel = "minilm";

namespace v1 = runanywhere::v1;

std::string preview_values(const v1::EmbeddingVector& vector) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(5);
    const int count = std::min(vector.values_size(), 8);
    for (int i = 0; i < count; ++i) {
        if (i > 0) {
            out << ',';
        }
        out << vector.values(i);
    }
    return out.str();
}

void print_json_result(const std::string& model_id, const std::vector<std::string>& texts,
                       const v1::EmbeddingsResult& result) {
    out::JsonWriter json;
    json.begin_object()
        .field("model", result.has_model_id() && !result.model_id().empty() ? result.model_id()
                                                                             : model_id)
        .field("dimension", static_cast<int64_t>(result.dimension()))
        .field("count", static_cast<int64_t>(result.vectors_size()))
        .field("tokens_used", static_cast<int64_t>(result.tokens_used()))
        .field("total_ms", static_cast<int64_t>(result.processing_time_ms()));
    json.begin_array("vectors");
    for (int i = 0; i < result.vectors_size(); ++i) {
        const auto& vector = result.vectors(i);
        const std::string text = vector.has_text() ? vector.text()
                                 : (static_cast<size_t>(i) < texts.size() ? texts[static_cast<size_t>(i)]
                                                                          : std::string());
        json.begin_array_object()
            .field("text", text)
            .field("dimension", static_cast<int64_t>(vector.dimension()));
        json.begin_array("values");
        for (const float value : vector.values()) {
            json.value(static_cast<double>(value));
        }
        json.end_array().end_object();
    }
    json.end_array().end_object();
    out::result_line(json.str());
}

void print_text_result(const std::string& model_id, const v1::EmbeddingsResult& result,
                       bool verbose) {
    out::result_line("model\t" + model_id);
    out::result_line("dimension\t" + std::to_string(result.dimension()));
    out::result_line("count\t" + std::to_string(result.vectors_size()));
    for (int i = 0; i < result.vectors_size(); ++i) {
        out::result_line("vector[" + std::to_string(i) + "]\t" + preview_values(result.vectors(i)));
    }
    if (verbose) {
        out::status_line("(" + std::to_string(result.processing_time_ms()) + " ms)");
    }
}

bool load_embeddings_model(const GlobalOptions& options, const std::string& model_id,
                           v1::InferenceFramework framework) {
    progress::DownloadProgressScope progress_scope(model_id, !options.no_progress && !options.json);
    v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    request.set_category(v1::MODEL_CATEGORY_EMBEDDING);
    request.set_validate_availability(true);
    if (framework != v1::INFERENCE_FRAMEWORK_UNSPECIFIED) {
        request.set_framework(framework);
    }

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    std::string error;
    v1::ModelLoadResult result;
    if (rac_model_lifecycle_load_proto(rac_get_model_registry(),
                                       reinterpret_cast<const uint8_t*>(bytes.data()),
                                       bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("embedding model load failed: " + error);
        return false;
    }
    if (!result.success()) {
        out::error_line("embedding model load failed: " +
                        (result.error_message().empty() ? "unknown error"
                                                        : result.error_message()));
        return false;
    }
    if (options.verbose) {
        out::status_line("loaded " + result.resolved_path());
    }
    return true;
}

int run_embed(const GlobalOptions& options, const std::string& ref, const std::string& engine,
              const std::vector<std::string>& texts) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    if (texts.empty()) {
        out::error_line("at least one text input is required");
        return 2;
    }

    EngineHintResolution engine_hint;
    std::string engine_error;
    if (!resolve_engine_hint(engine, &engine_hint, &engine_error)) {
        out::error_line(engine_error);
        return 2;
    }
    engine_hint.resolve_options.has_category = true;
    engine_hint.resolve_options.category = v1::MODEL_CATEGORY_EMBEDDING;

    model_ref::Resolved resolved;
    std::string error;
    const std::string selected_ref = ref.empty() ? kDefaultEmbeddingModel : ref;
    if (model_ref::resolve(selected_ref, &resolved, &error, &engine_hint.resolve_options) !=
        RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }

    const v1::InferenceFramework load_framework =
        resolved.from_catalog ? v1::INFERENCE_FRAMEWORK_UNSPECIFIED : engine_hint.framework;
    if (!load_embeddings_model(options, resolved.model_id, load_framework)) {
        return 1;
    }

    v1::EmbeddingsRequest request;
    request.set_model_id(resolved.model_id);
    for (const auto& text : texts) {
        request.add_texts(text);
    }

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    v1::EmbeddingsResult result;
    if (rac_embeddings_embed_batch_lifecycle_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                                   bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("embedding failed: " + error);
        return 1;
    }

    if (result.error_code() != 0 || !result.error_message().empty()) {
        out::error_line("embedding failed: " +
                        (result.error_message().empty() ? std::to_string(result.error_code())
                                                        : result.error_message()));
        return 1;
    }
    if (options.json) {
        print_json_result(resolved.model_id, texts, result);
    } else {
        print_text_result(resolved.model_id, result, options.verbose);
    }
    return 0;
}

}  // namespace

void register_embed(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("embed", "Generate text embeddings");
    auto model = std::make_shared<std::string>(kDefaultEmbeddingModel);
    auto engine = std::make_shared<std::string>();
    auto positional_text = std::make_shared<std::string>();
    auto option_texts = std::make_shared<std::vector<std::string>>();
    cmd->add_option("input", *positional_text, "Text to embed");
    cmd->add_option("--model,-m", *model,
                    "Embedding model (default: " + std::string(kDefaultEmbeddingModel) + ")")
        ->default_val(kDefaultEmbeddingModel);
    cmd->add_option("--engine", *engine,
                    "Engine/framework hint for URL or HF refs (mlx, llamacpp, onnx, sherpa)");
    cmd->add_option("--text,-t", *option_texts,
                    "Additional text to embed; repeat for batch embeddings");
    cmd->callback([&options, model, engine, positional_text, option_texts]() {
        std::vector<std::string> texts;
        if (!positional_text->empty()) {
            texts.push_back(*positional_text);
        }
        texts.insert(texts.end(), option_texts->begin(), option_texts->end());
        const int exit_code = run_embed(options, *model, *engine, texts);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
