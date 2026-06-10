/**
 * @file cmd_info.cpp
 * @brief `rcli info` — environment summary (versions, paths, memory, plugins).
 */

#include "commands/commands.h"

#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/plugin/rac_plugin_entry.h"

#include "config/cli_paths.h"
#include "io/output.h"

#ifndef RCLI_VERSION
#define RCLI_VERSION "0.0.0-dev"
#endif

namespace rcli::commands {

void register_info(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("info", "Show rcli environment information");
    cmd->callback([&options]() {
        Bootstrapped env;
        if (bootstrap(options, &env) != RAC_SUCCESS) {
            throw CLI::RuntimeError(1);
        }

        const rac_version_t commons = rac_get_version();
        const std::string commons_version = commons.string ? commons.string : "unknown";

        rac_memory_info_t memory{};
        bool memory_ok = false;
        if (const rac_platform_adapter_t* adapter = rac_get_platform_adapter()) {
            memory_ok = adapter->get_memory_info &&
                        adapter->get_memory_info(&memory, adapter->user_data) == RAC_SUCCESS;
        }

#if defined(__APPLE__)
        const char* platform = "macos";
#elif defined(__linux__)
        const char* platform = "linux";
#else
        const char* platform = "unknown";
#endif

        if (options.json) {
            out::JsonWriter json;
            json.begin_object()
                .field("rcli", RCLI_VERSION)
                .field("commons", commons_version)
                .field("platform", platform)
                .field("home", env.home)
                .field("models_dir", env.models_dir)
                .field("state_dir", paths::state_dir())
                .field("backends", static_cast<int64_t>(rac_plugin_count()));
            if (memory_ok) {
                json.field("memory_total_bytes", static_cast<int64_t>(memory.total_bytes))
                    .field("memory_available_bytes",
                           static_cast<int64_t>(memory.available_bytes));
            }
            json.end_object();
            out::result_line(json.str());
            return;
        }

        out::result_line("rcli       " RCLI_VERSION);
        out::result_line("commons    " + commons_version);
        out::result_line("platform   " + std::string(platform));
        out::result_line("home       " + env.home);
        out::result_line("models     " + env.models_dir);
        out::result_line("backends   " + std::to_string(rac_plugin_count()));
        if (memory_ok) {
            out::result_line("memory     " + out::human_bytes(memory.available_bytes) +
                             " available of " + out::human_bytes(memory.total_bytes));
        }
    });
}

}  // namespace rcli::commands
