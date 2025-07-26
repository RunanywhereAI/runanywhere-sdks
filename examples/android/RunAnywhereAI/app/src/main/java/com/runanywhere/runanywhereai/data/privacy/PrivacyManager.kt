package com.runanywhere.runanywhereai.data.privacy

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.runanywhere.runanywhereai.data.database.ConversationDao
import com.runanywhere.runanywhereai.data.database.Message
import com.runanywhere.runanywhereai.data.database.Conversation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import java.io.File

/**
 * Manages privacy settings and modes including no-logging privacy mode
 */
class PrivacyManager(
    private val context: Context,
    private val conversationDao: ConversationDao
) {
    companion object {
        private const val TAG = "PrivacyManager"
        private const val PREFS_NAME = "privacy_settings"
        private const val PRIVACY_SETTINGS_FILE = "privacy_settings.json"
        
        // Privacy preference keys
        private const val KEY_PRIVACY_MODE_ENABLED = "privacy_mode_enabled"
        private const val KEY_ANALYTICS_ENABLED = "analytics_enabled"
        private const val KEY_CRASH_REPORTING_ENABLED = "crash_reporting_enabled"
        private const val KEY_TELEMETRY_ENABLED = "telemetry_enabled"
        private const val KEY_LOCAL_STORAGE_ONLY = "local_storage_only"
        private const val KEY_ENCRYPTION_ENABLED = "encryption_enabled"
        private const val KEY_AUTO_DELETE_ENABLED = "auto_delete_enabled"
        private const val KEY_INCOGNITO_MODE_ENABLED = "incognito_mode_enabled"
    }
    
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        prettyPrint = true
    }
    
    private val preferences: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val privacySettingsFile: File by lazy {
        File(context.filesDir, PRIVACY_SETTINGS_FILE)
    }
    
    private var currentSettings: PrivacySettings? = null
    private var privacyListeners = mutableListOf<PrivacyListener>()
    
    /**
     * Initialize privacy manager
     */
    suspend fun initialize() {
        currentSettings = loadPrivacySettings()
        Log.d(TAG, "Privacy manager initialized with settings: ${currentSettings}")
    }
    
    /**
     * Check if privacy mode is enabled (no logging/tracking)
     */
    fun isPrivacyModeEnabled(): Boolean {
        return preferences.getBoolean(KEY_PRIVACY_MODE_ENABLED, false)
    }
    
    /**
     * Enable or disable privacy mode
     */
    suspend fun setPrivacyModeEnabled(enabled: Boolean) {
        preferences.edit()
            .putBoolean(KEY_PRIVACY_MODE_ENABLED, enabled)
            .apply()
        
        if (enabled) {
            enablePrivacyMode()
        } else {
            disablePrivacyMode()
        }
        
        notifyPrivacyListeners(PrivacyEvent.PrivacyModeChanged(enabled))
        Log.d(TAG, "Privacy mode ${if (enabled) "enabled" else "disabled"}")
    }
    
    /**
     * Check if incognito mode is enabled (temporary conversations)
     */
    fun isIncognitoModeEnabled(): Boolean {
        return preferences.getBoolean(KEY_INCOGNITO_MODE_ENABLED, false)
    }
    
    /**
     * Enable or disable incognito mode
     */
    suspend fun setIncognitoModeEnabled(enabled: Boolean) {
        preferences.edit()
            .putBoolean(KEY_INCOGNITO_MODE_ENABLED, enabled)
            .apply()
        
        notifyPrivacyListeners(PrivacyEvent.IncognitoModeChanged(enabled))
        Log.d(TAG, "Incognito mode ${if (enabled) "enabled" else "disabled"}")
    }
    
    /**
     * Get current privacy settings
     */
    suspend fun getPrivacySettings(): PrivacySettings = withContext(Dispatchers.IO) {
        currentSettings ?: loadPrivacySettings().also { currentSettings = it }
    }
    
    /**
     * Update privacy settings
     */
    suspend fun updatePrivacySettings(settings: PrivacySettings) = withContext(Dispatchers.IO) {
        try {
            // Apply settings to preferences
            preferences.edit()
                .putBoolean(KEY_PRIVACY_MODE_ENABLED, settings.privacyModeEnabled)
                .putBoolean(KEY_ANALYTICS_ENABLED, settings.analyticsEnabled)
                .putBoolean(KEY_CRASH_REPORTING_ENABLED, settings.crashReportingEnabled)
                .putBoolean(KEY_TELEMETRY_ENABLED, settings.telemetryEnabled)
                .putBoolean(KEY_LOCAL_STORAGE_ONLY, settings.localStorageOnly)
                .putBoolean(KEY_ENCRYPTION_ENABLED, settings.encryptionEnabled)
                .putBoolean(KEY_AUTO_DELETE_ENABLED, settings.autoDeleteEnabled)
                .putBoolean(KEY_INCOGNITO_MODE_ENABLED, settings.incognitoModeEnabled)
                .apply()
            
            // Save to file
            savePrivacySettings(settings)
            currentSettings = settings
            
            // Apply changes
            applyPrivacySettings(settings)
            
            notifyPrivacyListeners(PrivacyEvent.SettingsUpdated(settings))
            Log.d(TAG, "Privacy settings updated")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update privacy settings", e)
            throw e
        }
    }
    
    /**
     * Start incognito session
     */
    suspend fun startIncognitoSession(): IncognitoSession = withContext(Dispatchers.IO) {
        val sessionId = "incognito_${System.currentTimeMillis()}"
        val session = IncognitoSession(
            sessionId = sessionId,
            startTime = System.currentTimeMillis(),
            isActive = true
        )
        
        // Save session info
        saveIncognitoSession(session)
        
        notifyPrivacyListeners(PrivacyEvent.IncognitoSessionStarted(session))
        Log.d(TAG, "Started incognito session: $sessionId")
        
        session
    }
    
    /**
     * End incognito session and clean up data
     */
    suspend fun endIncognitoSession(sessionId: String) = withContext(Dispatchers.IO) {
        try {
            // Delete all conversations and messages from this session
            val incognitoConversations = conversationDao.getIncognitoConversations(sessionId)
            
            for (conversation in incognitoConversations) {
                conversationDao.deleteConversation(conversation.id)
            }
            
            // Clean up any temporary files
            cleanupIncognitoFiles(sessionId)
            
            // Remove session info
            removeIncognitoSession(sessionId)
            
            notifyPrivacyListeners(PrivacyEvent.IncognitoSessionEnded(sessionId))
            Log.d(TAG, "Ended incognito session: $sessionId, deleted ${incognitoConversations.size} conversations")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to end incognito session", e)
            throw e
        }
    }
    
    /**
     * Check if logging should be performed based on privacy settings
     */
    fun shouldLog(logType: LogType): Boolean {
        if (isPrivacyModeEnabled()) {
            return when (logType) {
                LogType.DEBUG -> false
                LogType.INFO -> false
                LogType.WARNING -> false
                LogType.ERROR -> !preferences.getBoolean(KEY_CRASH_REPORTING_ENABLED, true)
                LogType.ANALYTICS -> false
                LogType.TELEMETRY -> false
                LogType.PERFORMANCE -> false
                LogType.SECURITY -> true // Always log security events
            }
        }
        
        return when (logType) {
            LogType.ANALYTICS -> preferences.getBoolean(KEY_ANALYTICS_ENABLED, true)
            LogType.TELEMETRY -> preferences.getBoolean(KEY_TELEMETRY_ENABLED, true)
            LogType.ERROR -> preferences.getBoolean(KEY_CRASH_REPORTING_ENABLED, true)
            else -> true
        }
    }
    
    /**
     * Check if data should be stored based on privacy settings
     */
    fun shouldStoreData(dataType: DataType): Boolean {
        if (isIncognitoModeEnabled()) {
            return when (dataType) {
                DataType.CONVERSATIONS -> false // Incognito conversations are stored temporarily
                DataType.MESSAGES -> false // Incognito messages are stored temporarily
                DataType.ATTACHMENTS -> false
                DataType.MODEL_CACHE -> true // Cache is still allowed
                DataType.LOGS -> !isPrivacyModeEnabled()
                DataType.TEMPORARY_FILES -> true
            }
        }
        
        return when (dataType) {
            DataType.CONVERSATIONS -> !isPrivacyModeEnabled() || preferences.getBoolean(KEY_LOCAL_STORAGE_ONLY, false)
            DataType.MESSAGES -> !isPrivacyModeEnabled() || preferences.getBoolean(KEY_LOCAL_STORAGE_ONLY, false)
            DataType.LOGS -> shouldLog(LogType.INFO)
            else -> true
        }
    }
    
    /**
     * Sanitize data for logging based on privacy settings
     */
    fun sanitizeForLogging(data: String): String {
        if (isPrivacyModeEnabled()) {
            return "[REDACTED - Privacy Mode]"
        }
        
        // Basic PII sanitization
        return data
            .replace(Regex("\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b"), "[EMAIL]")
            .replace(Regex("\\b\\d{3}-\\d{2}-\\d{4}\\b"), "[SSN]")
            .replace(Regex("\\b\\d{4}\\s?\\d{4}\\s?\\d{4}\\s?\\d{4}\\b"), "[CARD]")
            .replace(Regex("\\b\\d{3}-\\d{3}-\\d{4}\\b"), "[PHONE]")
    }
    
    /**
     * Get privacy compliance report
     */
    suspend fun getPrivacyComplianceReport(): PrivacyComplianceReport = withContext(Dispatchers.IO) {
        val settings = getPrivacySettings()
        val dataStored = getStoredDataSummary()
        val activeSessions = getActiveIncognitoSessions()
        
        PrivacyComplianceReport(
            generatedAt = System.currentTimeMillis(),
            privacyModeEnabled = settings.privacyModeEnabled,
            incognitoModeEnabled = settings.incognitoModeEnabled,
            dataMinimization = settings.localStorageOnly,
            encryptionEnabled = settings.encryptionEnabled,
            dataRetentionPoliciesActive = getDataRetentionPoliciesCount() > 0,
            storedDataSummary = dataStored,
            activeIncognitoSessions = activeSessions.size,
            analyticsOptOut = !settings.analyticsEnabled,
            crashReportingOptOut = !settings.crashReportingEnabled,
            complianceScore = calculateComplianceScore(settings)
        )
    }
    
    /**
     * Export privacy data for user (GDPR compliance)
     */
    suspend fun exportPrivacyData(exportPath: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val settings = getPrivacySettings()
            val conversations = conversationDao.getAllConversations()
            val messages = conversationDao.getAllMessages()
            
            val exportData = PrivacyDataExport(
                exportedAt = System.currentTimeMillis(),
                privacySettings = settings,
                conversationsCount = conversations.size,
                messagesCount = messages.size,
                // Don't include actual content for privacy
                dataTypes = listOf("conversations", "messages", "settings", "preferences")
            )
            
            val exportFile = File(exportPath, "privacy_data_export_${System.currentTimeMillis()}.json")
            val jsonData = json.encodeToString(exportData)
            exportFile.writeText(jsonData)
            
            Log.d(TAG, "Privacy data exported to ${exportFile.absolutePath}")
            true
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to export privacy data", e)
            false
        }
    }
    
    /**
     * Add privacy listener
     */
    fun addPrivacyListener(listener: PrivacyListener) {
        privacyListeners.add(listener)
    }
    
    /**
     * Remove privacy listener
     */
    fun removePrivacyListener(listener: PrivacyListener) {
        privacyListeners.remove(listener)
    }
    
    // Private helper methods
    
    private suspend fun enablePrivacyMode() {
        // Disable analytics, telemetry, and detailed logging
        preferences.edit()
            .putBoolean(KEY_ANALYTICS_ENABLED, false)
            .putBoolean(KEY_TELEMETRY_ENABLED, false)
            .apply()
        
        // Clear any existing analytics data
        clearAnalyticsData()
        
        Log.d(TAG, "Privacy mode protections activated")
    }
    
    private suspend fun disablePrivacyMode() {
        // Restore default settings (but don't force enable)
        Log.d(TAG, "Privacy mode protections deactivated")
    }
    
    private fun applyPrivacySettings(settings: PrivacySettings) {
        // Apply settings to various components
        if (settings.privacyModeEnabled) {
            enablePrivacyMode()
        }
        
        // Configure encryption
        if (settings.encryptionEnabled) {
            // Enable encryption for stored data
        }
        
        // Configure auto-delete
        if (settings.autoDeleteEnabled) {
            // Schedule automatic deletion
        }
    }
    
    private fun clearAnalyticsData() {
        try {
            val analyticsDir = File(context.filesDir, "analytics")
            if (analyticsDir.exists()) {
                analyticsDir.deleteRecursively()
            }
            
            // Clear analytics preferences
            val analyticsPrefs = context.getSharedPreferences("analytics", Context.MODE_PRIVATE)
            analyticsPrefs.edit().clear().apply()
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear analytics data", e)
        }
    }
    
    private fun cleanupIncognitoFiles(sessionId: String) {
        try {
            val incognitoDir = File(context.cacheDir, "incognito/$sessionId")
            if (incognitoDir.exists()) {
                incognitoDir.deleteRecursively()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup incognito files", e)
        }
    }
    
    private fun saveIncognitoSession(session: IncognitoSession) {
        try {
            val sessionsFile = File(context.filesDir, "incognito_sessions.json")
            val sessions = if (sessionsFile.exists()) {
                val jsonData = sessionsFile.readText()
                json.decodeFromString<MutableList<IncognitoSession>>(jsonData)
            } else {
                mutableListOf()
            }
            
            sessions.add(session)
            val jsonData = json.encodeToString(sessions)
            sessionsFile.writeText(jsonData)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save incognito session", e)
        }
    }
    
    private fun removeIncognitoSession(sessionId: String) {
        try {
            val sessionsFile = File(context.filesDir, "incognito_sessions.json")
            if (sessionsFile.exists()) {
                val jsonData = sessionsFile.readText()
                val sessions = json.decodeFromString<MutableList<IncognitoSession>>(jsonData).apply {
                    removeAll { it.sessionId == sessionId }
                }
                
                val updatedJsonData = json.encodeToString(sessions)
                sessionsFile.writeText(updatedJsonData)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove incognito session", e)
        }
    }
    
    private fun getActiveIncognitoSessions(): List<IncognitoSession> {
        return try {
            val sessionsFile = File(context.filesDir, "incognito_sessions.json")
            if (sessionsFile.exists()) {
                val jsonData = sessionsFile.readText()
                json.decodeFromString<List<IncognitoSession>>(jsonData)
                    .filter { it.isActive }
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get active incognito sessions", e)
            emptyList()
        }
    }
    
    private suspend fun getStoredDataSummary(): StoredDataSummary {
        return try {
            val conversations = conversationDao.getConversationCount()
            val messages = conversationDao.getMessageCount()
            
            StoredDataSummary(
                conversationsCount = conversations,
                messagesCount = messages,
                attachmentsCount = 0, // Would implement if attachments exist
                cacheSize = getCacheSize(),
                totalSize = estimateTotalDataSize()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get stored data summary", e)
            StoredDataSummary()
        }
    }
    
    private fun getCacheSize(): Long {
        return try {
            context.cacheDir.walkTopDown()
                .filter { it.isFile }
                .map { it.length() }
                .sum()
        } catch (e: Exception) {
            0L
        }
    }
    
    private fun estimateTotalDataSize(): Long {
        return try {
            context.filesDir.walkTopDown()
                .filter { it.isFile }
                .map { it.length() }
                .sum() + getCacheSize()
        } catch (e: Exception) {
            0L
        }
    }
    
    private fun getDataRetentionPoliciesCount(): Int {
        // This would integrate with DataRetentionManager
        return 0 // Placeholder
    }
    
    private fun calculateComplianceScore(settings: PrivacySettings): Int {
        var score = 0
        
        if (settings.privacyModeEnabled) score += 20
        if (settings.encryptionEnabled) score += 15
        if (settings.localStorageOnly) score += 15
        if (!settings.analyticsEnabled) score += 10
        if (!settings.crashReportingEnabled) score += 10
        if (!settings.telemetryEnabled) score += 10
        if (settings.autoDeleteEnabled) score += 10
        if (settings.incognitoModeEnabled) score += 10
        
        return score
    }
    
    private fun loadPrivacySettings(): PrivacySettings {
        return try {
            if (privacySettingsFile.exists()) {
                val jsonData = privacySettingsFile.readText()
                json.decodeFromString<PrivacySettings>(jsonData)
            } else {
                getDefaultPrivacySettings()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load privacy settings", e)
            getDefaultPrivacySettings()
        }
    }
    
    private fun savePrivacySettings(settings: PrivacySettings) {
        try {
            val jsonData = json.encodeToString(settings)
            privacySettingsFile.writeText(jsonData)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save privacy settings", e)
            throw e
        }
    }
    
    private fun getDefaultPrivacySettings(): PrivacySettings {
        return PrivacySettings(
            privacyModeEnabled = preferences.getBoolean(KEY_PRIVACY_MODE_ENABLED, false),
            analyticsEnabled = preferences.getBoolean(KEY_ANALYTICS_ENABLED, true),
            crashReportingEnabled = preferences.getBoolean(KEY_CRASH_REPORTING_ENABLED, true),
            telemetryEnabled = preferences.getBoolean(KEY_TELEMETRY_ENABLED, true),
            localStorageOnly = preferences.getBoolean(KEY_LOCAL_STORAGE_ONLY, false),
            encryptionEnabled = preferences.getBoolean(KEY_ENCRYPTION_ENABLED, false),
            autoDeleteEnabled = preferences.getBoolean(KEY_AUTO_DELETE_ENABLED, false),
            incognitoModeEnabled = preferences.getBoolean(KEY_INCOGNITO_MODE_ENABLED, false)
        )
    }
    
    private fun notifyPrivacyListeners(event: PrivacyEvent) {
        privacyListeners.forEach { listener ->
            try {
                listener.onPrivacyEvent(event)
            } catch (e: Exception) {
                Log.e(TAG, "Error notifying privacy listener", e)
            }
        }
    }
}

// Data classes and interfaces

@Serializable
data class PrivacySettings(
    val privacyModeEnabled: Boolean = false,
    val analyticsEnabled: Boolean = true,
    val crashReportingEnabled: Boolean = true,
    val telemetryEnabled: Boolean = true,
    val localStorageOnly: Boolean = false,
    val encryptionEnabled: Boolean = false,
    val autoDeleteEnabled: Boolean = false,
    val incognitoModeEnabled: Boolean = false,
    val updatedAt: Long = System.currentTimeMillis()
)

@Serializable
data class IncognitoSession(
    val sessionId: String,
    val startTime: Long,
    val endTime: Long? = null,
    val isActive: Boolean = true
)

@Serializable
data class PrivacyComplianceReport(
    val generatedAt: Long,
    val privacyModeEnabled: Boolean,
    val incognitoModeEnabled: Boolean,
    val dataMinimization: Boolean,
    val encryptionEnabled: Boolean,
    val dataRetentionPoliciesActive: Boolean,
    val storedDataSummary: StoredDataSummary,
    val activeIncognitoSessions: Int,
    val analyticsOptOut: Boolean,
    val crashReportingOptOut: Boolean,
    val complianceScore: Int
)

@Serializable
data class StoredDataSummary(
    val conversationsCount: Int = 0,
    val messagesCount: Int = 0,
    val attachmentsCount: Int = 0,
    val cacheSize: Long = 0L,
    val totalSize: Long = 0L
)

@Serializable
data class PrivacyDataExport(
    val exportedAt: Long,
    val privacySettings: PrivacySettings,
    val conversationsCount: Int,
    val messagesCount: Int,
    val dataTypes: List<String>
)

enum class LogType {
    DEBUG, INFO, WARNING, ERROR, ANALYTICS, TELEMETRY, PERFORMANCE, SECURITY
}

sealed class PrivacyEvent {
    data class PrivacyModeChanged(val enabled: Boolean) : PrivacyEvent()
    data class IncognitoModeChanged(val enabled: Boolean) : PrivacyEvent()
    data class SettingsUpdated(val settings: PrivacySettings) : PrivacyEvent()
    data class IncognitoSessionStarted(val session: IncognitoSession) : PrivacyEvent()
    data class IncognitoSessionEnded(val sessionId: String) : PrivacyEvent()
}

interface PrivacyListener {
    fun onPrivacyEvent(event: PrivacyEvent)
}

// Extension functions for ConversationDao (these would be added to the actual DAO)
suspend fun ConversationDao.getIncognitoConversations(sessionId: String): List<Conversation> {
    // Implementation would be added to the actual DAO
    return emptyList() // Placeholder
}

suspend fun ConversationDao.getConversationCount(): Int {
    // Implementation would be added to the actual DAO
    return 0 // Placeholder
}

suspend fun ConversationDao.getMessageCount(): Int {
    // Implementation would be added to the actual DAO  
    return 0 // Placeholder
}

suspend fun ConversationDao.getAllConversations(): List<Conversation> {
    // Implementation would be added to the actual DAO
    return emptyList() // Placeholder
}

suspend fun ConversationDao.getAllMessages(): List<Message> {
    // Implementation would be added to the actual DAO
    return emptyList() // Placeholder
}