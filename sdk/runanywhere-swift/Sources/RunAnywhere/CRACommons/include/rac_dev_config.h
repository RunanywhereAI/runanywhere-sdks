/**
 * @file rac_dev_config.h
 * @brief Development mode configuration API
 *
 * Provides access to the baked staging backend base URL and the canonical
 * usability checks. Only a neutral backend base URL is ever baked — no
 * credentials, project refs, or tokens. The SDK reaches the backend solely
 * through this base URL.
 *
 * Security Model:
 * - development_config.cpp is in .gitignore (not committed to main branch)
 * - Normal, CI, and release builds never compile the ignored local file
 * - Local opt-in requires RAC_INCLUDE_LOCAL_DEV_CONFIG=ON and must never be packaged
 */

#ifndef RAC_DEV_CONFIG_H
#define RAC_DEV_CONFIG_H

#include <stdbool.h>

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Development Configuration API
// =============================================================================

/**
 * @brief Get the baked staging backend base URL
 *
 * Team builds bake the staging URL via the git-ignored development_config.cpp
 * so callers can init with environment=staging and nothing else. Open-source
 * builds keep the placeholder and must pass a base URL explicitly.
 *
 * @return URL string or placeholder (static, do not free)
 */
RAC_API const char* rac_dev_config_get_staging_base_url(void);

// =============================================================================
// Usability Checks (canonical, shared by all SDKs)
// =============================================================================

/**
 * @brief Whether a baked-in credential string is usable: non-empty and not a
 *        scaffolding placeholder ("your_...", "<your...", "replace_me",
 *        "placeholder").
 * @param value Credential string (may be NULL → not usable)
 * @return true if the credential looks real and usable
 */
RAC_API bool rac_dev_config_is_usable_credential(const char* value);

/**
 * @brief Whether a string is a usable absolute http(s) URL.
 * @param value URL string (may be NULL → not usable)
 * @return true if the URL is well-formed and usable
 */
RAC_API bool rac_dev_config_is_usable_http_url(const char* value);

#ifdef __cplusplus
}
#endif

#endif  // RAC_DEV_CONFIG_H
