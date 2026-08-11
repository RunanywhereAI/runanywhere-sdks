package com.runanywhere.sdk.foundation.bridge.extensions

import java.security.GeneralSecurityException
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull

class CppBridgePlatformAdapterSecureStorageTest {
    @Test
    fun `clean secure-storage miss remains null`() {
        CppBridgePlatformAdapter.setPlatformStorage(FakeStorage())

        assertNull(CppBridgePlatformAdapter.secureGetCallback("missing"))
    }

    @Test
    fun `authenticated read failure propagates to JNI boundary`() {
        CppBridgePlatformAdapter.setPlatformStorage(
            FakeStorage(
                getValue = { throw GeneralSecurityException("authentication failed") },
            ),
        )

        assertFailsWith<GeneralSecurityException> {
            CppBridgePlatformAdapter.secureGetCallback("credential")
        }
    }

    @Test
    fun `failed durable delete is reported`() {
        CppBridgePlatformAdapter.setPlatformStorage(
            FakeStorage(deleteValue = { false }),
        )

        assertFalse(CppBridgePlatformAdapter.secureDeleteCallback("credential"))
    }

    @Test
    fun `failed durable clear propagates`() {
        CppBridgePlatformAdapter.setPlatformStorage(
            FakeStorage(clearValue = { error("commit failed") }),
        )

        assertFailsWith<IllegalStateException> {
            CppBridgePlatformAdapter.clearSecureStorage()
        }
    }

    private class FakeStorage(
        private val getValue: (String) -> ByteArray? = { null },
        private val deleteValue: (String) -> Boolean = { true },
        private val clearValue: () -> Unit = {},
    ) : CppBridgePlatformAdapter.PlatformSecureStorage {
        override fun get(key: String): ByteArray? = getValue(key)

        override fun set(key: String, value: ByteArray): Boolean = true

        override fun delete(key: String): Boolean = deleteValue(key)

        override fun clear() = clearValue()
    }
}
