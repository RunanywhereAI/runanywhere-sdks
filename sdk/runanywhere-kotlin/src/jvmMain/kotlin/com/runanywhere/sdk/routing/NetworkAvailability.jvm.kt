/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM network availability — lightweight socket check.
 */
package com.runanywhere.sdk.routing

import java.net.InetSocketAddress
import java.net.Socket

actual fun isNetworkAvailable(): Boolean {
    return try {
        Socket().use { socket ->
            socket.connect(InetSocketAddress("8.8.8.8", 53), 1000)
        }
        true
    } catch (_: Exception) {
        false
    }
}
