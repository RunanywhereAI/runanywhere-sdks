/**
 * @file desktop_internal.h
 * @brief Internal declarations shared between the desktop adapter TUs.
 */

#ifndef RAC_DESKTOP_INTERNAL_H
#define RAC_DESKTOP_INTERNAL_H

#include <string>

#include "rac/core/rac_types.h"

namespace rac::desktop {

// --- desktop_secure_store.cpp -----------------------------------------------

/** Replace the secure-store directory (empty → default config dir). */
void secure_store_set_dir(const std::string& dir);

/** Adapter slots (signatures match rac_platform_adapter_t). */
rac_result_t secure_get(const char* key, char** out_value, void* user_data);
rac_result_t secure_set(const char* key, const char* value, void* user_data);
rac_result_t secure_delete(const char* key, void* user_data);

// --- shared path helpers (desktop_adapter.cpp) -------------------------------

/** User home/profile directory; empty string when unresolvable. */
std::string home_dir();

/** XDG config directory on POSIX, AppData on Windows (no trailing slash). */
std::string default_config_dir();

/** XDG data directory on POSIX, LocalAppData on Windows (no trailing slash). */
std::string default_data_dir();

}  // namespace rac::desktop

#endif  // RAC_DESKTOP_INTERNAL_H
