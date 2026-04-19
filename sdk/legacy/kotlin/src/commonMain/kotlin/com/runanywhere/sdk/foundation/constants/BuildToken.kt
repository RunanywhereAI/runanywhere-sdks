package com.runanywhere.sdk.foundation.constants

/**
 * Build token for development mode device registration
 *
 * ⚠️ THIS FILE IS AUTO-GENERATED DURING RELEASES
 * ⚠️ DO NOT MANUALLY EDIT THIS FILE
 * ⚠️ THIS FILE IS IN .gitignore AND SHOULD NOT BE COMMITTED
 *
 * Security Model:
 * - This file is generated during release scripts
 * - Contains a cohort build token (format: bt_<uuid>_<timestamp>)
 * - Main branch: This file has a placeholder token
 * - Release tags: This file has a real token (for Maven distribution)
 * - Token is used ONLY when SDK is in DEVELOPMENT mode
 * - Backend validates token and can revoke it if abused
 *
 * Token Properties:
 * - Rotatable: Each release gets a new token
 * - Revocable: Backend can mark token as inactive
 * - Cohort-scoped: Not a secret, extractable but secured via backend validation
 * - Rate-limited: Backend enforces 100 req/min per device
 */
object BuildToken {
    /**
     * Development mode build token
     * Format: "bt_<uuid>_<timestamp>"
     *
     * This is a PLACEHOLDER token for development.
     * Real tokens are injected during SDK releases via release scripts
     */
    const val token = "bt_placeholder_for_development"
}
