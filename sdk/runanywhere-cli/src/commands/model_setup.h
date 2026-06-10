/**
 * @file model_setup.h
 * @brief Shared ensure-downloaded + resolve-paths step for speech commands.
 *
 * Resolves a model ref, pulls it when missing (same flow as `rcli pull`), and
 * resolves the on-disk artifact paths through commons'
 * rac_model_lifecycle_resolve_paths_proto — no engine load, no path guessing
 * in the CLI.
 */

#ifndef RCLI_COMMANDS_MODEL_SETUP_H
#define RCLI_COMMANDS_MODEL_SETUP_H

#include <string>

#include "bootstrap.h"

namespace rcli::commands {

struct ResolvedModelPaths {
    std::string model_id;
    std::string display_name;
    std::string primary_path;  // resolved artifact (file or inner directory)
};

/**
 * Resolve ref → ensure downloaded (auto-pull with progress) → resolve paths.
 * Returns 0 on success, 1 on failure, 130 when the user cancelled the pull.
 */
int ensure_model_ready(const GlobalOptions& options, const std::string& ref,
                       ResolvedModelPaths* out);

/**
 * Refresh the registry (rescan_local + downloaded-state reconciliation) so
 * on-disk artifacts — including ones placed by the test rig or playground —
 * are linked to their entries. Used by list and by ensure_model_ready.
 */
bool refresh_registry(std::string* error);

}  // namespace rcli::commands

#endif  // RCLI_COMMANDS_MODEL_SETUP_H
