package com.runanywhere.runanywhereai.data.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StringPreferenceMigrationTest {
    @Test
    fun `legacy value is verified in secure storage before removal`() {
        var secure: String? = null
        var legacy: String? = "secret"

        val result = migrateSensitiveString(
            readSecure = { secure },
            readLegacy = { legacy },
            writeSecure = { secure = it; true },
            removeLegacy = { legacy = null; true },
        )

        assertEquals("secret", secure)
        assertNull(legacy)
        assertEquals("secret", result.value)
        assertTrue(result.migrated)
        assertNull(result.failure)
    }

    @Test
    fun `failed secure commit retains legacy value for retry`() {
        var legacy: String? = "secret"

        val result = migrateSensitiveString(
            readSecure = { null },
            readLegacy = { legacy },
            writeSecure = { false },
            removeLegacy = { legacy = null; true },
        )

        assertEquals("secret", legacy)
        assertNull(result.value)
        assertFalse(result.migrated)
        assertEquals(PreferenceMigrationFailure.SECURE_WRITE, result.failure)
    }

    @Test
    fun `failed readback verification retains legacy value`() {
        var legacy: String? = "secret"

        val result = migrateSensitiveString(
            readSecure = { null },
            readLegacy = { legacy },
            writeSecure = { true },
            removeLegacy = { legacy = null; true },
        )

        assertEquals("secret", legacy)
        assertEquals(PreferenceMigrationFailure.SECURE_VERIFY, result.failure)
    }

    @Test
    fun `migration is idempotent and does not rewrite an existing secure value`() {
        var secure: String? = null
        var legacy: String? = "secret"
        var writes = 0
        fun migrate() = migrateSensitiveString(
            readSecure = { secure },
            readLegacy = { legacy },
            writeSecure = { writes += 1; secure = it; true },
            removeLegacy = { legacy = null; true },
        )

        val first = migrate()
        val second = migrate()

        assertTrue(first.migrated)
        assertFalse(second.migrated)
        assertEquals("secret", second.value)
        assertEquals(1, writes)
    }

    @Test
    fun `invalid legacy value is retained and never encrypted`() {
        var legacy: String? = "not-json"
        var writes = 0

        val result = migrateSensitiveString(
            readSecure = { null },
            readLegacy = { legacy },
            writeSecure = { writes += 1; true },
            removeLegacy = { legacy = null; true },
            validate = { it.startsWith("[") && it.endsWith("]") },
        )

        assertEquals("not-json", legacy)
        assertEquals(0, writes)
        assertEquals(PreferenceMigrationFailure.LEGACY_VALUE_INVALID, result.failure)
    }

    @Test
    fun `failed legacy cleanup keeps verified secure value usable`() {
        var secure: String? = null
        val result = migrateSensitiveString(
            readSecure = { secure },
            readLegacy = { "secret" },
            writeSecure = { secure = it; true },
            removeLegacy = { false },
        )

        assertEquals("secret", result.value)
        assertTrue(result.migrated)
        assertEquals(PreferenceMigrationFailure.LEGACY_REMOVE, result.failure)
    }
}
