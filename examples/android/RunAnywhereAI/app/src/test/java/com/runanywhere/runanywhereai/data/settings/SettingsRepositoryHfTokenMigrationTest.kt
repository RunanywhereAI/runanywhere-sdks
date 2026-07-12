package com.runanywhere.runanywhereai.data.settings

import android.content.SharedPreferences
import com.runanywhere.runanywhereai.data.security.SecureStringPreferences
import com.runanywhere.runanywhereai.util.RACLog
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SettingsRepositoryHfTokenMigrationTest {
    private var loggingWasEnabled = false

    @Before
    fun setUp() {
        SettingsRepository.resetForTesting()
        loggingWasEnabled = RACLog.enabled
        RACLog.enabled = false
    }

    @After
    fun tearDown() {
        SettingsRepository.resetForTesting()
        RACLog.enabled = loggingWasEnabled
    }

    @Test
    fun `clear removes legacy token left by an earlier migration cleanup failure`() {
        val legacy = FakeSharedPreferences(mapOf(HF_TOKEN_KEY to OLD_TOKEN)).apply {
            failedHfTokenRemovalCommits = 1
        }
        val secure = FakeSecureStringPreferences()

        SettingsRepository.initializeForTesting(legacy, secure)

        assertEquals(OLD_TOKEN, SettingsRepository.settings.hfToken)
        assertEquals(OLD_TOKEN, legacy.getString(HF_TOKEN_KEY, null))

        assertTrue(SettingsRepository.setHfToken("").isSuccess)
        assertFalse(legacy.contains(HF_TOKEN_KEY))
        assertTrue(secure.contains(HF_TOKEN_KEY))
        assertEquals("", secure.getString(HF_TOKEN_KEY))

        SettingsRepository.resetForTesting()
        SettingsRepository.initializeForTesting(legacy, secure)

        assertEquals("", SettingsRepository.settings.hfToken)
        assertFalse(legacy.contains(HF_TOKEN_KEY))
    }

    @Test
    fun `secure clear tombstone prevents resurrection when legacy cleanup keeps failing`() {
        val legacy = FakeSharedPreferences(mapOf(HF_TOKEN_KEY to OLD_TOKEN)).apply {
            failedHfTokenRemovalCommits = 3
        }
        val secure = FakeSecureStringPreferences()

        SettingsRepository.initializeForTesting(legacy, secure)
        val clearResult = SettingsRepository.setHfToken("")

        assertTrue(clearResult.isFailure)
        assertEquals("", SettingsRepository.settings.hfToken)
        assertEquals("", secure.getString(HF_TOKEN_KEY))
        assertEquals(OLD_TOKEN, legacy.getString(HF_TOKEN_KEY, null))

        SettingsRepository.resetForTesting()
        SettingsRepository.initializeForTesting(legacy, secure)

        assertEquals("", SettingsRepository.settings.hfToken)
        assertEquals(OLD_TOKEN, legacy.getString(HF_TOKEN_KEY, null))
    }

    @Test
    fun `update replaces stale migration source and remains authoritative after reinitialize`() {
        val legacy = FakeSharedPreferences(mapOf(HF_TOKEN_KEY to OLD_TOKEN)).apply {
            failedHfTokenRemovalCommits = 1
        }
        val secure = FakeSecureStringPreferences()

        SettingsRepository.initializeForTesting(legacy, secure)

        assertTrue(SettingsRepository.setHfToken(NEW_TOKEN).isSuccess)
        assertFalse(legacy.contains(HF_TOKEN_KEY))
        assertEquals(NEW_TOKEN, secure.getString(HF_TOKEN_KEY))

        SettingsRepository.resetForTesting()
        SettingsRepository.initializeForTesting(legacy, secure)

        assertEquals(NEW_TOKEN, SettingsRepository.settings.hfToken)
        assertFalse(legacy.contains(HF_TOKEN_KEY))
    }

    private class FakeSharedPreferences(
        initialValues: Map<String, Any?> = emptyMap(),
    ) : SharedPreferences {
        private val values = initialValues.toMutableMap()

        var failedHfTokenRemovalCommits: Int = 0

        override fun getAll(): MutableMap<String, *> = values.toMutableMap()

        override fun getString(key: String, defValue: String?): String? =
            values[key] as? String ?: defValue

        @Suppress("UNCHECKED_CAST")
        override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? =
            (values[key] as? Set<String>)?.toMutableSet() ?: defValues

        override fun getInt(key: String, defValue: Int): Int = values[key] as? Int ?: defValue

        override fun getLong(key: String, defValue: Long): Long = values[key] as? Long ?: defValue

        override fun getFloat(key: String, defValue: Float): Float = values[key] as? Float ?: defValue

        override fun getBoolean(key: String, defValue: Boolean): Boolean =
            values[key] as? Boolean ?: defValue

        override fun contains(key: String): Boolean = values.containsKey(key)

        override fun edit(): SharedPreferences.Editor = Editor()

        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener,
        ) = Unit

        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener,
        ) = Unit

        private inner class Editor : SharedPreferences.Editor {
            private val updates = mutableMapOf<String, Any?>()
            private val removals = mutableSetOf<String>()
            private var clearRequested = false

            override fun putString(key: String, value: String?): SharedPreferences.Editor = apply {
                updates[key] = value
                removals.remove(key)
            }

            override fun putStringSet(
                key: String,
                values: MutableSet<String>?,
            ): SharedPreferences.Editor = apply {
                updates[key] = values?.toSet()
                removals.remove(key)
            }

            override fun putInt(key: String, value: Int): SharedPreferences.Editor = apply {
                updates[key] = value
                removals.remove(key)
            }

            override fun putLong(key: String, value: Long): SharedPreferences.Editor = apply {
                updates[key] = value
                removals.remove(key)
            }

            override fun putFloat(key: String, value: Float): SharedPreferences.Editor = apply {
                updates[key] = value
                removals.remove(key)
            }

            override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor = apply {
                updates[key] = value
                removals.remove(key)
            }

            override fun remove(key: String): SharedPreferences.Editor = apply {
                removals += key
                updates.remove(key)
            }

            override fun clear(): SharedPreferences.Editor = apply {
                clearRequested = true
                updates.clear()
                removals.clear()
            }

            override fun commit(): Boolean {
                if (HF_TOKEN_KEY in removals && failedHfTokenRemovalCommits > 0) {
                    failedHfTokenRemovalCommits -= 1
                    return false
                }
                if (clearRequested) values.clear()
                removals.forEach(values::remove)
                updates.forEach { (key, value) ->
                    if (value == null) values.remove(key) else values[key] = value
                }
                return true
            }

            override fun apply() {
                commit()
            }
        }
    }

    private class FakeSecureStringPreferences : SecureStringPreferences {
        private val values = mutableMapOf<String, String>()

        override fun getString(key: String): String? = values[key]

        override fun putString(key: String, value: String): Boolean {
            values[key] = value
            return true
        }

        override fun contains(key: String): Boolean = values.containsKey(key)
    }

    private companion object {
        const val HF_TOKEN_KEY = "hf_token"
        const val OLD_TOKEN = "old-token"
        const val NEW_TOKEN = "new-token"
    }
}
