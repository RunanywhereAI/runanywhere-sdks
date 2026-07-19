/**
 * @file bootstrap.h
 * @brief One-call SDK bring-up for every rcli command.
 *
 * Mirrors the canonical bootstrap proven by the commons real-inference tests
 * (tests/test_voice_agent.cpp) with real desktop I/O:
 *
 *   desktop adapter → rac_model_paths_set_base_dir → rac_init →
 *   curl HTTP transport → backend registration → (PR3: catalog + discovery)
 *
 * Commands call bootstrap() exactly once; it is idempotent within a process.
 */

#ifndef RCLI_BOOTSTRAP_H
#define RCLI_BOOTSTRAP_H

#include <string>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/network/rac_environment.h"

typedef struct rac_telemetry_manager rac_telemetry_manager_t;

namespace rcli {

/** Global flags shared by all subcommands (parsed in main.cpp). */
struct GlobalOptions {
    bool json = false;
    bool verbose = false;
    bool quiet = false;
    bool no_progress = false;
    std::string home_override;  // --home flag

    // Control-plane connection. Empty defaults preserve the historical
    // offline development-mode behavior exactly. CLI11 fills these from
    // --base-url/--api-key/--environment with RUNANYWHERE_BASE_URL /
    // RUNANYWHERE_API_KEY / RUNANYWHERE_ENV env-var fallbacks (app.cpp).
    // resolve_connection() also accepts RUNANYWHERE_ENVIRONMENT as an alias
    // for the environment name (keyless staging remains valid).
    std::string environment;  // dev|development|staging|prod|production ("" → dev)
    std::string base_url;     // staging may omit (baked URL); prod requires https
    std::string api_key;      // staging may omit (keyless); prod requires ≥10 chars
};

/**
 * Validated control-plane connection resolved from GlobalOptions.
 * bootstrap() threads these values into rac_state / rac_sdk_config so the
 * commons auth, device-registration, and telemetry paths can read them.
 */
struct Connection {
    rac_environment_t environment = RAC_ENV_DEVELOPMENT;
    std::string base_url;
    std::string api_key;
};

/**
 * Resolve + validate the connection flags client-side (before any network
 * call). On failure fills `error` with an actionable message and returns
 * RAC_ERROR_INVALID_CONFIGURATION.
 *
 * Rules (mirrors commons rac_validate_api_key / rac_validate_base_url):
 *   - dev (default): no credentials allowed — pass --environment staging to
 *     target a real control plane (localhost is allowed on staging).
 *   - staging: keyless OK (baked staging URL / PUBLIC-org); optional key+URL.
 *   - prod: api key + https base URL required; localhost rejected.
 *
 * Env aliases: RUNANYWHERE_ENV (CLI11) and RUNANYWHERE_ENVIRONMENT (fallback).
 */
rac_result_t resolve_connection(const GlobalOptions& options, Connection* out, std::string* error);

/** Resolved environment after bootstrap. */
struct Bootstrapped {
    std::string home;        // RunAnywhere home (storage base dir)
    std::string models_dir;  // commons-derived models directory
};

/**
 * Initialize the SDK for CLI use. Logs go to stderr at WARNING by default
 * (DEBUG with --verbose, ERROR with --quiet).
 *
 * @return RAC_SUCCESS or the first failing step's error code.
 */
rac_result_t bootstrap(const GlobalOptions& options, Bootstrapped* out);

/** rac_shutdown() wrapper; safe to call when bootstrap never ran. */
void shutdown();

/**
 * The process telemetry manager created by bootstrap() (NULL if telemetry was
 * not initialized, e.g. no creds). Exposed for the live telemetry integration
 * test, which overrides its HTTP callback to observe the backend's response.
 */
rac_telemetry_manager_t* active_telemetry_manager();

}  // namespace rcli

#endif  // RCLI_BOOTSTRAP_H
