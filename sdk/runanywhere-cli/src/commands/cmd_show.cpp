/**
 * @file cmd_show.cpp
 * @brief `rcli show <model>` — registry entry details.
 */

#include "commands/commands.h"
#include "commands/model_labels.h"
#include "commands/model_setup.h"

#include <memory>
#include <string>

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/model_ref.h"
#include "io/output.h"
#include "io/proto.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

int run_show(const GlobalOptions &options, const std::string &ref) {
  Bootstrapped env;
  if (bootstrap(options, &env) != RAC_SUCCESS) {
    return 1;
  }

  model_ref::Resolved resolved;
  std::string error;
  if (model_ref::resolve(ref, &resolved, &error) != RAC_SUCCESS) {
    out::error_line(error);
    return 1;
  }

  // Link on-disk artifacts (incl. sidecar-less rig-placed files) before
  // reading state — mirrors list/ensure_model_ready so show reports the
  // same downloaded state.
  if (!refresh_registry(&error)) {
    out::status_line("warning: registry refresh failed: " + error);
  }

  rac_proto_buffer_t out_buffer;
  rac_proto_buffer_init(&out_buffer);
  v1::ModelInfo model;
  const rac_result_t get_rc = rac_model_registry_get_proto_buffer(
      rac_get_model_registry(), resolved.model_id.c_str(), &out_buffer);
  // parse unconditionally: it interprets the {status,error_message}
  // envelope and frees the buffer on every path (no leak on get failure).
  if (!proto::parse_proto_buffer(&out_buffer, &model, &error) ||
      get_rc != RAC_SUCCESS) {
    out::error_line("model not found: " + resolved.model_id +
                    (error.empty() ? "" : " (" + error + ")"));
    return 1;
  }

  const bool downloaded = model.is_downloaded() || !model.local_path().empty();

  if (options.json) {
    out::JsonWriter json;
    json.begin_object()
        .field("id", model.id())
        .field("name", model.name())
        .field("category", static_cast<int64_t>(model.category()))
        .field("framework", static_cast<int64_t>(model.framework()))
        .field("backend", model_labels::backend(model.framework()))
        .field("format", static_cast<int64_t>(model.format()))
        .field("download_url", model.download_url())
        .field("local_path", model.local_path())
        .field("size_bytes", static_cast<int64_t>(model.download_size_bytes()))
        .field("context_length", static_cast<int64_t>(model.context_length()))
        .field("supports_thinking", model.supports_thinking())
        .field("downloaded", downloaded);
    if (model.has_multi_file()) {
      json.begin_array("files");
      for (const v1::ModelFileDescriptor &file : model.multi_file().files()) {
        json.begin_array_object()
            .field("filename", file.filename())
            .field("url", file.url())
            .end_object();
      }
      json.end_array();
    }
    json.end_object();
    out::result_line(json.str());
    return 0;
  }

  out::result_line("id          " + model.id());
  out::result_line("name        " + model.name());
  out::result_line("backend     " +
                   std::string(model_labels::backend(model.framework())));
  if (model.download_size_bytes() > 0) {
    out::result_line("size        " + out::human_bytes(static_cast<uint64_t>(
                                          model.download_size_bytes())));
  }
  if (model.context_length() > 0) {
    out::result_line("context     " + std::to_string(model.context_length()));
  }
  if (!model.download_url().empty()) {
    out::result_line("url         " + model.download_url());
  }
  if (model.has_multi_file()) {
    for (const v1::ModelFileDescriptor &file : model.multi_file().files()) {
      out::result_line("file        " + file.filename() + "  (" + file.url() +
                       ")");
    }
  }
  out::result_line("downloaded  " + std::string(downloaded ? "yes" : "no"));
  if (!model.local_path().empty()) {
    out::result_line("path        " + model.local_path());
  }
  if (model.supports_thinking()) {
    out::result_line("thinking    yes");
  }
  return 0;
}

} // namespace

void register_show(CLI::App &app, GlobalOptions &options) {
  CLI::App *cmd = app.add_subcommand("show", "Show model details");
  auto ref = std::make_shared<std::string>();
  cmd->add_option("model", *ref, "Model id, alias or URL")->required();
  cmd->callback([&options, ref]() {
    const int exit_code = run_show(options, *ref);
    if (exit_code != 0) {
      throw CLI::RuntimeError(exit_code);
    }
  });
}

} // namespace rcli::commands
