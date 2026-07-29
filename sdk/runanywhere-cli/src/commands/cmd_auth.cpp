/**
 * @file cmd_auth.cpp
 * @brief `rcli auth login` — real control-plane handshake.
 *
 * Runs the canonical staging/production auth sequence against the configured
 * backend (--base-url/--api-key/--environment or their RUNANYWHERE_* env
 * vars): authenticate (API key → JWT + refresh token), device registration,
 * and model-assignment fetch — all through commons entry points
 * (net::login → rac_auth_* + rac_sdk_init_phase2_proto).
 */

#include "commands/commands.h"

#include <cstdio>
#include <ctime>
#include <string>

#include "net/control_plane.h"

#include "io/output.h"

namespace rcli::commands {

namespace {

std::string format_epoch_seconds(int64_t seconds) {
    if (seconds <= 0) {
        return "-";
    }
    const time_t secs = static_cast<time_t>(seconds);
    struct tm tm_info{};
#if defined(_WIN32)
    if (gmtime_s(&tm_info, &secs) != 0) {
        return std::to_string(seconds);
    }
#else
    if (gmtime_r(&secs, &tm_info) == nullptr) {
        return std::to_string(seconds);
    }
#endif
    char buffer[32] = {};
    strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &tm_info);
    return buffer;
}

int run_auth_login(const GlobalOptions& options) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    net::LoginSummary summary;
    std::string error;
    if (net::login(&summary, &error) != RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }

    // A staging/production login without a device row is a broken control
    // plane — surface it as a failure, not a footnote.
    const bool ok = summary.device_registered;

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("success", ok)
            .field("organization_id", summary.organization_id)
            .field("user_id", summary.user_id)
            .field("device_id", summary.backend_device_id)
            .field("device_uuid", summary.persistent_device_id)
            .field("token_expires_at", format_epoch_seconds(summary.token_expires_at))
            .field("device_registered", summary.device_registered)
            .field("assignments", static_cast<int64_t>(summary.assignment_count));
        if (!summary.warning.empty()) {
            json.field("warning", summary.warning);
        }
        json.end_object();
        out::result_line(json.str());
    } else {
        out::result_line("organization   " + summary.organization_id);
        out::result_line("user           " +
                         (summary.user_id.empty() ? std::string("-") : summary.user_id));
        out::result_line("device         " + summary.backend_device_id);
        out::result_line("device-uuid    " + summary.persistent_device_id);
        out::result_line("token expires  " + format_epoch_seconds(summary.token_expires_at));
        out::result_line(std::string("device row     ") +
                         (summary.device_registered ? "registered" : "NOT registered"));
        out::result_line("assignments    " + std::to_string(summary.assignment_count) +
                         " model(s)");
        if (!summary.warning.empty()) {
            out::status_line("warning: " + summary.warning);
        }
    }

    if (!ok) {
        out::error_line("device registration did not complete" +
                        (summary.warning.empty() ? "" : ": " + summary.warning));
        return 1;
    }
    return 0;
}

}  // namespace

void register_auth(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("auth", "Control-plane authentication");
    cmd->require_subcommand(1);

    CLI::App* login_cmd = cmd->add_subcommand(
        "login",
        "Authenticate against the configured backend (API key → JWT), register "
        "this device and fetch model assignments. Requires --environment "
        "production with --base-url and --api-key (or RUNANYWHERE_* env vars). "
        "Keyless development has no login path.");
    login_cmd->callback([&options]() {
        const int exit_code = run_auth_login(options);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
