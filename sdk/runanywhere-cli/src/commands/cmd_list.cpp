/**
 * @file cmd_list.cpp
 * @brief `rcli list` — downloaded models (default) or full catalog (--all).
 *
 * The registry is refreshed with rescan_local so on-disk artifacts pulled by
 * previous runs (or by the test rig / playground tooling) are linked before
 * listing.
 */

#include "commands/commands.h"

#include <memory>
#include <set>
#include <string>
#include <vector>

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "commands/model_setup.h"
#include "io/output.h"
#include "io/proto.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

const char* category_label(v1::ModelCategory category) {
    switch (category) {
        case v1::MODEL_CATEGORY_LANGUAGE:
            return "llm";
        case v1::MODEL_CATEGORY_MULTIMODAL:
        case v1::MODEL_CATEGORY_VISION:
            return "vlm";
        case v1::MODEL_CATEGORY_SPEECH_RECOGNITION:
            return "stt";
        case v1::MODEL_CATEGORY_SPEECH_SYNTHESIS:
            return "tts";
        case v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
            return "vad";
        case v1::MODEL_CATEGORY_EMBEDDING:
            return "embedding";
        case v1::MODEL_CATEGORY_IMAGE_GENERATION:
            return "diffusion";
        case v1::MODEL_CATEGORY_AUDIO:
            return "audio";
        default:
            return "?";
    }
}

const char* framework_label(v1::InferenceFramework framework) {
    switch (framework) {
        case v1::INFERENCE_FRAMEWORK_LLAMA_CPP:
            return "llamacpp";
        case v1::INFERENCE_FRAMEWORK_ONNX:
            return "onnx";
        case v1::INFERENCE_FRAMEWORK_SHERPA:
            return "sherpa";
        case v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
            return "foundation";
        case v1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
            return "system-tts";
        default:
            return "?";
    }
}

int run_list(const GlobalOptions& options, bool show_all) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    std::string error;
    if (!refresh_registry(&error)) {
        out::status_line("warning: registry refresh failed: " + error);
    }

    // Full list + downloaded list; membership marks the DOWNLOADED column.
    rac_proto_buffer_t all_out;
    rac_proto_buffer_init(&all_out);
    v1::ModelInfoList all_models;
    if (rac_model_registry_list_proto_buffer(rac_get_model_registry(), &all_out) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&all_out, &all_models, &error)) {
        out::error_line("failed to list models: " + error);
        return 1;
    }

    std::set<std::string> downloaded_ids;
    {
        rac_proto_buffer_t downloaded_out;
        rac_proto_buffer_init(&downloaded_out);
        v1::ModelInfoList downloaded;
        if (rac_model_registry_list_downloaded_proto_buffer(rac_get_model_registry(),
                                                            &downloaded_out) == RAC_SUCCESS &&
            proto::parse_proto_buffer(&downloaded_out, &downloaded, nullptr)) {
            for (const v1::ModelInfo& model : downloaded.models()) {
                downloaded_ids.insert(model.id());
            }
        }
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object().begin_array("models");
        for (const v1::ModelInfo& model : all_models.models()) {
            const bool is_downloaded =
                downloaded_ids.count(model.id()) > 0 || model.is_downloaded();
            if (!show_all && !is_downloaded) {
                continue;
            }
            json.begin_array_object()
                .field("id", model.id())
                .field("name", model.name())
                .field("modality", category_label(model.category()))
                .field("backend", framework_label(model.framework()))
                .field("size_bytes", static_cast<int64_t>(model.download_size_bytes()))
                .field("downloaded", is_downloaded)
                .field("local_path", model.local_path())
                .end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
        return 0;
    }

    std::vector<std::vector<std::string>> rows;
    for (const v1::ModelInfo& model : all_models.models()) {
        const bool is_downloaded = downloaded_ids.count(model.id()) > 0 || model.is_downloaded();
        if (!show_all && !is_downloaded) {
            continue;
        }
        rows.push_back({model.id(), category_label(model.category()),
                        framework_label(model.framework()),
                        model.download_size_bytes() > 0
                            ? out::human_bytes(static_cast<uint64_t>(model.download_size_bytes()))
                            : "-",
                        is_downloaded ? "yes" : "no"});
    }

    if (rows.empty()) {
        out::result_line(show_all ? "no models registered"
                                  : "no models downloaded — try `rcli list --all` then "
                                    "`rcli pull <id>`");
        return 0;
    }
    out::table({"ID", "MODALITY", "BACKEND", "SIZE", "DOWNLOADED"}, rows);
    return 0;
}

}  // namespace

void register_list(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("list", "List models (downloaded by default)");
    cmd->alias("ls");
    auto show_all = std::make_shared<bool>(false);
    cmd->add_flag("--all,-a", *show_all, "Include catalog models that are not downloaded");
    cmd->callback([&options, show_all]() {
        const int exit_code = run_list(options, *show_all);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
