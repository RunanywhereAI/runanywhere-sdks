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

typedef struct rac_telemetry_manager rac_telemetry_manager_t;

namespace rcli {

/** Global flags shared by all subcommands (parsed in main.cpp). */
struct GlobalOptions {
    bool json = false;
    bool verbose = false;
    bool quiet = false;
    bool no_progress = false;
    std::string home_override;  // --home flag
};

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
