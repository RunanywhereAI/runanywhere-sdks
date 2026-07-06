#include "app.h"

#include <string>

#include "commands/commands.h"

#ifndef RCLI_VERSION
#define RCLI_VERSION "0.0.0-dev"
#endif

namespace rcli {

void configure_app(CLI::App& app, GlobalOptions& options) {
    app.set_version_flag("--version,-V", std::string("rcli ") + RCLI_VERSION);
    app.require_subcommand(0, 1);
    app.fallthrough(true);

    app.add_flag("--json", options.json, "Machine-readable JSON output on stdout");
    app.add_flag("-v,--verbose", options.verbose, "Debug logging on stderr");
    app.add_flag("-q,--quiet", options.quiet, "Errors only on stderr");
    app.add_flag("--no-progress", options.no_progress, "Disable progress rendering");
    app.add_option("--home", options.home_override,
                   "RunAnywhere home directory (default: $RUNANYWHERE_HOME or "
                   "~/.local/share/runanywhere; models live under <home>/Models)");

    commands::register_version(app, options);
    commands::register_info(app, options);
    commands::register_backends(app, options);
    commands::register_list(app, options);
    commands::register_lora(app, options);
    commands::register_pull(app, options);
    commands::register_rm(app, options);
    commands::register_show(app, options);
    commands::register_run(app, options);
    commands::register_stt(app, options);
    commands::register_tts(app, options);
    commands::register_vad(app, options);
    commands::register_voice(app, options);
    commands::register_serve(app, options);
}

}  // namespace rcli
