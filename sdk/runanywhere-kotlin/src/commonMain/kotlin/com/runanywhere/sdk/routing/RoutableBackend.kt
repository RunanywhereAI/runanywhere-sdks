/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Interface for backends participating in hybrid routing.
 */
package com.runanywhere.sdk.routing

/**
 * Implemented by any backend that wants to participate in the hybrid router.
 *
 * The backend declares its own descriptors — conditions are never injected from outside.
 * This is the "backend owns its routing contract" principle.
 *
 * To add a new provider: implement this interface (and the capability-specific interface
 * like STTBackend), then call HybridRouterRegistry.register(). Nothing else changes.
 */
interface RoutableBackend {
    /**
     * Returns all BackendDescriptors this backend supports.
     * Called once at registration; results are cached by the registry.
     *
     * A backend handling both STT and TTS returns two descriptors.
     */
    fun descriptors(): List<BackendDescriptor>
}
