/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ShutdownFailureCollectorTest {
    @Test
    fun `teardown retains first sanitized failure and continues cleanup`() {
        val failures = ShutdownFailureCollector()
        var laterCleanupRan = false

        assertFalse(failures.captureNativeShutdown { -1 })
        assertTrue(
            failures.capture("Later cleanup failed") {
                laterCleanupRan = true
            },
        )
        failures.capture("Platform adapter teardown failed") {
            throw IllegalArgumentException("private platform detail")
        }

        assertTrue(laterCleanupRan)
        val error = assertFailsWith<IllegalStateException> { failures.throwIfAny() }
        assertEquals("Native SDK shutdown failed", error.message)
        assertEquals(listOf("Platform adapter teardown failed"), error.suppressed.map { it.message })
    }
}
