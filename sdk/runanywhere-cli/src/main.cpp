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

#include "app.h"
#include "bootstrap.h"
#include "io/output.h"

int main(int argc, char** argv) {
    rcli::GlobalOptions options;

    CLI::App app{"RunAnywhere on-device AI CLI — run, manage and serve local models"};
    rcli::configure_app(app, options);

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
