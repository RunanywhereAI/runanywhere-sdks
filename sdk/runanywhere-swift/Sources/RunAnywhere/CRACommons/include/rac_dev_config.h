/**
 * @file rac_dev_config.h
 * @brief Development mode configuration API
 *
 * Provides access to development mode configuration values.
 * The actual values are defined in development_config.cpp which is git-ignored.
 *
 * This allows:
 * - Cross-platform sharing of dev config (iOS, Android, Flutter)
 * - Git-ignored secrets with template for developers
 * - Consistent development environment across SDKs
 *
 * Security Model:
 * - development_config.cpp is in .gitignore (not committed to main branch)
 * - Real values are ONLY in release tags (for SPM/Maven distribution)
 * - Used ONLY when SDK is in .development mode
 * - Backend validates build token via POST /api/v1/devices/register/dev
 */

#ifndef RAC_DEV_CONFIG_H
#define RAC_DEV_CONFIG_H

#include <stdbool.h>

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// Development Configuration API

/**
 * @brief Check if development config is available
 * @return true if development config is properly configured
 */
RAC_API bool rac_dev_config_is_available(void);

/**
 * @brief Get Supabase project URL for development mode
 * @return URL string (static, do not free)
 */
RAC_API const char* rac_dev_config_get_supabase_url(void);

/**
 * @brief Get Supabase anon key for development mode
 * @return API key string (static, do not free)
 */
RAC_API const char* rac_dev_config_get_supabase_key(void);

/**
 * @brief Get build token for development mode
 * @return Build token string (static, do not free)
 */
RAC_API const char* rac_dev_config_get_build_token(void);

// Convenience Functions

/**
 * @brief Check if Supabase config is valid
 * @return true if URL and key are non-empty
 */
RAC_API bool rac_dev_config_has_supabase(void);

/**
 * @brief Check if build token is valid
 * @return true if build token is non-empty
 */
RAC_API bool rac_dev_config_has_build_token(void);

// Usability Checks (canonical, shared by all SDKs)

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
