/**
 * @file main.cpp
 * @brief rcli — RunAnywhere desktop CLI entry point.
 *
 * Thin dispatch layer: global flags + CLI11 subcommands. All real work
 * happens in commons behind the rac_* C ABI (see AGENTS.md layering rule).
 *
 * Exit codes: 0 success, 1 runtime/SDK error, 2 usage error.
 */

#include <CLI11.hpp>

#include "bootstrap.h"
#include "commands/commands.h"
#include "io/output.h"

#ifndef RCLI_VERSION
#define RCLI_VERSION "0.0.0-dev"
#endif

int main(int argc, char** argv) {
    rcli::GlobalOptions options;

    CLI::App app{"RunAnywhere on-device AI CLI — run, manage and serve local models"};
    app.set_version_flag("--version,-V", std::string("rcli ") + RCLI_VERSION);
    app.require_subcommand(0, 1);
    // Global flags (--json, -v, --home, …) are valid after the subcommand
    // name too: `rcli list --json` and `rcli --json list` both work.
    app.fallthrough(true);

    app.add_flag("--json", options.json, "Machine-readable JSON output on stdout");
    app.add_flag("-v,--verbose", options.verbose, "Debug logging on stderr");
    app.add_flag("-q,--quiet", options.quiet, "Errors only on stderr");
    app.add_flag("--no-progress", options.no_progress, "Disable progress rendering");
    app.add_option("--home", options.home_override,
                   "RunAnywhere home directory (default: $RUNANYWHERE_HOME or "
                   "~/.local/share/runanywhere; models live under <home>/Models)");

    rcli::commands::register_version(app, options);
    rcli::commands::register_info(app, options);
    rcli::commands::register_backends(app, options);
    rcli::commands::register_list(app, options);
    rcli::commands::register_pull(app, options);
    rcli::commands::register_rm(app, options);
    rcli::commands::register_show(app, options);
    rcli::commands::register_run(app, options);
    rcli::commands::register_stt(app, options);
    rcli::commands::register_tts(app, options);
    rcli::commands::register_vad(app, options);
    rcli::commands::register_voice(app, options);
    rcli::commands::register_serve(app, options);

    int exit_code = 0;
    try {
        app.parse(argc, argv);
        if (app.get_subcommands().empty()) {
            // Bare `rcli` prints help like `ollama` does.
            rcli::out::status_line(app.help());
        }
    } catch (const CLI::CallForHelp& e) {
        exit_code = app.exit(e);
    } catch (const CLI::CallForVersion& e) {
        exit_code = app.exit(e);
    } catch (const CLI::RuntimeError& e) {
        exit_code = (e.get_exit_code() != 0) ? e.get_exit_code() : 1;
    } catch (const CLI::ParseError& e) {
        app.exit(e);  // prints the usage message to stderr
        exit_code = 2;
    } catch (const std::exception& e) {
        rcli::out::error_line(e.what());
        exit_code = 1;
    }

    rcli::shutdown();
    return exit_code;
}
