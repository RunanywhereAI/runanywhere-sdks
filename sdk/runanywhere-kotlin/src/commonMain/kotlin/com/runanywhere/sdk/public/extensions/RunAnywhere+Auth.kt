/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for SDK authentication / device-registration state accessors.
 * Mirrors Swift's `RunAnywhere.{getUserId,getOrganizationId,isAuthenticated,
 * isDeviceRegistered,deviceId}` (Public/RunAnywhere.swift:106–140).
 *
 * The values are read directly from the C++ auth + device state via the
 * `rac_auth_*` thunks; Kotlin maintains no parallel cache.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere

/**
 * Get the current user ID from authentication state.
 *
 * @return User ID if authenticated, `null` otherwise.
 */
expect fun RunAnywhere.getUserId(): String?

/**
 * Get the current organization ID from authentication state.
 *
 * @return Organization ID if authenticated, `null` otherwise.
 */
expect fun RunAnywhere.getOrganizationId(): String?

/**
 * Check if the SDK is currently authenticated with a valid token.
 *
 * Equivalent to Swift's `RunAnywhere.isAuthenticated` static var.
 */
expect val RunAnywhere.isAuthenticated: Boolean

/**
 * Check if this device is registered with the backend.
 *
 * @return true if the device-registration handshake completed successfully.
 */
expect fun RunAnywhere.isDeviceRegistered(): Boolean

/**
 * The persistent device ID. Survives reinstalls (stored in keychain on
 * Apple platforms / EncryptedSharedPreferences on Android).
 *
 * @return Device ID or empty string if device hasn't been registered yet.
 */
expect val RunAnywhere.deviceId: String
