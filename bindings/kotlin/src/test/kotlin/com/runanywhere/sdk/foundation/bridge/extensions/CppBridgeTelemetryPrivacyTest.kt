package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.bridge.HTTPClientAdapter
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CppBridgeTelemetryPrivacyTest {
    @Test
    fun `unregister clears copied credentials without a native manager`() {
        CppBridgeTelemetry.setApiKey("copied-secret")
        CppBridgeTelemetry.setBaseUrl("https://private.example")

        CppBridgeTelemetry.unregister()

        assertNull(CppBridgeTelemetry.getApiKey())
        assertNull(CppBridgeTelemetry.getBaseUrl())
    }

    @Test
    fun `HTTP reset clears copied credentials before reinitialization`() =
        runBlocking {
            HTTPClientAdapter.configure("https://private.example", "copied-secret")
            assertTrue(HTTPClientAdapter.isConfigured)
            assertTrue(HTTPClientAdapter.hasUsableConfiguration)

            HTTPClientAdapter.reset()

            assertFalse(HTTPClientAdapter.isConfigured)
            assertFalse(HTTPClientAdapter.hasUsableConfiguration)
        }
}
