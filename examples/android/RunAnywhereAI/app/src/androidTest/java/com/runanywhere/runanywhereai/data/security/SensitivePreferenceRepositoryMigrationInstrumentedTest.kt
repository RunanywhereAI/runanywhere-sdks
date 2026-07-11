package com.runanywhere.runanywhereai.data.security

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.data.cloud.CloudPreset
import com.runanywhere.runanywhereai.data.cloud.CloudProviderConfig
import com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.state.GlobalState
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith
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
        preferenceNames.forEach(context::deleteSharedPreferences)
    }

    @Test
    fun cloudRepositoryMigratesRealLegacyEntryAndRerunsFromEncryptedStorage() {
        val provider = CloudProviderConfig(
            id = "migration-provider",
            label = "Migration provider",
            preset = CloudPreset.OPENAI,
            model = "whisper-1",
            apiKey = "credential-value",
            baseUrl = "https://api.openai.com",
        )
        val encoded = Json.encodeToString(listOf(provider))
        val legacy = context.getSharedPreferences(CLOUD_LEGACY_PREFS, Context.MODE_PRIVATE)
        assertTrue(legacy.edit().putString(PROVIDERS_KEY, encoded).commit())

        CloudProviderRepository.initialize(context)

        assertEquals(listOf(provider), CloudProviderRepository.providers)
        assertFalse(legacy.contains(PROVIDERS_KEY))
        assertEquals(
            encoded,
            securePreferences(context, CLOUD_SECURE_PREFS).getString(PROVIDERS_KEY, null),
        )

        CloudProviderRepository.resetForTesting()
        CloudProviderRepository.initialize(context)

        assertEquals(listOf(provider), CloudProviderRepository.providers)
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

        CloudProviderRepository.initialize(context, ::unavailableSecurePreferences)

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
            securePreferences(context, SETTINGS_SECURE_PREFS).getString(HF_TOKEN_KEY, null),
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

        SettingsRepository.initialize(context, ::unavailableSecurePreferences)

        assertEquals("", SettingsRepository.settings.hfToken)
        assertEquals("repository-token-value", legacy.getString(HF_TOKEN_KEY, null))
    }

    private fun unavailableSecurePreferences(
        @Suppress("UNUSED_PARAMETER") context: Context,
        @Suppress("UNUSED_PARAMETER") name: String,
    ): SharedPreferences = throw GeneralSecurityException("test-only secure storage failure")

    private class ScopedPreferencesContext(
        base: Context,
        private val prefix: String,
    ) : ContextWrapper(base) {
        override fun getApplicationContext(): Context = this

        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
            super.getSharedPreferences("${prefix}_$name", mode)

        override fun deleteSharedPreferences(name: String): Boolean =
            super.deleteSharedPreferences("${prefix}_$name")
    }

    companion object {
        private const val CLOUD_LEGACY_PREFS = "cloud_providers"
        private const val CLOUD_SECURE_PREFS = "cloud_secure_providers"
        private const val SETTINGS_LEGACY_PREFS = "app_settings"
        private const val SETTINGS_SECURE_PREFS = "app_secure_settings"
        private const val PROVIDERS_KEY = "providers"
        private const val HF_TOKEN_KEY = "hf_token"

        private val preferenceNames = listOf(
            CLOUD_LEGACY_PREFS,
            CLOUD_SECURE_PREFS,
            SETTINGS_LEGACY_PREFS,
            SETTINGS_SECURE_PREFS,
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
