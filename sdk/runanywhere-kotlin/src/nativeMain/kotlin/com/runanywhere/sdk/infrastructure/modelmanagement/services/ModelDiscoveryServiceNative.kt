package com.runanywhere.sdk.infrastructure.modelmanagement.services

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo

private val logger = SDKLogger("ModelDiscoveryNative")

/**
 * Native implementation of bundle model discovery
 *
 * On native platforms, bundled models are typically placed in known directories
 * alongside the executable. This implementation returns an empty list as
 * native bundle discovery requires platform-specific implementations.
 */
actual suspend fun discoverBundleModelsPlatform(): List<ModelInfo> {
    // Native platforms typically don't have a standard bundle/resource system
    // Models are usually placed in known directories relative to the executable
    // Specific implementations can override this for their platform

    logger.debug("Native bundle model discovery: no bundled models (use filesystem discovery)")

    return emptyList()
}
