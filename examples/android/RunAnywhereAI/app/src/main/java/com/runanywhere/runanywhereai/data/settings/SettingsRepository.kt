package com.runanywhere.runanywhereai.data.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
    private const val KEY_HF_TOKEN = "hf_token"

    private var prefs: SharedPreferences? = null
    private var securePrefs: SharedPreferences? = null

    var settings: AppSettings by mutableStateOf(AppSettings())
        private set

    fun initialize(context: Context) {
        if (prefs != null) return
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val secure = runCatching { securePreferences(context, SECURE_PREFS) }
            .onFailure { RACLog.w("Secure settings unavailable; credentials cannot be loaded or saved") }
            .getOrNull()
        val hfToken = if (secure == null) {
            ""
        } else {
            runCatching { secure.getString(KEY_HF_TOKEN, "").orEmpty() }
                .onSuccess { securePrefs = secure }
                .onFailure { RACLog.w("Secure settings could not be read; credentials are unavailable") }
                .getOrDefault("")
        }
        prefs = p
        settings = AppSettings(
            temperature = p.getFloat(KEY_TEMPERATURE, AppSettings().temperature),
            maxTokens = p.getInt(KEY_MAX_TOKENS, AppSettings().maxTokens),
            systemPrompt = p.getString(KEY_SYSTEM_PROMPT, "").orEmpty(),
            streaming = p.getBoolean(KEY_STREAMING, true),
            disableThinking = p.getBoolean(KEY_DISABLE_THINKING, false),
            toolCallingEnabled = p.getBoolean(KEY_TOOL_CALLING, false),
            hfToken = hfToken,
        )
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

    fun setToolCallingEnabled(value: Boolean) {
        settings = settings.copy(toolCallingEnabled = value)
        prefs?.edit()?.putBoolean(KEY_TOOL_CALLING, value)?.apply()
    }

    /**
     * Durably replaces the Hugging Face token in encrypted storage.
     *
     * The observable settings state changes only after the synchronous commit
     * succeeds, so callers can report a storage failure without exposing an
     * unsaved credential as active configuration.
     */
    fun setHfToken(value: String): Result<Unit> {
        val secure = securePrefs
            ?: return Result.failure(IllegalStateException("Secure credential storage is unavailable"))
        val normalized = value.trim()
        val committed = runCatching {
            val editor = secure.edit()
            if (normalized.isBlank()) {
                editor.remove(KEY_HF_TOKEN)
            } else {
                editor.putString(KEY_HF_TOKEN, normalized)
            }
            editor.commit()
        }.getOrElse {
            return Result.failure(IllegalStateException("Could not write secure credential storage", it))
        }
        if (!committed) {
            return Result.failure(IllegalStateException("Could not commit secure credential storage"))
        }
        settings = settings.copy(hfToken = normalized)
        return Result.success(Unit)
    }

    private inline fun pSafeEdit(block: SharedPreferences.Editor.() -> Unit) {
        prefs?.edit()?.apply(block)?.apply()
    }
}
