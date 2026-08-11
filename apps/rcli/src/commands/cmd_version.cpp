/**
 * @file cmd_version.cpp
 * @brief `rcli version` — CLI + commons versions. No bootstrap needed.
 */

#include "commands/commands.h"

#include <string>

#include "rac/core/rac_core.h"

#include "io/output.h"

#ifndef RCLI_VERSION
#define RCLI_VERSION "0.0.0-dev"
#endif

namespace rcli::commands {

void register_version(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("version", "Show rcli and commons versions");
    cmd->callback([&options]() {
        const rac_version_t commons = rac_get_version();
        const std::string commons_version =
            commons.string ? commons.string : "unknown";
        if (options.json) {
            out::JsonWriter json;
            json.begin_object()
                .field("rcli", RCLI_VERSION)
                .field("commons", commons_version)
                .end_object();
            out::result_line(json.str());
        } else {
            out::result_line(std::string("rcli ") + RCLI_VERSION + " (commons " +
                             commons_version + ")");
        }
    });
}

}  // namespace rcli::commands
