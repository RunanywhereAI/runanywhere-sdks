/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform-agnostic network availability check for routing decisions.
 */
package com.runanywhere.sdk.routing

/**
 * Check if the device has a working internet connection right now.
 *
 * Each platform provides its own implementation:
 * - Android: uses ConnectivityManager via NetworkConnectivity
 * - JVM: returns true (desktop/server environments assumed connected)
 */
expect fun isNetworkAvailable(): Boolean
