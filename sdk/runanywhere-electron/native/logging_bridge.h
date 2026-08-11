// logging_bridge.h — the commons structured logger, exposed to JS.
//
// Commons routes every record through the platform adapter's `log` slot
// (`rac_logger.cpp` -> `adapter->log`), so the two adapters in this package call
// `rac_electron_forward_log` from that slot instead of writing to stderr
// themselves. That keeps one place deciding whether a record is printed, handed
// to a JS subscriber, or both.
#ifndef RUNANYWHERE_ELECTRON_LOGGING_BRIDGE_H
#define RUNANYWHERE_ELECTRON_LOGGING_BRIDGE_H

#include <napi.h>

#include "rac/core/rac_types.h"

namespace rac_electron {

void RegisterLoggingBridge(Napi::Env env, Napi::Object exports);

/** The C++ half of {@link rac_electron_forward_log}. */
void ForwardLog(rac_log_level_t level, const char* category, const char* message);

/** Release the JS subscriber, if any. Called from the addon's shutdown path. */
void ShutdownLoggingBridge();

}  // namespace rac_electron

#ifdef __cplusplus
extern "C" {
#endif

/**
 * One record from commons. Safe to call from any thread and before any
 * subscriber exists; writes to stderr while the local sink is enabled (the
 * default) and forwards to the JS subscriber when one is attached.
 */
void rac_electron_forward_log(rac_log_level_t level, const char* category, const char* message);

#ifdef __cplusplus
}
#endif

#endif  // RUNANYWHERE_ELECTRON_LOGGING_BRIDGE_H
