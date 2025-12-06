package com.runanywhere.runanywhereai.data

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.runanywhere.runanywhereai.presentation.settings.RoutingPolicy
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import java.io.IOException

/**
 * DataStore extension property for the Context
 * iOS equivalent: UserDefaults
 */
private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/**
 * Data class to hold all settings
 * iOS Reference: State properties in CombinedSettingsView.swift
 */
data class SettingsData(
    val routingPolicy: RoutingPolicy = RoutingPolicy.AUTOMATIC,
    val temperature: Float = 0.7f,
    val maxTokens: Int = 10000,
    val analyticsLogToLocal: Boolean = false
)

/**
 * Settings persistence using DataStore
 *
 * iOS equivalent: UserDefaults for non-sensitive settings
 * - UserDefaults.standard.set(routingPolicy.rawValue, forKey: "routingPolicy")
 * - UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
 * - UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")
 */
class SettingsDataStore(private val context: Context) {

    companion object {
        private const val TAG = "SettingsDataStore"

        // Keys matching iOS UserDefaults keys
        private val ROUTING_POLICY = stringPreferencesKey("routingPolicy")
        private val TEMPERATURE = floatPreferencesKey("defaultTemperature")
        private val MAX_TOKENS = intPreferencesKey("defaultMaxTokens")
        private val ANALYTICS_LOG_TO_LOCAL = booleanPreferencesKey("analyticsLogToLocal")
    }

    /**
     * Flow of settings data - automatically updates when any value changes
     * iOS equivalent: Using @Published properties that auto-update UI
     */
    val settingsFlow: Flow<SettingsData> = context.settingsDataStore.data
        .catch { exception ->
            if (exception is IOException) {
                Log.e(TAG, "Error reading settings", exception)
                emit(androidx.datastore.preferences.core.emptyPreferences())
            } else {
                throw exception
            }
        }
        .map { preferences ->
            mapPreferencesToSettings(preferences)
        }

    private fun mapPreferencesToSettings(preferences: Preferences): SettingsData {
        val routingPolicyRaw = preferences[ROUTING_POLICY] ?: RoutingPolicy.AUTOMATIC.rawValue
        val routingPolicy = RoutingPolicy.entries.find { it.rawValue == routingPolicyRaw }
            ?: RoutingPolicy.AUTOMATIC

        return SettingsData(
            routingPolicy = routingPolicy,
            temperature = preferences[TEMPERATURE] ?: 0.7f,
            maxTokens = preferences[MAX_TOKENS] ?: 10000,
            analyticsLogToLocal = preferences[ANALYTICS_LOG_TO_LOCAL] ?: false
        )
    }

    /**
     * Save routing policy
     * iOS equivalent: UserDefaults.standard.set(routingPolicy.rawValue, forKey: "routingPolicy")
     */
    suspend fun saveRoutingPolicy(policy: RoutingPolicy) {
        context.settingsDataStore.edit { preferences ->
            preferences[ROUTING_POLICY] = policy.rawValue
        }
        Log.d(TAG, "Saved routing policy: ${policy.rawValue}")
    }

    /**
     * Save temperature
     * iOS equivalent: UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
     */
    suspend fun saveTemperature(temperature: Float) {
        context.settingsDataStore.edit { preferences ->
            preferences[TEMPERATURE] = temperature
        }
        Log.d(TAG, "Saved temperature: $temperature")
    }

    /**
     * Save max tokens
     * iOS equivalent: UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")
     */
    suspend fun saveMaxTokens(maxTokens: Int) {
        context.settingsDataStore.edit { preferences ->
            preferences[MAX_TOKENS] = maxTokens
        }
        Log.d(TAG, "Saved max tokens: $maxTokens")
    }

    /**
     * Save analytics logging preference
     * iOS equivalent: KeychainHelper.save(key: "analyticsLogToLocal", data: newValue)
     * Note: iOS stores this in Keychain but it's not truly sensitive, so DataStore is fine
     */
    suspend fun saveAnalyticsLogToLocal(enabled: Boolean) {
        context.settingsDataStore.edit { preferences ->
            preferences[ANALYTICS_LOG_TO_LOCAL] = enabled
        }
        Log.d(TAG, "Saved analytics log to local: $enabled")
    }

    /**
     * Save all settings at once
     * iOS equivalent: updateSDKConfiguration() in CombinedSettingsView
     */
    suspend fun saveAllSettings(settings: SettingsData) {
        context.settingsDataStore.edit { preferences ->
            preferences[ROUTING_POLICY] = settings.routingPolicy.rawValue
            preferences[TEMPERATURE] = settings.temperature
            preferences[MAX_TOKENS] = settings.maxTokens
            preferences[ANALYTICS_LOG_TO_LOCAL] = settings.analyticsLogToLocal
        }
        Log.d(TAG, "Saved all settings: $settings")
    }
}
