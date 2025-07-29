package com.runanywhere.runanywhereai.data.repository

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import com.runanywhere.runanywhereai.llm.LLMFramework
import com.runanywhere.runanywhereai.security.EncryptionManager
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for managing encrypted application preferences
 * 
 * Provides secure storage for all app settings using Android's EncryptedSharedPreferences
 * and additional encryption through EncryptionManager for sensitive data.
 */
@Singleton
class PreferencesRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val encryptionManager: EncryptionManager
) {
    companion object {
        private const val PREFS_NAME = "app_settings"
        
        // Generation Parameters Keys
        private const val KEY_MAX_TOKENS = "max_tokens"
        private const val KEY_TEMPERATURE = "temperature"
        private const val KEY_TOP_P = "top_p"
        private const val KEY_TOP_K = "top_k"
        private const val KEY_REPETITION_PENALTY = "repetition_penalty"
        private const val KEY_STOP_SEQUENCES = "stop_sequences"
        private const val KEY_PRESENCE_PENALTY = "presence_penalty"
        private const val KEY_FREQUENCY_PENALTY = "frequency_penalty"
        
        // Hardware Settings Keys
        private const val KEY_PREFERRED_FRAMEWORK = "preferred_framework"
        private const val KEY_ENABLE_GPU_ACCELERATION = "enable_gpu_acceleration"
        private const val KEY_MAX_MEMORY_USAGE = "max_memory_usage"
        
        // Battery Settings Keys
        private const val KEY_ENABLE_BATTERY_OPTIMIZATION = "enable_battery_optimization"
        private const val KEY_THERMAL_THROTTLING_ENABLED = "thermal_throttling_enabled"
        private const val KEY_MAX_BATTERY_TEMPERATURE = "max_battery_temperature"
        
        // Privacy Settings Keys
        private const val KEY_ENABLE_CONVERSATION_ENCRYPTION = "enable_conversation_encryption"
        private const val KEY_AUTO_DELETE_CONVERSATIONS = "auto_delete_conversations"
        private const val KEY_CONVERSATION_RETENTION_DAYS = "conversation_retention_days"
        private const val KEY_ENABLE_ANALYTICS = "enable_analytics"
        
        // Advanced Settings Keys
        private const val KEY_ENABLE_DEBUG_LOGGING = "enable_debug_logging"
        private const val KEY_MODEL_CACHE_SIZE = "model_cache_size"
        private const val KEY_ENABLE_MODEL_PRELOADING = "enable_model_preloading"
        private const val KEY_CONCURRENT_INFERENCES_LIMIT = "concurrent_inferences_limit"
        
        // Default Values
        private const val DEFAULT_MAX_TOKENS = 150
        private const val DEFAULT_TEMPERATURE = 0.7f
        private const val DEFAULT_TOP_P = 0.9f
        private const val DEFAULT_TOP_K = 40
        private const val DEFAULT_REPETITION_PENALTY = 1.1f
        private const val DEFAULT_MAX_MEMORY_USAGE = 4096
        private const val DEFAULT_MAX_BATTERY_TEMPERATURE = 40.0f
        private const val DEFAULT_CONVERSATION_RETENTION_DAYS = 30
        private const val DEFAULT_MODEL_CACHE_SIZE = 2048
        private const val DEFAULT_CONCURRENT_INFERENCES_LIMIT = 2
    }

    private val sharedPreferences by lazy {
        try {
            val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
            EncryptedSharedPreferences.create(
                PREFS_NAME,
                masterKeyAlias,
                context,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            // Fallback to regular SharedPreferences if EncryptedSharedPreferences fails
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    // Generation Parameters
    suspend fun getMaxTokens(): Int = withContext(Dispatchers.IO) {
        sharedPreferences.getInt(KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS)
    }

    suspend fun setMaxTokens(value: Int) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putInt(KEY_MAX_TOKENS, value).apply()
    }

    suspend fun getTemperature(): Float = withContext(Dispatchers.IO) {
        sharedPreferences.getFloat(KEY_TEMPERATURE, DEFAULT_TEMPERATURE)
    }

    suspend fun setTemperature(value: Float) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putFloat(KEY_TEMPERATURE, value).apply()
    }

    suspend fun getTopP(): Float = withContext(Dispatchers.IO) {
        sharedPreferences.getFloat(KEY_TOP_P, DEFAULT_TOP_P)
    }

    suspend fun setTopP(value: Float) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putFloat(KEY_TOP_P, value).apply()
    }

    suspend fun getTopK(): Int = withContext(Dispatchers.IO) {
        sharedPreferences.getInt(KEY_TOP_K, DEFAULT_TOP_K)
    }

    suspend fun setTopK(value: Int) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putInt(KEY_TOP_K, value).apply()
    }

    suspend fun getRepetitionPenalty(): Float = withContext(Dispatchers.IO) {
        sharedPreferences.getFloat(KEY_REPETITION_PENALTY, DEFAULT_REPETITION_PENALTY)
    }

    suspend fun setRepetitionPenalty(value: Float) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putFloat(KEY_REPETITION_PENALTY, value).apply()
    }

    suspend fun getStopSequences(): List<String> = withContext(Dispatchers.IO) {
        val jsonString = sharedPreferences.getString(KEY_STOP_SEQUENCES, "[]") ?: "[]"
        val jsonArray = JSONArray(jsonString)
        val list = mutableListOf<String>()
        for (i in 0 until jsonArray.length()) {
            list.add(jsonArray.getString(i))
        }
        list
    }

    suspend fun setStopSequences(value: List<String>) = withContext(Dispatchers.IO) {
        val jsonArray = JSONArray(value)
        sharedPreferences.edit().putString(KEY_STOP_SEQUENCES, jsonArray.toString()).apply()
    }

    suspend fun getPresencePenalty(): Float? = withContext(Dispatchers.IO) {
        if (sharedPreferences.contains(KEY_PRESENCE_PENALTY)) {
            sharedPreferences.getFloat(KEY_PRESENCE_PENALTY, 0f)
        } else null
    }

    suspend fun setPresencePenalty(value: Float?) = withContext(Dispatchers.IO) {
        if (value != null) {
            sharedPreferences.edit().putFloat(KEY_PRESENCE_PENALTY, value).apply()
        } else {
            sharedPreferences.edit().remove(KEY_PRESENCE_PENALTY).apply()
        }
    }

    suspend fun getFrequencyPenalty(): Float? = withContext(Dispatchers.IO) {
        if (sharedPreferences.contains(KEY_FREQUENCY_PENALTY)) {
            sharedPreferences.getFloat(KEY_FREQUENCY_PENALTY, 0f)
        } else null
    }

    suspend fun setFrequencyPenalty(value: Float?) = withContext(Dispatchers.IO) {
        if (value != null) {
            sharedPreferences.edit().putFloat(KEY_FREQUENCY_PENALTY, value).apply()
        } else {
            sharedPreferences.edit().remove(KEY_FREQUENCY_PENALTY).apply()
        }
    }

    // Hardware Settings
    suspend fun getPreferredFramework(): LLMFramework? = withContext(Dispatchers.IO) {
        val frameworkName = sharedPreferences.getString(KEY_PREFERRED_FRAMEWORK, null)
        frameworkName?.let { LLMFramework.valueOf(it) }
    }

    suspend fun setPreferredFramework(value: LLMFramework?) = withContext(Dispatchers.IO) {
        if (value != null) {
            sharedPreferences.edit().putString(KEY_PREFERRED_FRAMEWORK, value.name).apply()
        } else {
            sharedPreferences.edit().remove(KEY_PREFERRED_FRAMEWORK).apply()
        }
    }

    suspend fun getEnableGPUAcceleration(): Boolean = withContext(Dispatchers.IO) {
        sharedPreferences.getBoolean(KEY_ENABLE_GPU_ACCELERATION, true)
    }

    suspend fun setEnableGPUAcceleration(value: Boolean) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putBoolean(KEY_ENABLE_GPU_ACCELERATION, value).apply()
    }

    suspend fun getMaxMemoryUsage(): Int = withContext(Dispatchers.IO) {
        sharedPreferences.getInt(KEY_MAX_MEMORY_USAGE, DEFAULT_MAX_MEMORY_USAGE)
    }

    suspend fun setMaxMemoryUsage(value: Int) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putInt(KEY_MAX_MEMORY_USAGE, value).apply()
    }

    // Battery Settings
    suspend fun getEnableBatteryOptimization(): Boolean = withContext(Dispatchers.IO) {
        sharedPreferences.getBoolean(KEY_ENABLE_BATTERY_OPTIMIZATION, true)
    }

    suspend fun setEnableBatteryOptimization(value: Boolean) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putBoolean(KEY_ENABLE_BATTERY_OPTIMIZATION, value).apply()
    }

    suspend fun getThermalThrottlingEnabled(): Boolean = withContext(Dispatchers.IO) {
        sharedPreferences.getBoolean(KEY_THERMAL_THROTTLING_ENABLED, true)
    }

    suspend fun setThermalThrottlingEnabled(value: Boolean) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putBoolean(KEY_THERMAL_THROTTLING_ENABLED, value).apply()
    }

    suspend fun getMaxBatteryTemperature(): Float = withContext(Dispatchers.IO) {
        sharedPreferences.getFloat(KEY_MAX_BATTERY_TEMPERATURE, DEFAULT_MAX_BATTERY_TEMPERATURE)
    }

    suspend fun setMaxBatteryTemperature(value: Float) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putFloat(KEY_MAX_BATTERY_TEMPERATURE, value).apply()
    }

    // Privacy Settings
    suspend fun getEnableConversationEncryption(): Boolean = withContext(Dispatchers.IO) {
        sharedPreferences.getBoolean(KEY_ENABLE_CONVERSATION_ENCRYPTION, true)
    }

    suspend fun setEnableConversationEncryption(value: Boolean) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putBoolean(KEY_ENABLE_CONVERSATION_ENCRYPTION, value).apply()
    }

    suspend fun getAutoDeleteConversations(): Boolean = withContext(Dispatchers.IO) {
        sharedPreferences.getBoolean(KEY_AUTO_DELETE_CONVERSATIONS, false)
    }

    suspend fun setAutoDeleteConversations(value: Boolean) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putBoolean(KEY_AUTO_DELETE_CONVERSATIONS, value).apply()
    }

    suspend fun getConversationRetentionDays(): Int = withContext(Dispatchers.IO) {
        sharedPreferences.getInt(KEY_CONVERSATION_RETENTION_DAYS, DEFAULT_CONVERSATION_RETENTION_DAYS)
    }

    suspend fun setConversationRetentionDays(value: Int) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putInt(KEY_CONVERSATION_RETENTION_DAYS, value).apply()
    }

    suspend fun getEnableAnalytics(): Boolean = withContext(Dispatchers.IO) {
        sharedPreferences.getBoolean(KEY_ENABLE_ANALYTICS, false)
    }

    suspend fun setEnableAnalytics(value: Boolean) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putBoolean(KEY_ENABLE_ANALYTICS, value).apply()
    }

    // Advanced Settings
    suspend fun getEnableDebugLogging(): Boolean = withContext(Dispatchers.IO) {
        sharedPreferences.getBoolean(KEY_ENABLE_DEBUG_LOGGING, false)
    }

    suspend fun setEnableDebugLogging(value: Boolean) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putBoolean(KEY_ENABLE_DEBUG_LOGGING, value).apply()
    }

    suspend fun getModelCacheSize(): Int = withContext(Dispatchers.IO) {
        sharedPreferences.getInt(KEY_MODEL_CACHE_SIZE, DEFAULT_MODEL_CACHE_SIZE)
    }

    suspend fun setModelCacheSize(value: Int) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putInt(KEY_MODEL_CACHE_SIZE, value).apply()
    }

    suspend fun getEnableModelPreloading(): Boolean = withContext(Dispatchers.IO) {
        sharedPreferences.getBoolean(KEY_ENABLE_MODEL_PRELOADING, true)
    }

    suspend fun setEnableModelPreloading(value: Boolean) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putBoolean(KEY_ENABLE_MODEL_PRELOADING, value).apply()
    }

    suspend fun getConcurrentInferencesLimit(): Int = withContext(Dispatchers.IO) {
        sharedPreferences.getInt(KEY_CONCURRENT_INFERENCES_LIMIT, DEFAULT_CONCURRENT_INFERENCES_LIMIT)
    }

    suspend fun setConcurrentInferencesLimit(value: Int) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putInt(KEY_CONCURRENT_INFERENCES_LIMIT, value).apply()
    }

    // Utility Functions
    /**
     * Clear all settings and reset to defaults
     */
    suspend fun clearAllSettings() = withContext(Dispatchers.IO) {
        sharedPreferences.edit().clear().apply()
    }

    /**
     * Export all settings to encrypted JSON string
     */
    fun exportSettings(): String {
        val allPrefs = sharedPreferences.all
        val jsonObject = JSONObject()
        
        allPrefs.forEach { (key, value) ->
            when (value) {
                is String -> jsonObject.put(key, value)
                is Int -> jsonObject.put(key, value)
                is Float -> jsonObject.put(key, value.toDouble()) // JSON doesn't have Float
                is Boolean -> jsonObject.put(key, value)
                is Long -> jsonObject.put(key, value)
            }
        }
        
        // Encrypt the JSON string for additional security
        return encryptionManager.encrypt(jsonObject.toString())
    }

    /**
     * Import settings from encrypted JSON string
     */
    suspend fun importSettings(encryptedData: String) = withContext(Dispatchers.IO) {
        try {
            val decryptedData = encryptionManager.decrypt(encryptedData)
            val jsonObject = JSONObject(decryptedData)
            val editor = sharedPreferences.edit()
            
            val keys = jsonObject.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                when (val value = jsonObject.get(key)) {
                    is String -> editor.putString(key, value)
                    is Int -> editor.putInt(key, value)
                    is Double -> editor.putFloat(key, value.toFloat())
                    is Boolean -> editor.putBoolean(key, value)
                    is Long -> editor.putLong(key, value)
                }
            }
            
            editor.apply()
        } catch (e: Exception) {
            throw IllegalArgumentException("Invalid settings data format", e)
        }
    }

    /**
     * Check if settings have been initialized (not empty)
     */
    fun hasSettings(): Boolean {
        return sharedPreferences.all.isNotEmpty()
    }

    /**
     * Get all settings as a map for debugging purposes
     */
    fun getAllSettings(): Map<String, Any?> = sharedPreferences.all
}