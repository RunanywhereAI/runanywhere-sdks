package com.runanywhere.runanywhereai.data.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.runanywhere.runanywhereai.BuildConfig
import com.runanywhere.runanywhereai.data.security.migrateSensitiveString
import com.runanywhere.runanywhereai.data.security.securePreferences
import com.runanywhere.runanywhereai.util.RACLog

object SettingsRepository {
    private const val PREFS = "app_settings"
    private const val SECURE_PREFS = "app_secure_settings"
    private const val KEY_TEMPERATURE = "temperature"
    private const val KEY_MAX_TOKENS = "max_tokens"
    private const val KEY_SYSTEM_PROMPT = "system_prompt"
    private const val KEY_STREAMING = "streaming"
    private const val KEY_DISABLE_THINKING = "disable_thinking"
    private const val KEY_TOOL_CALLING = "tool_calling_enabled"
    private const val LEGACY_KEY_WEB_SEARCH_DISCLOSURE = "web_search_disclosure_accepted"
    private const val KEY_WEB_SEARCH_CONSENT_SCOPE = "web_search_consent_scope_v2"
    private const val KEY_HF_TOKEN = "hf_token"

    private var prefs: SharedPreferences? = null
    private var securePrefs: SharedPreferences? = null

    var settings: AppSettings by mutableStateOf(AppSettings())
        private set

    fun initialize(context: Context) = initialize(context, ::securePreferences)

    internal fun initialize(
        context: Context,
        securePreferencesFactory: (Context, String) -> SharedPreferences,
    ) {
        if (prefs != null) return
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val secure = runCatching { securePreferencesFactory(context, SECURE_PREFS) }
            .onFailure { RACLog.w("Secure settings unavailable; credentials cannot be loaded or saved") }
            .getOrNull()
        initializePreferences(p, secure)
    }

    internal fun initializeForTesting(
        legacyPreferences: SharedPreferences,
        encryptedPreferences: SharedPreferences?,
    ) {
        if (prefs != null) return
        initializePreferences(legacyPreferences, encryptedPreferences)
    }

    private fun initializePreferences(
        p: SharedPreferences,
        secure: SharedPreferences?,
    ) {
        val hfToken = if (secure == null) {
            ""
        } else {
            val migration = migrateSensitiveString(
                readSecure = { secure.getString(KEY_HF_TOKEN, null) },
                readLegacy = { p.getString(KEY_HF_TOKEN, null) },
                writeSecure = { secure.edit().putString(KEY_HF_TOKEN, it).commit() },
                removeLegacy = { p.edit().remove(KEY_HF_TOKEN).commit() },
                normalize = { it.trim() },
                allowBlankSecureValue = true,
            )
            if (migration.failure != null) {
                RACLog.w("hf_token_migration_${migration.failure.name.lowercase()}")
            }
            securePrefs = secure
            migration.value.orEmpty()
        }
        prefs = p
        val acceptedWebSearchScope = p.getString(KEY_WEB_SEARCH_CONSENT_SCOPE, "").orEmpty()
        val currentWebSearchScope =
            WebSearchConsentPolicy.routeFor(BuildConfig.WEB_SEARCH_URL)?.scope
        val toolsEnabled = WebSearchConsentPolicy.permitsTransfer(
            WebSearchConsentState(
                toolsEnabled = p.getBoolean(KEY_TOOL_CALLING, false),
                acceptedScope = acceptedWebSearchScope,
                currentScope = currentWebSearchScope,
            ),
        )
        // A boolean accepted under the older generic disclosure is not enough
        // to authorize a new proxy/device-ID route. Route or wording changes
        // fail closed and require a fresh affirmative choice.
        p.edit()
            .remove(LEGACY_KEY_WEB_SEARCH_DISCLOSURE)
            .putBoolean(KEY_TOOL_CALLING, toolsEnabled)
            .apply()

        settings = AppSettings(
            temperature = p.getFloat(KEY_TEMPERATURE, AppSettings().temperature),
            maxTokens = p.getInt(KEY_MAX_TOKENS, AppSettings().maxTokens),
            systemPrompt = p.getString(KEY_SYSTEM_PROMPT, "").orEmpty(),
            streaming = p.getBoolean(KEY_STREAMING, true),
            disableThinking = p.getBoolean(KEY_DISABLE_THINKING, false),
            toolCallingEnabled = toolsEnabled,
            webSearchConsentScope = acceptedWebSearchScope,
            hfToken = hfToken,
        )
    }

    internal fun resetForTesting() {
        prefs = null
        securePrefs = null
        settings = AppSettings()
    }

    fun setTemperature(value: Float) {
        settings = settings.copy(temperature = value)
        prefs?.edit()?.putFloat(KEY_TEMPERATURE, value)?.apply()
    }

    fun setMaxTokens(value: Int) {
        settings = settings.copy(maxTokens = value)
        prefs?.edit()?.putInt(KEY_MAX_TOKENS, value)?.apply()
    }

    fun setSystemPrompt(value: String) {
        settings = settings.copy(systemPrompt = value)
        prefs?.edit()?.putString(KEY_SYSTEM_PROMPT, value)?.apply()
    }

    fun setStreaming(value: Boolean) {
        settings = settings.copy(streaming = value)
        prefs?.edit()?.putBoolean(KEY_STREAMING, value)?.apply()
    }

    fun setDisableThinking(value: Boolean) {
        settings = settings.copy(disableThinking = value)
        prefs?.edit()?.putBoolean(KEY_DISABLE_THINKING, value)?.apply()
    }

    /** Enables transfer only after disclosure acceptance; disabling also revokes that acceptance. */
    fun setWebToolsTransferEnabled(value: Boolean) {
        val currentScope = WebSearchConsentPolicy.routeFor(BuildConfig.WEB_SEARCH_URL)?.scope
        val next = if (value) {
            WebSearchConsentPolicy.accept(currentScope)
        } else {
            WebSearchConsentPolicy.revoke()
        }
        settings = settings.copy(
            toolCallingEnabled = next.toolsEnabled,
            webSearchConsentScope = next.acceptedScope,
        )
        prefs?.edit()?.also { editor ->
            editor.putBoolean(KEY_TOOL_CALLING, next.toolsEnabled)
            editor.remove(LEGACY_KEY_WEB_SEARCH_DISCLOSURE)
            if (next.acceptedScope.isBlank()) {
                editor.remove(KEY_WEB_SEARCH_CONSENT_SCOPE)
            } else {
                editor.putString(KEY_WEB_SEARCH_CONSENT_SCOPE, next.acceptedScope)
            }
        }?.apply()
    }

    /**
     * Durably replaces the Hugging Face token in encrypted storage.
     *
     * The observable settings state changes only after the synchronous commit
     * succeeds and its value is read back. A blank token is stored as an
     * authoritative encrypted tombstone so a stale plaintext migration source
     * cannot resurrect a cleared credential. Legacy plaintext cleanup happens
     * only after that verified secure write.
     */
    fun setHfToken(value: String): Result<Unit> {
        val secure = securePrefs
            ?: return Result.failure(IllegalStateException("Secure credential storage is unavailable"))
        val normalized = value.trim()
        val committed = runCatching {
            secure.edit().putString(KEY_HF_TOKEN, normalized).commit()
        }.getOrElse {
            return Result.failure(IllegalStateException("Could not write secure credential storage", it))
        }
        if (!committed) {
            return Result.failure(IllegalStateException("Could not commit secure credential storage"))
        }
        val verified = runCatching { secure.getString(KEY_HF_TOKEN, null) }
            .getOrElse {
                return Result.failure(
                    IllegalStateException("Could not verify secure credential storage", it),
                )
            }
        if (verified != normalized) {
            return Result.failure(IllegalStateException("Could not verify secure credential storage"))
        }

        settings = settings.copy(hfToken = normalized)
        val legacy = prefs
            ?: return Result.failure(IllegalStateException("Legacy credential storage is unavailable"))
        val legacyRemoved = runCatching {
            legacy.edit().remove(KEY_HF_TOKEN).commit()
        }.getOrElse {
            return Result.failure(IllegalStateException("Could not remove legacy credential storage", it))
        }
        if (!legacyRemoved) {
            return Result.failure(IllegalStateException("Could not commit legacy credential cleanup"))
        }
        return Result.success(Unit)
    }

    private inline fun pSafeEdit(block: SharedPreferences.Editor.() -> Unit) {
        prefs?.edit()?.apply(block)?.apply()
    }
}
