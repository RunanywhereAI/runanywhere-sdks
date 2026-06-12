/**
 * @file cmd_rm.cpp
 * @brief `rcli rm <model>` — delete downloaded files + unregister.
 *
 * File deletion is CLI-owned (registry remove only unregisters, per the
 * rac_model_registry_remove contract). Deletion targets come from the
 * registry's local_path and are confined to the models directory before
 * anything is removed.
 */

#include "commands/commands.h"
#include "commands/model_setup.h"

#include <cstdio>
#include <filesystem>
#include <memory>
#include <string>

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/model_ref.h"
#include "io/output.h"
#include "io/proto.h"
#include "util/term.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;
namespace fs = std::filesystem;

// Resolve the directory to delete for a model. Single-file artifacts live in
// a per-model folder ({models}/{framework}/{id}/file) — delete the folder when
// its name matches the model id, otherwise just the file itself.
fs::path deletion_target(const v1::ModelInfo &model) {
  const fs::path local(model.local_path());
  std::error_code ec;
  if (fs::is_directory(local, ec)) {
    return local;
  }
  const fs::path parent = local.parent_path();
  if (parent.filename() == model.id()) {
    return parent;
  }
  return local;
}

// The target must live strictly inside the models root.
bool confined_to(const fs::path &target, const fs::path &models_root) {
  std::error_code ec;
  const fs::path canonical_target = fs::weakly_canonical(target, ec);
  if (ec) {
    return false;
  }
  const fs::path canonical_root = fs::weakly_canonical(models_root, ec);
  if (ec) {
    return false;
  }
  const std::string target_str = canonical_target.string();
  const std::string root_str = canonical_root.string();
  return target_str.size() > root_str.size() + 1 &&
         target_str.starts_with(root_str + "/");
}

bool confirm_on_tty(const std::string &prompt) {
  std::fprintf(stderr, "%s [y/N] ", prompt.c_str());
  std::fflush(stderr);
  char buffer[16] = {};
  if (!std::fgets(buffer, sizeof(buffer), stdin)) {
    return false;
  }
  return buffer[0] == 'y' || buffer[0] == 'Y';
}

int run_rm(const GlobalOptions &options, const std::string &ref, bool force) {
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

  // Link on-disk artifacts before deciding what to delete — mirrors
  // list/ensure_model_ready so rm sees the same downloaded state.
  if (!refresh_registry(&error)) {
    out::status_line("warning: registry refresh failed: " + error);
  }

  rac_proto_buffer_t model_out;
  rac_proto_buffer_init(&model_out);
  v1::ModelInfo model;
  const rac_result_t get_rc = rac_model_registry_get_proto_buffer(
      rac_get_model_registry(), resolved.model_id.c_str(), &model_out);
  // parse unconditionally: it interprets the {status,error_message} envelope
  // and frees the buffer on every path (no leak on get failure).
  if (!proto::parse_proto_buffer(&model_out, &model, &error) ||
      get_rc != RAC_SUCCESS) {
    out::error_line("model not found: " + resolved.model_id);
    return 1;
  }

  uint64_t freed_bytes = 0;
  if (!model.local_path().empty()) {
    const fs::path target = deletion_target(model);
    if (!confined_to(target, env.models_dir)) {
      out::error_line("refusing to delete " + target.string() +
                      " (outside models directory " + env.models_dir + ")");
      return 1;
    }
    std::error_code ec;
    if (fs::exists(target, ec)) {
      if (!force && term::stdin_is_tty() &&
          !confirm_on_tty("delete " + target.string() + "?")) {
        out::status_line("aborted");
        return 1;
      }
      // Best-effort size accounting before removal.
      if (fs::is_directory(target, ec)) {
        for (const auto &entry : fs::recursive_directory_iterator(
                 target, fs::directory_options::skip_permission_denied, ec)) {
          if (entry.is_regular_file(ec)) {
            freed_bytes += entry.file_size(ec);
          }
        }
      } else if (fs::is_regular_file(target, ec)) {
        freed_bytes = fs::file_size(target, ec);
      }
      fs::remove_all(target, ec);
      if (ec) {
        out::error_line("failed to delete " + target.string() + ": " +
                        ec.message());
        return 1;
      }
    }
  } else {
    out::status_line(resolved.model_id + " has no downloaded files");
  }

  rac_proto_buffer_t remove_out;
  rac_proto_buffer_init(&remove_out);
  v1::ModelDeleteResult remove_result;
  if (rac_model_registry_remove_proto_buffer(rac_get_model_registry(),
                                             resolved.model_id.c_str(),
                                             &remove_out) != RAC_SUCCESS ||
      !proto::parse_proto_buffer(&remove_out, &remove_result, &error)) {
    out::status_line("warning: registry unregister failed: " + error);
  }

  if (options.json) {
    out::JsonWriter json;
    json.begin_object()
        .field("id", resolved.model_id)
        .field("freed_bytes", static_cast<int64_t>(freed_bytes))
        .end_object();
    out::result_line(json.str());
  } else {
    out::result_line(
        "deleted " + resolved.model_id +
        (freed_bytes ? " (freed " + out::human_bytes(freed_bytes) + ")" : ""));
  }
  return 0;
}

} // namespace

void register_rm(CLI::App &app, GlobalOptions &options) {
  CLI::App *cmd = app.add_subcommand("rm", "Delete a downloaded model");
  cmd->alias("remove");
  auto ref = std::make_shared<std::string>();
  auto force = std::make_shared<bool>(false);
  cmd->add_option("model", *ref, "Model id or alias")->required();
  cmd->add_flag("-f,--force", *force, "Do not ask for confirmation");
  cmd->callback([&options, ref, force]() {
    const int exit_code = run_rm(options, *ref, *force);
    if (exit_code != 0) {
      throw CLI::RuntimeError(exit_code);
    }
  });
}

} // namespace rcli::commands
