/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CppBridgePlatformAdapterRegisterTest {
    @After
    fun tearDown() {
        CppBridgePlatformAdapter.unregister()
    }

    @Test
    fun `onPlatformAdapterRegisterResult throws when commons refuses the adapter`() {
        val error =
            assertThrows(SDKException::class.java) {
                CppBridgePlatformAdapter.onPlatformAdapterRegisterResult(
                    RunAnywhereBridge.RAC_ERROR_INVALID_PARAMETER,
                )
            }
        assertEquals(RunAnywhereBridge.RAC_ERROR_INVALID_PARAMETER, error.cAbiCode)
        assertFalse(CppBridgePlatformAdapter.isRegistered())
    }

    @Test
    fun `onPlatformAdapterRegisterResult marks the adapter registered on success`() {
        CppBridgePlatformAdapter.onPlatformAdapterRegisterResult(RunAnywhereBridge.RAC_SUCCESS)
        assertTrue(CppBridgePlatformAdapter.isRegistered())
    }
}
