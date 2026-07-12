package com.runanywhere.runanywhereai.data.security

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.state.GlobalState
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.GeneralSecurityException
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class SensitivePreferenceRepositoryMigrationInstrumentedTest {
    private lateinit var context: ScopedPreferencesContext

    @Before
    fun setUp() {
        val targetContext = InstrumentationRegistry.getInstrumentation().targetContext
        context = ScopedPreferencesContext(targetContext, "migration_${UUID.randomUUID()}")
        CloudProviderRepository.resetForTesting()
        SettingsRepository.resetForTesting()
    }

    @After
    fun tearDown() {
        CloudProviderRepository.resetForTesting()
        SettingsRepository.resetForTesting()
        preferenceNames.forEach { context.deleteSharedPreferences(it) }
        context.noBackupFilesDir.deleteRecursively()
    }

    @Test
    fun cloudRepositoryMigratesRealLegacyEntryAndRerunsFromEncryptedStorage() {
        val encoded =
            "[{\"id\":\"migration-provider\",\"label\":\"Migration provider\",\"preset\":\"OPENAI\"," +
                "\"model\":\"whisper-1\",\"apiKey\":\"credential-value\"," +
                "\"baseUrl\":\"https://api.openai.com\"}]"
        val legacy = context.getSharedPreferences(CLOUD_LEGACY_PREFS, Context.MODE_PRIVATE)
        assertTrue(legacy.edit().putString(PROVIDERS_KEY, encoded).commit())

        CloudProviderRepository.initialize(context)

        assertEquals(1, CloudProviderRepository.providers.size)
        assertFalse(legacy.contains(PROVIDERS_KEY))
        assertEquals(
            encoded,
            securePreferences(context, CLOUD_SECURE_PREFS).getString(PROVIDERS_KEY),
        )
        val ciphertext = requireNotNull(rawSecureStore(CLOUD_SECURE_PREFS).read(PROVIDERS_KEY))
        assertNotEquals(encoded, ciphertext.toString(StandardCharsets.UTF_8))
        assertFalse(ciphertext.toString(StandardCharsets.UTF_8).contains("credential-value"))

        CloudProviderRepository.resetForTesting()
        CloudProviderRepository.initialize(context)

        assertEquals(1, CloudProviderRepository.providers.size)
        assertFalse(legacy.contains(PROVIDERS_KEY))
    }

    @Test
    fun cloudRepositoryRetainsMalformedLegacyEntryWithoutEncryptingIt() {
        val legacy = context.getSharedPreferences(CLOUD_LEGACY_PREFS, Context.MODE_PRIVATE)
        assertTrue(legacy.edit().putString(PROVIDERS_KEY, "not-provider-json").commit())

        CloudProviderRepository.initialize(context)

        assertTrue(CloudProviderRepository.providers.isEmpty())
        assertEquals("not-provider-json", legacy.getString(PROVIDERS_KEY, null))
        assertFalse(securePreferences(context, CLOUD_SECURE_PREFS).contains(PROVIDERS_KEY))
    }

    @Test
    fun cloudRepositoryRetainsLegacyEntryWhenEncryptedStorageCannotOpen() {
        val legacy = context.getSharedPreferences(CLOUD_LEGACY_PREFS, Context.MODE_PRIVATE)
        assertTrue(legacy.edit().putString(PROVIDERS_KEY, "[]").commit())

        CloudProviderRepository.initialize(context) { storageContext, name ->
            unavailableSecurePreferences(storageContext, name)
        }

        assertTrue(CloudProviderRepository.providers.isEmpty())
        assertEquals("[]", legacy.getString(PROVIDERS_KEY, null))
    }

    @Test
    fun settingsRepositoryMigratesTrimmedTokenAndRerunsFromEncryptedStorage() {
        val legacy = context.getSharedPreferences(SETTINGS_LEGACY_PREFS, Context.MODE_PRIVATE)
        assertTrue(legacy.edit().putString(HF_TOKEN_KEY, "  repository-token-value  ").commit())

        SettingsRepository.initialize(context)

        assertEquals("repository-token-value", SettingsRepository.settings.hfToken)
        assertFalse(legacy.contains(HF_TOKEN_KEY))
        assertEquals(
            "repository-token-value",
            securePreferences(context, SETTINGS_SECURE_PREFS).getString(HF_TOKEN_KEY),
        )

        SettingsRepository.resetForTesting()
        SettingsRepository.initialize(context)

        assertEquals("repository-token-value", SettingsRepository.settings.hfToken)
        assertFalse(legacy.contains(HF_TOKEN_KEY))
    }

    @Test
    fun settingsRepositoryRetainsBlankLegacyTokenAsInvalid() {
        val legacy = context.getSharedPreferences(SETTINGS_LEGACY_PREFS, Context.MODE_PRIVATE)
        assertTrue(legacy.edit().putString(HF_TOKEN_KEY, "   ").commit())

        SettingsRepository.initialize(context)

        assertEquals("", SettingsRepository.settings.hfToken)
        assertEquals("   ", legacy.getString(HF_TOKEN_KEY, null))
        assertFalse(securePreferences(context, SETTINGS_SECURE_PREFS).contains(HF_TOKEN_KEY))
    }

    @Test
    fun settingsRepositoryRetainsLegacyTokenWhenEncryptedStorageCannotOpen() {
        val legacy = context.getSharedPreferences(SETTINGS_LEGACY_PREFS, Context.MODE_PRIVATE)
        assertTrue(legacy.edit().putString(HF_TOKEN_KEY, "repository-token-value").commit())

        SettingsRepository.initialize(context) { storageContext, name ->
            unavailableSecurePreferences(storageContext, name)
        }

        assertEquals("", SettingsRepository.settings.hfToken)
        assertEquals("repository-token-value", legacy.getString(HF_TOKEN_KEY, null))
    }

    @Test
    fun securePreferencesRejectCiphertextMovedToAnotherKey() {
        val secure = securePreferences(context, TEST_SECURE_PREFS)
        assertTrue(secure.putString("source", "credential-value"))
        val raw = rawSecureStore(TEST_SECURE_PREFS)
        val ciphertext = requireNotNull(raw.read("source"))
        assertTrue(raw.write("destination", ciphertext))

        assertTrue(runCatching { secure.getString("destination") }.isFailure)
    }

    @Test
    fun securePreferencesRejectTamperedCiphertext() {
        val secure = securePreferences(context, TEST_SECURE_PREFS)
        assertTrue(secure.putString("credential", "credential-value"))
        val raw = rawSecureStore(TEST_SECURE_PREFS)
        val ciphertext = requireNotNull(raw.read("credential"))
        ciphertext[ciphertext.lastIndex] = (ciphertext.last().toInt() xor 0x01).toByte()
        assertTrue(raw.write("credential", ciphertext))

        assertTrue(runCatching { secure.getString("credential") }.isFailure)
        assertTrue(runCatching { secure.contains("credential") }.isFailure)
    }

    @Test
    fun securePreferencesRoundTripEmptyAndUnicodeValuesAcrossInstances() {
        val first = securePreferences(context, TEST_SECURE_PREFS)
        assertTrue(first.putString("empty", ""))
        assertTrue(first.putString("unicode", "token-\u0000-\uD83D\uDD10"))

        val reopened = securePreferences(context, TEST_SECURE_PREFS)
        assertEquals("", reopened.getString("empty"))
        assertEquals("token-\u0000-\uD83D\uDD10", reopened.getString("unicode"))
    }

    @Test
    fun securePreferencesDeletesDeprecatedStoreWithoutMigratingValues() {
        val deprecated = context.getSharedPreferences(TEST_SECURE_PREFS, Context.MODE_PRIVATE)
        assertTrue(deprecated.edit().putString("credential", "deprecated-value").commit())

        val secure = securePreferences(context, TEST_SECURE_PREFS)

        assertFalse(
            context.getSharedPreferences(TEST_SECURE_PREFS, Context.MODE_PRIVATE).contains("credential"),
        )
        assertNull(secure.getString("credential"))
    }

    @Test
    fun securePreferencesFailsClosedWhenDeprecatedStoreCannotBeDeleted() {
        val deletionFailureContext = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this

            override fun deleteSharedPreferences(name: String): Boolean = false
        }

        assertTrue(
            runCatching { securePreferences(deletionFailureContext, TEST_SECURE_PREFS) }.isFailure,
        )
    }

    private fun rawSecureStore(name: String): NoBackupCiphertextStore =
        NoBackupCiphertextStore(context, securePreferencesDirectoryName(name))

    private fun unavailableSecurePreferences(
        @Suppress("UNUSED_PARAMETER") context: Context,
        @Suppress("UNUSED_PARAMETER") name: String,
    ): SecureStringPreferences = throw GeneralSecurityException("test-only secure storage failure")

    private class ScopedPreferencesContext(
        base: Context,
        private val prefix: String,
    ) : ContextWrapper(base) {
        override fun getApplicationContext(): Context = this

        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
            super.getSharedPreferences("${prefix}_$name", mode)

        override fun deleteSharedPreferences(name: String): Boolean =
            super.deleteSharedPreferences("${prefix}_$name")

        override fun getNoBackupFilesDir(): File =
            File(super.getNoBackupFilesDir(), prefix).apply { mkdirs() }
    }

    companion object {
        private const val CLOUD_LEGACY_PREFS = "cloud_providers"
        private const val CLOUD_SECURE_PREFS = "cloud_secure_providers"
        private const val SETTINGS_LEGACY_PREFS = "app_settings"
        private const val SETTINGS_SECURE_PREFS = "app_secure_settings"
        private const val TEST_SECURE_PREFS = "test_secure_preferences"
        private const val PROVIDERS_KEY = "providers"
        private const val HF_TOKEN_KEY = "hf_token"

        private val preferenceNames = listOf(
            CLOUD_LEGACY_PREFS,
            CLOUD_SECURE_PREFS,
            SETTINGS_LEGACY_PREFS,
            SETTINGS_SECURE_PREFS,
            TEST_SECURE_PREFS,
        )

        @JvmStatic
        @BeforeClass
        fun waitForApplicationInitialization() {
            val deadline = System.currentTimeMillis() + 60_000
            while (!GlobalState.ready && GlobalState.initError == null && System.currentTimeMillis() < deadline) {
                Thread.sleep(50)
            }
            assertTrue(
                "Application initialization must settle before repository singletons are reset",
                GlobalState.ready || GlobalState.initError != null,
            )
        }
    }
}
