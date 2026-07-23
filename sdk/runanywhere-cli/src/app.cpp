#include "app.h"

#include <exception>
#include <string>

#include <CLI11.hpp>

#include "bootstrap.h"
#include "commands/commands.h"
#include "io/output.h"

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

    // Control-plane connection. validation happens in resolve_connection().
    app.add_option("--environment", options.environment,
                   "SDK environment: development (default, keyless OSS → baked staging "
                   "backend) or production (API key + https URL).")
        ->envname("RUNANYWHERE_ENVIRONMENT")
        ->check(CLI::IsMember({"dev", "development", "prod", "production"}));
    app.add_option("--base-url", options.base_url,
                   "Backend base URL. Optional in development (baked staging URL). "
                   "Required https for production.")
        ->envname("RUNANYWHERE_BASE_URL");
    app.add_option("--api-key", options.api_key,
                   "Control-plane API key (required for production; omit for "
                   "keyless development)")
        ->envname("RUNANYWHERE_API_KEY");

    commands::register_version(app, options);
    commands::register_info(app, options);
    commands::register_backends(app, options);
    commands::register_list(app, options);
    commands::register_lora(app, options);
    commands::register_pull(app, options);
    commands::register_rm(app, options);
    commands::register_show(app, options);
    commands::register_run(app, options);
    commands::register_image(app, options);
    commands::register_segment(app, options);
    commands::register_embed(app, options);
    commands::register_diarize(app, options);
    commands::register_stt(app, options);
    commands::register_tts(app, options);
    commands::register_vad(app, options);
    commands::register_voice(app, options);
    commands::register_rag(app, options);
    commands::register_bench(app, options);
    commands::register_serve(app, options);
    commands::register_auth(app, options);
    commands::register_telemetry(app, options);
}

int run(int argc, char** argv) {
    GlobalOptions options;

    CLI::App app{"RunAnywhere on-device AI CLI — run, manage and serve local models"};
    configure_app(app, options);

    int exit_code = 0;
    try {
        app.parse(argc, argv);
        if (app.get_subcommands().empty()) {
            // Bare `rcli` prints help like `ollama` does.
            out::status_line(app.help());
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
        out::error_line(e.what());
        exit_code = 1;
    }

    shutdown();
    return exit_code;
}

}  // namespace rcli

extern "C" int rcli_run_main(int argc, char** argv) {
    return rcli::run(argc, argv);
}
