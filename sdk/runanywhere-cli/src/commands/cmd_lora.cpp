/**
 * @file cmd_lora.cpp
 * @brief `rcli lora import <file>` / `rcli lora list` — LoRA adapter catalog.
 *
 * Import places a local adapter file through the canonical commons entry
 * point (rac_lora_adapter_import_proto): catalog matching, canonical
 * placement, artifact registration, and manifest persistence all happen in
 * commons. This file only translates argv ↔ proto bytes, per the repo
 * layering rule.
 */

#include "commands/commands.h"

#include <memory>
#include <string>

#include "lora_options.pb.h"
#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/lora/rac_lora_service.h"

#include "io/output.h"
#include "io/proto.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

rac_lora_registry_handle_t require_lora_registry() {
  rac_lora_registry_handle_t registry = rac_get_lora_registry();
  if (!registry) {
    out::error_line("LoRA registry unavailable (SDK not initialized)");
  }
  return registry;
}

int run_lora_import(const GlobalOptions &options, const std::string &file) {
  Bootstrapped env;
  if (bootstrap(options, &env) != RAC_SUCCESS) {
    return 1;
  }
  rac_lora_registry_handle_t registry = require_lora_registry();
  if (!registry) {
    return 1;
  }

  v1::LoraAdapterImportRequest request;
  request.set_source_path(file);
  const std::string request_bytes = proto::serialize(request);

  rac_proto_buffer_t out_buffer;
  rac_proto_buffer_init(&out_buffer);
  const rac_result_t rc = rac_lora_adapter_import_proto(
      registry, reinterpret_cast<const uint8_t *>(request_bytes.data()),
      request_bytes.size(), &out_buffer);
  v1::LoraAdapterImportResult result;
  std::string error;
  if (!proto::parse_proto_buffer(&out_buffer, &result, &error) ||
      rc != RAC_SUCCESS) {
    out::error_line("import failed: " + error);
    return 1;
  }
  if (!result.success()) {
    out::error_line("import failed: " + result.error_message());
    return 1;
  }

  if (options.json) {
    out::JsonWriter json;
    json.begin_object()
        .field("local_path", result.local_path())
        .field("matched", result.matched());
    if (result.matched()) {
      json.field("adapter_id", result.entry().id());
    }
    json.end_object();
    out::result_line(json.str());
  } else {
    out::result_line("imported " + result.local_path() +
                     (result.matched()
                          ? " (catalog entry: " + result.entry().id() + ")"
                          : ""));
  }
  return 0;
}

int run_lora_list(const GlobalOptions &options) {
  Bootstrapped env;
  if (bootstrap(options, &env) != RAC_SUCCESS) {
    return 1;
  }
  rac_lora_registry_handle_t registry = require_lora_registry();
  if (!registry) {
    return 1;
  }

  v1::LoraAdapterCatalogListRequest request;
  const std::string request_bytes = proto::serialize(request);

  rac_proto_buffer_t out_buffer;
  rac_proto_buffer_init(&out_buffer);
  const rac_result_t rc = rac_lora_catalog_list_proto(
      registry, reinterpret_cast<const uint8_t *>(request_bytes.data()),
      request_bytes.size(), &out_buffer);
  v1::LoraAdapterCatalogListResult result;
  std::string error;
  if (!proto::parse_proto_buffer(&out_buffer, &result, &error) ||
      rc != RAC_SUCCESS || !result.success()) {
    out::error_line("list failed: " +
                    (error.empty() ? result.error_message() : error));
    return 1;
  }

  if (options.json) {
    out::JsonWriter json;
    json.begin_object()
        .field("count", static_cast<int64_t>(result.entries_size()))
        .begin_array("entries");
    for (const v1::LoraAdapterCatalogEntry &entry : result.entries()) {
      const bool downloaded =
          (entry.has_is_downloaded() && entry.is_downloaded()) ||
          !entry.local_path().empty();
      json.begin_array_object()
          .field("id", entry.id())
          .field("name", entry.name())
          .field("downloaded", downloaded)
          .field("local_path", entry.local_path())
          .end_object();
    }
    json.end_array().end_object();
    out::result_line(json.str());
    return 0;
  }
  if (result.entries_size() == 0) {
    out::result_line("no LoRA adapters registered");
    return 0;
  }
  for (const v1::LoraAdapterCatalogEntry &entry : result.entries()) {
    const bool downloaded =
        (entry.has_is_downloaded() && entry.is_downloaded()) ||
        !entry.local_path().empty();
    out::result_line(entry.id() + "  " + entry.name() +
                     (downloaded ? "  [downloaded]" : ""));
  }
  return 0;
}

// Load an LLM through the model-lifecycle service so rac_lora_apply_proto can
// acquire it. validate_availability=true auto-pulls the model if missing.
bool load_llm_for_lora(const GlobalOptions &options, const std::string &model_id) {
  v1::ModelLoadRequest request;
  request.set_model_id(model_id);
  request.set_category(v1::MODEL_CATEGORY_LANGUAGE);
  request.set_validate_availability(true);

  const std::string bytes = proto::serialize(request);
  rac_proto_buffer_t out_buffer;
  rac_proto_buffer_init(&out_buffer);
  std::string error;
  v1::ModelLoadResult result;
  if (rac_model_lifecycle_load_proto(rac_get_model_registry(),
                                     reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size(),
                                     &out_buffer) != RAC_SUCCESS ||
      !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
    out::error_line("LLM load failed: " + error);
    return false;
  }
  if (!result.success()) {
    out::error_line("LLM load failed: " +
                    (result.error_message().empty() ? "unknown error" : result.error_message()));
    return false;
  }
  return true;
}

int run_lora_apply(const GlobalOptions &options, const std::string &model_id,
                   const std::string &adapter_path, float scale) {
  Bootstrapped env;
  if (bootstrap(options, &env) != RAC_SUCCESS) {
    return 1;
  }
  if (!load_llm_for_lora(options, model_id)) {
    return 1;
  }

  v1::LoRAApplyRequest request;
  request.set_replace_existing(true);
  v1::LoRAAdapterConfig *adapter = request.add_adapters();
  adapter->set_adapter_path(adapter_path);
  adapter->set_scale(scale);

  const std::string request_bytes = proto::serialize(request);
  rac_proto_buffer_t out_buffer;
  rac_proto_buffer_init(&out_buffer);
  const rac_result_t rc = rac_lora_apply_proto(
      reinterpret_cast<const uint8_t *>(request_bytes.data()), request_bytes.size(), &out_buffer);
  v1::LoRAApplyResult result;
  std::string error;
  if (!proto::parse_proto_buffer(&out_buffer, &result, &error) || rc != RAC_SUCCESS) {
    out::error_line("apply failed: " + error);
    return 1;
  }
  if (!result.success()) {
    out::error_line("apply failed: " +
                    (result.error_message().empty() ? std::to_string(result.error_code())
                                                     : result.error_message()));
    return 1;
  }

  if (options.json) {
    out::JsonWriter json;
    json.begin_object()
        .field("success", result.success())
        .field("adapters", static_cast<int64_t>(result.adapters_size()))
        .end_object();
    out::result_line(json.str());
  } else {
    out::result_line("applied " + std::to_string(result.adapters_size()) + " adapter(s) to " +
                     model_id);
  }
  return 0;
}

} // namespace

void register_lora(CLI::App &app, GlobalOptions &options) {
  CLI::App *cmd = app.add_subcommand("lora", "LoRA adapter catalog");
  cmd->require_subcommand(1);

  CLI::App *import_cmd = cmd->add_subcommand(
      "import", "Import a local adapter file into SDK-owned storage");
  auto file = std::make_shared<std::string>();
  import_cmd->add_option("file", *file, "Path to the adapter file (.gguf)")
      ->required();
  import_cmd->callback([&options, file]() {
    const int exit_code = run_lora_import(options, *file);
    if (exit_code != 0) {
      throw CLI::RuntimeError(exit_code);
    }
  });

  CLI::App *list_cmd =
      cmd->add_subcommand("list", "List registered LoRA adapters");
  list_cmd->callback([&options]() {
    const int exit_code = run_lora_list(options);
    if (exit_code != 0) {
      throw CLI::RuntimeError(exit_code);
    }
  });

  CLI::App *apply_cmd = cmd->add_subcommand(
      "apply", "Load an LLM and attach a LoRA adapter (.gguf) to it");
  auto apply_model = std::make_shared<std::string>();
  auto adapter_path = std::make_shared<std::string>();
  auto scale = std::make_shared<float>(1.0f);
  apply_cmd->add_option("adapter", *adapter_path, "Path to the adapter file (.gguf)")
      ->required();
  apply_cmd->add_option("--model,-m", *apply_model, "LLM model id to attach the adapter to")
      ->required();
  apply_cmd->add_option("--scale", *scale, "Adapter scale factor (default: 1.0)")
      ->default_val(1.0f);
  apply_cmd->callback([&options, apply_model, adapter_path, scale]() {
    const int exit_code = run_lora_apply(options, *apply_model, *adapter_path, *scale);
    if (exit_code != 0) {
      throw CLI::RuntimeError(exit_code);
    }
  });
}

} // namespace rcli::commands
