package com.runanywhere.runanywhereai.data.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

object SettingsRepository {
    private const val PREFS = "app_settings"
    private const val KEY_TEMPERATURE = "temperature"
    private const val KEY_MAX_TOKENS = "max_tokens"
    private const val KEY_SYSTEM_PROMPT = "system_prompt"
    private const val KEY_STREAMING = "streaming"

    private var prefs: SharedPreferences? = null

    var settings: AppSettings by mutableStateOf(AppSettings())
        private set

    fun initialize(context: Context) {
        if (prefs != null) return
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs = p
        settings = AppSettings(
            temperature = p.getFloat(KEY_TEMPERATURE, AppSettings().temperature),
            maxTokens = p.getInt(KEY_MAX_TOKENS, AppSettings().maxTokens),
            systemPrompt = p.getString(KEY_SYSTEM_PROMPT, "").orEmpty(),
            streaming = p.getBoolean(KEY_STREAMING, true),
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
}
