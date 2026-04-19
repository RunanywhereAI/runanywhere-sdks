/**
 * @file development_config.cpp.template
 * @brief Template for development mode configuration
 *
 * SETUP INSTRUCTIONS:
 * 1. Copy this file to development_config.cpp
 * 2. Fill in your development credentials
 * 3. development_config.cpp is git-ignored, so your secrets won't be committed
 *
 * For RunAnywhere team members:
 * - Get credentials from the team's secure credential storage
 * - Contact team lead for access to development credentials
 */

#include <cstring>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/network/rac_dev_config.h"

// =============================================================================
// Configuration Values - FILL IN YOUR CREDENTIALS BELOW
// =============================================================================

namespace {

// Supabase project URL for development device analytics
// Get this from: https://supabase.com/dashboard → Your Project → Settings → API
constexpr const char* SUPABASE_URL = "YOUR_SUPABASE_PROJECT_URL";

// Supabase anon/public API key
// Get this from: https://supabase.com/dashboard → Your Project → Settings → API → anon key
constexpr const char* SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY";

// Development mode build token
// Get this from your team's credential storage, or use a debug token for local dev
constexpr const char* BUILD_TOKEN = "YOUR_BUILD_TOKEN";

// Sentry DSN for crash reporting (optional)
// Get this from: https://sentry.io → Your Project → Settings → Client Keys (DSN)
// Set to nullptr if not using Sentry
constexpr const char* SENTRY_DSN = nullptr;

}  // anonymous namespace

// =============================================================================
// Public API Implementation (DO NOT MODIFY BELOW)
// =============================================================================

extern "C" {

bool rac_dev_config_is_available(void) {
    return SUPABASE_URL != nullptr && SUPABASE_ANON_KEY != nullptr &&
           std::strlen(SUPABASE_URL) > 0 && std::strlen(SUPABASE_ANON_KEY) > 0;
}

const char* rac_dev_config_get_supabase_url(void) {
    return SUPABASE_URL;
}

const char* rac_dev_config_get_supabase_key(void) {
    return SUPABASE_ANON_KEY;
}

const char* rac_dev_config_get_build_token(void) {
    return BUILD_TOKEN;
}

const char* rac_dev_config_get_sentry_dsn(void) {
    return SENTRY_DSN;
}

bool rac_dev_config_has_supabase(void) {
    return rac_dev_config_is_available();
}

bool rac_dev_config_has_build_token(void) {
    return BUILD_TOKEN != nullptr && std::strlen(BUILD_TOKEN) > 0;
}

}  // extern "C"
