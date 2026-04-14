/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android network availability check using ConnectivityManager.
 */
package com.runanywhere.sdk.routing

import com.runanywhere.sdk.platform.NetworkConnectivity

actual fun isNetworkAvailable(): Boolean = NetworkConnectivity.isNetworkAvailable()
