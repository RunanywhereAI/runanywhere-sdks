/**
 * @file cmd_models.cpp
 * @brief `rcli models …` — the model-lifecycle namespace from the public API
 *        spec (list, get, register, download, delete, load, unload, state).
 *
 * list / get / download / delete reuse the configure_* functions owned by
 * cmd_list, cmd_show, cmd_pull and cmd_rm, so the namespaced verbs and the
 * top-level aliases (`list`, `show`, `pull`, `rm`) are the same command.
 * register / load / unload / state are thin translations of the commons
 * lifecycle ABI:
 *   register → model_ref::resolve (rac_register_model_from_url_proto inside)
 *   load     → rac_model_lifecycle_load_proto(validate_availability=true)
 *   unload   → rac_model_lifecycle_unload_proto
 *   state    → rac_model_lifecycle_current_model_proto per category
 */

#include "commands/commands.h"

#include <filesystem>
#include <memory>
#include <string>
#include <system_error>
#include <vector>

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/model_ref.h"
#include "commands/engine_options.h"
#include "commands/model_labels.h"
#include "io/output.h"
#include "io/proto.h"
#include "progress/progress_bar.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;
namespace fs = std::filesystem;

// Categories `models state` reports, in the order they are printed.
constexpr v1::ModelCategory kStateCategories[] = {
    v1::MODEL_CATEGORY_LANGUAGE,
    v1::MODEL_CATEGORY_MULTIMODAL,
    v1::MODEL_CATEGORY_SPEECH_RECOGNITION,
    v1::MODEL_CATEGORY_SPEECH_SYNTHESIS,
    v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    v1::MODEL_CATEGORY_EMBEDDING,
    v1::MODEL_CATEGORY_IMAGE_GENERATION,
};

bool parse_category(const std::string& name, v1::ModelCategory* out) {
    for (const v1::ModelCategory category : kStateCategories) {
        if (name == model_labels::category(category)) {
            *out = category;
            return true;
        }
    }
    return false;
}

std::string category_choices() {
    std::string choices;
    for (const v1::ModelCategory category : kStateCategories) {
        choices += choices.empty() ? "" : ", ";
        choices += model_labels::category(category);
    }
    return choices;
}

int run_register(const GlobalOptions& options, const std::string& ref, const std::string& engine) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    EngineHintResolution engine_hint;
    std::string error;
    if (!resolve_engine_hint(engine, &engine_hint, &error)) {
        out::error_line(error);
        return 2;
    }

    model_ref::Resolved resolved;
    if (model_ref::resolve(ref, &resolved, &error, &engine_hint.resolve_options) != RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }

    rac_proto_buffer_t info_out;
    rac_proto_buffer_init(&info_out);
    v1::ModelInfo model;
    const rac_result_t get_rc = rac_model_registry_get_proto_buffer(
        rac_get_model_registry(), resolved.model_id.c_str(), &info_out);
    const bool parsed = proto::parse_proto_buffer(&info_out, &model, &error);
    if (get_rc != RAC_SUCCESS || !parsed) {
        out::error_line("registration failed: " + error);
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("id", model.id())
            .field("name", model.name())
            .field("modality", model_labels::category(model.category()))
            .field("backend", model_labels::backend(model.framework()))
            .field("download_url", model.download_url())
            .field("downloaded",
                   model.registry_status() == v1::MODEL_REGISTRY_STATUS_DOWNLOADED)
            .end_object();
        out::result_line(json.str());
    } else {
        out::result_line("registered " + model.id());
    }
    return 0;
}

int run_load(const GlobalOptions& options, const std::string& ref, const std::string& engine,
             const std::string& category_name) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    EngineHintResolution engine_hint;
    std::string error;
    if (!resolve_engine_hint(engine, &engine_hint, &error)) {
        out::error_line(error);
        return 2;
    }

    v1::ModelCategory category = v1::MODEL_CATEGORY_UNSPECIFIED;
    if (!category_name.empty()) {
        if (!parse_category(category_name, &category)) {
            out::error_line("unknown category '" + category_name + "' (" + category_choices() +
                            ")");
            return 2;
        }
        engine_hint.resolve_options.has_category = true;
        engine_hint.resolve_options.category = category;
    }

    model_ref::Resolved resolved;
    if (model_ref::resolve(ref, &resolved, &error, &engine_hint.resolve_options) != RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }

    progress::DownloadProgressScope progress_scope(resolved.model_id,
                                                   !options.no_progress && !options.json);
    v1::ModelLoadRequest request;
    request.set_model_id(resolved.model_id);
    request.set_validate_availability(true);
    if (category != v1::MODEL_CATEGORY_UNSPECIFIED) {
        request.set_category(category);
    }
    if (!resolved.from_catalog &&
        engine_hint.framework != v1::INFERENCE_FRAMEWORK_UNSPECIFIED) {
        request.set_framework(engine_hint.framework);
    }

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    v1::ModelLoadResult result;
    if (rac_model_lifecycle_load_proto(rac_get_model_registry(),
                                       reinterpret_cast<const uint8_t*>(bytes.data()),
                                       bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("model load failed: " + error);
        return 1;
    }
    if (result.has_error()) {
        out::error_line("model load failed: " + (result.error().message().empty()
                                                     ? "unknown error"
                                                     : result.error().message()));
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("id", result.model_id())
            .field("modality", model_labels::category(result.category()))
            .field("backend", model_labels::backend(result.framework()))
            .field("path", result.resolved_path())
            .field("already_loaded", result.already_loaded())
            .end_object();
        out::result_line(json.str());
    } else {
        out::result_line("loaded " + result.model_id() + " → " + result.resolved_path());
    }
    return 0;
}

int run_unload(const GlobalOptions& options, const std::string& category_name) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    v1::ModelUnloadRequest request;
    if (category_name.empty()) {
        request.set_unload_all(true);
    } else {
        v1::ModelCategory category = v1::MODEL_CATEGORY_UNSPECIFIED;
        if (!parse_category(category_name, &category)) {
            out::error_line("unknown category '" + category_name + "' (" + category_choices() +
                            ")");
            return 2;
        }
        request.set_category(category);
    }

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    std::string error;
    v1::ModelUnloadResult result;
    if (rac_model_lifecycle_unload_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                         bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("unload failed: " + error);
        return 1;
    }
    // Freeing everything when nothing is resident is not a failure, even though
    // the lifecycle service reports "no loaded model matched".
    if (result.has_error() && !(request.unload_all() && result.unloaded_model_ids().empty())) {
        out::error_line("unload failed: " + (result.error().message().empty()
                                                ? "unknown error"
                                                : result.error().message()));
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object().begin_array("unloaded");
        for (const std::string& id : result.unloaded_model_ids()) {
            json.begin_array_object().field("id", id).end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
    } else if (result.unloaded_model_ids().empty()) {
        out::result_line("nothing was loaded");
    } else {
        for (const std::string& id : result.unloaded_model_ids()) {
            out::result_line("unloaded " + id);
        }
    }
    return 0;
}

// Loaded model for one category, or an empty id when nothing is resident.
std::string loaded_model_id(v1::ModelCategory category) {
    v1::CurrentModelRequest request;
    request.set_category(category);
    const std::string bytes = proto::serialize(request);

    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    v1::CurrentModelResult result;
    if (rac_model_lifecycle_current_model_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                                bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, nullptr) || !result.found()) {
        return {};
    }
    return result.model_id();
}

struct Storage {
    uint64_t used_bytes = 0;
    uint64_t free_bytes = 0;
};

Storage models_storage(const std::string& models_dir) {
    Storage storage;
    std::error_code ec;
    for (const auto& entry : fs::recursive_directory_iterator(
             models_dir, fs::directory_options::skip_permission_denied, ec)) {
        if (entry.is_regular_file(ec)) {
            storage.used_bytes += entry.file_size(ec);
        }
    }
    // The models directory may not exist yet; free space comes from the nearest
    // ancestor that does.
    for (fs::path path = models_dir; !path.empty(); path = path.parent_path()) {
        const fs::space_info space = fs::space(path, ec);
        if (!ec) {
            storage.free_bytes = space.available;
            break;
        }
        if (!path.has_relative_path()) {
            break;
        }
    }
    return storage;
}

int run_state(const GlobalOptions& options) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    std::vector<std::pair<std::string, std::string>> loaded;
    for (const v1::ModelCategory category : kStateCategories) {
        const std::string id = loaded_model_id(category);
        if (!id.empty()) {
            loaded.emplace_back(model_labels::category(category), id);
        }
    }
    const Storage storage = models_storage(env.models_dir);

    if (options.json) {
        out::JsonWriter json;
        json.begin_object().begin_array("loaded");
        for (const auto& [modality, id] : loaded) {
            json.begin_array_object().field("modality", modality).field("id", id).end_object();
        }
        json.end_array()
            .field("storage_used_bytes", static_cast<int64_t>(storage.used_bytes))
            .field("storage_free_bytes", static_cast<int64_t>(storage.free_bytes))
            .end_object();
        out::result_line(json.str());
        return 0;
    }

    if (loaded.empty()) {
        out::result_line("no models loaded");
    } else {
        std::vector<std::vector<std::string>> rows;
        for (const auto& [modality, id] : loaded) {
            rows.push_back({modality, id});
        }
        out::table({"MODALITY", "LOADED"}, rows);
    }
    out::result_line("storage    " + out::human_bytes(storage.used_bytes) + " used, " +
                     out::human_bytes(storage.free_bytes) + " free");
    return 0;
}

}  // namespace

void register_models(CLI::App& app, GlobalOptions& options) {
    CLI::App* ns = app.add_subcommand("models", "Manage the local model catalog");
    ns->require_subcommand(1);

    configure_models_list(ns->add_subcommand("list", "List models, downloaded ones by default"),
                          options);
    configure_models_get(ns->add_subcommand("get", "Show one model's registry entry"), options);
    configure_models_download(
        ns->add_subcommand("download", "Fetch a model with resumable progress"), options);
    configure_models_delete(ns->add_subcommand("delete", "Remove a model's files and registration"),
                            options);

    CLI::App* register_cmd =
        ns->add_subcommand("register", "Add a model from a URL or hf.co ref to the registry");
    auto register_ref = std::make_shared<std::string>();
    auto register_engine = std::make_shared<std::string>();
    register_cmd->add_option("model", *register_ref, "hf.co/org/repo/file, hf:// or http(s) URL")
        ->required();
    register_cmd->add_option("--engine", *register_engine,
                             "Pin the inference engine (mlx, llamacpp, onnx, sherpa)");
    register_cmd->callback([&options, register_ref, register_engine]() {
        const int exit_code = run_register(options, *register_ref, *register_engine);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });

    CLI::App* load_cmd = ns->add_subcommand("load", "Load a model now instead of on first use");
    auto load_ref = std::make_shared<std::string>();
    auto load_engine = std::make_shared<std::string>();
    auto load_category = std::make_shared<std::string>();
    load_cmd->add_option("model", *load_ref, "Model id, alias, hf.co/... ref or URL")->required();
    load_cmd->add_option("--engine,--framework", *load_engine,
                         "Pin the inference engine (mlx, llamacpp, onnx, sherpa)");
    load_cmd->add_option("--category", *load_category,
                         "Load it as this modality (" + category_choices() + ")");
    load_cmd->callback([&options, load_ref, load_engine, load_category]() {
        const int exit_code = run_load(options, *load_ref, *load_engine, *load_category);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });

    CLI::App* unload_cmd =
        ns->add_subcommand("unload", "Free loaded models, all of them by default");
    auto unload_category = std::make_shared<std::string>();
    unload_cmd->add_option("category", *unload_category,
                           "Only free this modality (" + category_choices() + ")");
    unload_cmd->callback([&options, unload_category]() {
        const int exit_code = run_unload(options, *unload_category);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });

    CLI::App* state_cmd = ns->add_subcommand("state", "Report resident models and disk usage");
    state_cmd->callback([&options]() {
        const int exit_code = run_state(options);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

void register_models_aliases(CLI::App& app, GlobalOptions& options) {
    CLI::App* list = app.add_subcommand("list", "List models (alias of `models list`)");
    list->alias("ls");
    configure_models_list(list, options);

    configure_models_get(app.add_subcommand("show", "Show model details (alias of `models get`)"),
                         options);
    configure_models_download(
        app.add_subcommand("pull", "Download a model (alias of `models download`)"), options);

    CLI::App* remove = app.add_subcommand("rm", "Delete a model (alias of `models delete`)");
    remove->alias("remove");
    configure_models_delete(remove, options);
}

}  // namespace rcli::commands
