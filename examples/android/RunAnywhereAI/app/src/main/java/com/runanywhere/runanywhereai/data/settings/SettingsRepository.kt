package com.runanywhere.runanywhereai.data.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

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
        val secure = runCatching { createSecurePreferences(context.applicationContext) }.getOrNull()
        securePrefs = secure
        val hfToken = secure?.getString(KEY_HF_TOKEN, "").orEmpty()
            .ifBlank { p.getString(KEY_HF_TOKEN, "").orEmpty() }
        if (secure != null && hfToken.isNotBlank()) {
            secure.edit().putString(KEY_HF_TOKEN, hfToken).apply()
            p.edit().remove(KEY_HF_TOKEN).apply()
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

    fun setHfToken(value: String) {
        settings = settings.copy(hfToken = value)
        (securePrefs ?: prefs)?.edit()?.putString(KEY_HF_TOKEN, value)?.apply()
        if (securePrefs != null) {
            prefs?.edit()?.remove(KEY_HF_TOKEN)?.apply()
        }
    }

    private fun createSecurePreferences(context: Context): SharedPreferences {
        val masterKey = MasterKey
            .Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            SECURE_PREFS,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }
}
