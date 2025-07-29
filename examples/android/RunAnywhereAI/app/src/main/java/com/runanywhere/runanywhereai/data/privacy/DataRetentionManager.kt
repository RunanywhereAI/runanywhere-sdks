package com.runanywhere.runanywhereai.data.privacy

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.runanywhere.runanywhereai.data.database.ConversationDao
import com.runanywhere.runanywhereai.data.database.Message
import com.runanywhere.runanywhereai.data.database.Conversation
import kotlinx.coroutines.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Manages data retention policies and automatic cleanup
 */
class DataRetentionManager(
    private val context: Context,
    private val conversationDao: ConversationDao
) {
    companion object {
        private const val TAG = "DataRetentionManager"
        private const val PREFS_NAME = "data_retention_prefs"
        private const val RETENTION_POLICIES_FILE = "retention_policies.json"
        private const val LAST_CLEANUP_KEY = "last_cleanup_timestamp"
        private const val CLEANUP_INTERVAL_MS = 24 * 60 * 60 * 1000L // 24 hours
    }
    
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        prettyPrint = true
    }
    
    private val preferences: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val retentionPoliciesFile: File by lazy {
        File(context.filesDir, RETENTION_POLICIES_FILE)
    }
    
    private var cleanupJob: Job? = null
    
    /**
     * Initialize data retention manager and start periodic cleanup
     */
    fun initialize() {
        Log.d(TAG, "Initializing data retention manager")
        
        // Start periodic cleanup
        schedulePeriodicCleanup()
        
        // Run initial cleanup if needed
        CoroutineScope(Dispatchers.IO).launch {
            val lastCleanup = preferences.getLong(LAST_CLEANUP_KEY, 0)
            val currentTime = System.currentTimeMillis()
            
            if (currentTime - lastCleanup > CLEANUP_INTERVAL_MS) {
                performCleanup()
            }
        }
    }
    
    /**
     * Set data retention policy
     */
    suspend fun setRetentionPolicy(policy: DataRetentionPolicy): Boolean = withContext(Dispatchers.IO) {
        try {
            val policies = loadRetentionPolicies().toMutableList()
            val existingIndex = policies.indexOfFirst { it.dataType == policy.dataType }
            
            if (existingIndex >= 0) {
                policies[existingIndex] = policy
            } else {
                policies.add(policy)
            }
            
            saveRetentionPolicies(policies)
            
            Log.d(TAG, "Set retention policy for ${policy.dataType}: ${policy.retentionPeriodDays} days")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set retention policy", e)
            false
        }
    }
    
    /**
     * Get current retention policies
     */
    suspend fun getRetentionPolicies(): List<DataRetentionPolicy> = withContext(Dispatchers.IO) {
        loadRetentionPolicies()
    }
    
    /**
     * Get retention policy for specific data type
     */
    suspend fun getRetentionPolicy(dataType: DataType): DataRetentionPolicy? = withContext(Dispatchers.IO) {
        loadRetentionPolicies().find { it.dataType == dataType }
    }
    
    /**
     * Remove retention policy
     */
    suspend fun removeRetentionPolicy(dataType: DataType): Boolean = withContext(Dispatchers.IO) {
        try {
            val policies = loadRetentionPolicies().toMutableList()
            val removed = policies.removeAll { it.dataType == dataType }
            
            if (removed) {
                saveRetentionPolicies(policies)
                Log.d(TAG, "Removed retention policy for $dataType")
            }
            
            removed
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove retention policy", e)
            false
        }
    }
    
    /**
     * Perform manual cleanup based on current policies
     */
    suspend fun performCleanup(): CleanupResult = withContext(Dispatchers.IO) {
        Log.d(TAG, "Starting data cleanup")
        
        val startTime = System.currentTimeMillis()
        val policies = loadRetentionPolicies()
        var totalItemsDeleted = 0
        var totalSpaceFreed = 0L
        val cleanupDetails = mutableListOf<CleanupDetail>()
        
        try {
            for (policy in policies) {
                val detail = cleanupDataType(policy)
                cleanupDetails.add(detail)
                totalItemsDeleted += detail.itemsDeleted
                totalSpaceFreed += detail.spaceFreedBytes
            }
            
            // Update last cleanup timestamp
            preferences.edit()
                .putLong(LAST_CLEANUP_KEY, System.currentTimeMillis())
                .apply()
            
            val duration = System.currentTimeMillis() - startTime
            
            Log.d(TAG, "Cleanup completed: $totalItemsDeleted items deleted, ${formatBytes(totalSpaceFreed)} freed in ${duration}ms")
            
            CleanupResult(
                success = true,
                totalItemsDeleted = totalItemsDeleted,
                totalSpaceFreed = totalSpaceFreed,
                durationMs = duration,
                details = cleanupDetails
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "Cleanup failed", e)
            CleanupResult(
                success = false,
                error = e.message,
                durationMs = System.currentTimeMillis() - startTime,
                details = cleanupDetails
            )
        }
    }
    
    /**
     * Get cleanup statistics without performing cleanup
     */
    suspend fun getCleanupPreview(): CleanupPreview = withContext(Dispatchers.IO) {
        val policies = loadRetentionPolicies()
        val previews = mutableListOf<CleanupItemPreview>()
        var totalItems = 0
        var estimatedSpaceToFree = 0L
        
        for (policy in policies) {
            val preview = getCleanupPreviewForPolicy(policy)
            previews.add(preview)
            totalItems += preview.itemCount
            estimatedSpaceToFree += preview.estimatedSizeBytes
        }
        
        CleanupPreview(
            totalItemsToDelete = totalItems,
            estimatedSpaceToFree = estimatedSpaceToFree,
            items = previews
        )
    }
    
    /**
     * Check if data should be retained based on policies
     */
    suspend fun shouldRetainData(dataType: DataType, timestamp: Long): Boolean = withContext(Dispatchers.IO) {
        val policy = getRetentionPolicy(dataType) ?: return@withContext true
        
        if (!policy.enabled) return@withContext true
        
        val cutoffTime = System.currentTimeMillis() - (policy.retentionPeriodDays * 24 * 60 * 60 * 1000L)
        timestamp >= cutoffTime
    }
    
    /**
     * Get data that will be deleted based on current policies
     */
    suspend fun getDataForDeletion(dataType: DataType): List<DeletableItem> = withContext(Dispatchers.IO) {
        val policy = getRetentionPolicy(dataType) ?: return@withContext emptyList()
        
        if (!policy.enabled) return@withContext emptyList()
        
        val cutoffTime = System.currentTimeMillis() - (policy.retentionPeriodDays * 24 * 60 * 60 * 1000L)
        
        when (dataType) {
            DataType.CONVERSATIONS -> {
                val conversations = conversationDao.getConversationsOlderThan(cutoffTime)
                conversations.map { conv ->
                    DeletableItem(
                        id = conv.id.toString(),
                        type = DataType.CONVERSATIONS,
                        timestamp = conv.createdAt,
                        sizeBytes = estimateConversationSize(conv),
                        description = "Conversation: ${conv.title}"
                    )
                }
            }
            DataType.MESSAGES -> {
                val messages = conversationDao.getMessagesOlderThan(cutoffTime)
                messages.map { msg ->
                    DeletableItem(
                        id = msg.id.toString(),
                        type = DataType.MESSAGES,
                        timestamp = msg.timestamp,
                        sizeBytes = msg.content.length.toLong() * 2, // Rough estimate
                        description = "Message: ${msg.content.take(50)}..."
                    )
                }
            }
            DataType.ATTACHMENTS -> {
                // Implementation would depend on attachment storage system
                emptyList()
            }
            DataType.MODEL_CACHE -> {
                getModelCacheForDeletion(cutoffTime)
            }
            DataType.LOGS -> {
                getLogsForDeletion(cutoffTime)
            }
            DataType.TEMPORARY_FILES -> {
                getTemporaryFilesForDeletion(cutoffTime)
            }
        }
    }
    
    /**
     * Export data before deletion (for compliance)
     */
    suspend fun exportDataBeforeDeletion(
        items: List<DeletableItem>,
        exportPath: String
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val exportDir = File(exportPath)
            if (!exportDir.exists()) {
                exportDir.mkdirs()
            }
            
            val exportData = DataExport(
                exportedAt = System.currentTimeMillis(),
                items = items,
                reason = "Data retention policy cleanup"
            )
            
            val exportFile = File(exportDir, "data_export_${System.currentTimeMillis()}.json")
            val jsonData = json.encodeToString(exportData)
            exportFile.writeText(jsonData)
            
            Log.d(TAG, "Exported ${items.size} items to ${exportFile.absolutePath}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to export data", e)
            false
        }
    }
    
    /**
     * Get default retention policies
     */
    fun getDefaultRetentionPolicies(): List<DataRetentionPolicy> {
        return listOf(
            DataRetentionPolicy(
                dataType = DataType.CONVERSATIONS,
                retentionPeriodDays = 365, // 1 year
                enabled = false, // Disabled by default
                autoCleanup = false,
                exportBeforeDelete = true,
                description = "Chat conversations and their messages"
            ),
            DataRetentionPolicy(
                dataType = DataType.MESSAGES,
                retentionPeriodDays = 365,
                enabled = false,
                autoCleanup = false,
                exportBeforeDelete = true,
                description = "Individual chat messages"
            ),
            DataRetentionPolicy(
                dataType = DataType.ATTACHMENTS,
                retentionPeriodDays = 180, // 6 months
                enabled = false,
                autoCleanup = true,
                exportBeforeDelete = false,
                description = "File attachments and images"
            ),
            DataRetentionPolicy(
                dataType = DataType.MODEL_CACHE,
                retentionPeriodDays = 30,
                enabled = true,
                autoCleanup = true,
                exportBeforeDelete = false,
                description = "Cached model data and temporary files"
            ),
            DataRetentionPolicy(
                dataType = DataType.LOGS,
                retentionPeriodDays = 7,
                enabled = true,
                autoCleanup = true,
                exportBeforeDelete = false,
                description = "Application logs and debugging information"
            ),
            DataRetentionPolicy(
                dataType = DataType.TEMPORARY_FILES,
                retentionPeriodDays = 1,
                enabled = true,
                autoCleanup = true,
                exportBeforeDelete = false,
                description = "Temporary files and cache"
            )
        )
    }
    
    fun shutdown() {
        Log.d(TAG, "Shutting down data retention manager")
        cleanupJob?.cancel()
    }
    
    // Private helper methods
    
    private fun schedulePeriodicCleanup() {
        cleanupJob?.cancel()
        cleanupJob = CoroutineScope(Dispatchers.IO).launch {
            while (isActive) {
                try {
                    delay(CLEANUP_INTERVAL_MS)
                    performCleanup()
                } catch (e: CancellationException) {
                    break
                } catch (e: Exception) {
                    Log.e(TAG, "Error in periodic cleanup", e)
                }
            }
        }
    }
    
    private suspend fun cleanupDataType(policy: DataRetentionPolicy): CleanupDetail {
        if (!policy.enabled || !policy.autoCleanup) {
            return CleanupDetail(
                dataType = policy.dataType,
                itemsDeleted = 0,
                spaceFreedBytes = 0L,
                skipped = true,
                reason = if (!policy.enabled) "Policy disabled" else "Auto cleanup disabled"
            )
        }
        
        val cutoffTime = System.currentTimeMillis() - (policy.retentionPeriodDays * 24 * 60 * 60 * 1000L)
        
        return when (policy.dataType) {
            DataType.CONVERSATIONS -> cleanupConversations(cutoffTime, policy.exportBeforeDelete)
            DataType.MESSAGES -> cleanupMessages(cutoffTime, policy.exportBeforeDelete)
            DataType.ATTACHMENTS -> cleanupAttachments(cutoffTime, policy.exportBeforeDelete)
            DataType.MODEL_CACHE -> cleanupModelCache(cutoffTime)
            DataType.LOGS -> cleanupLogs(cutoffTime)
            DataType.TEMPORARY_FILES -> cleanupTemporaryFiles(cutoffTime)
        }
    }
    
    private suspend fun cleanupConversations(cutoffTime: Long, exportFirst: Boolean): CleanupDetail {
        val conversations = conversationDao.getConversationsOlderThan(cutoffTime)
        
        if (exportFirst && conversations.isNotEmpty()) {
            // Export conversations before deletion
            val exportItems = conversations.map { conv ->
                DeletableItem(
                    id = conv.id.toString(),
                    type = DataType.CONVERSATIONS,
                    timestamp = conv.createdAt,
                    sizeBytes = estimateConversationSize(conv),
                    description = "Conversation: ${conv.title}"
                )
            }
            exportDataBeforeDeletion(exportItems, "${context.filesDir}/exports/conversations")
        }
        
        var deletedCount = 0
        var freedSpace = 0L
        
        for (conversation in conversations) {
            try {
                val sizeEstimate = estimateConversationSize(conversation)
                conversationDao.deleteConversation(conversation.id)
                deletedCount++
                freedSpace += sizeEstimate
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete conversation ${conversation.id}", e)
            }
        }
        
        return CleanupDetail(
            dataType = DataType.CONVERSATIONS,
            itemsDeleted = deletedCount,
            spaceFreedBytes = freedSpace
        )
    }
    
    private suspend fun cleanupMessages(cutoffTime: Long, exportFirst: Boolean): CleanupDetail {
        val messages = conversationDao.getMessagesOlderThan(cutoffTime)
        
        if (exportFirst && messages.isNotEmpty()) {
            val exportItems = messages.map { msg ->
                DeletableItem(
                    id = msg.id.toString(),
                    type = DataType.MESSAGES,
                    timestamp = msg.timestamp,
                    sizeBytes = msg.content.length.toLong() * 2,
                    description = "Message: ${msg.content.take(50)}..."
                )
            }
            exportDataBeforeDeletion(exportItems, "${context.filesDir}/exports/messages")
        }
        
        var deletedCount = 0
        var freedSpace = 0L
        
        for (message in messages) {
            try {
                val sizeEstimate = message.content.length.toLong() * 2
                conversationDao.deleteMessage(message.id)
                deletedCount++
                freedSpace += sizeEstimate
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete message ${message.id}", e)
            }
        }
        
        return CleanupDetail(
            dataType = DataType.MESSAGES,
            itemsDeleted = deletedCount,
            spaceFreedBytes = freedSpace
        )
    }
    
    private suspend fun cleanupAttachments(cutoffTime: Long, exportFirst: Boolean): CleanupDetail {
        // Implementation would depend on attachment storage system
        return CleanupDetail(
            dataType = DataType.ATTACHMENTS,
            itemsDeleted = 0,
            spaceFreedBytes = 0L,
            skipped = true,
            reason = "Attachment cleanup not implemented"
        )
    }
    
    private suspend fun cleanupModelCache(cutoffTime: Long): CleanupDetail {
        val cacheDir = File(context.cacheDir, "models")
        var deletedCount = 0
        var freedSpace = 0L
        
        if (cacheDir.exists()) {
            cacheDir.listFiles()?.forEach { file ->
                if (file.lastModified() < cutoffTime) {
                    try {
                        val size = file.length()
                        if (file.delete()) {
                            deletedCount++
                            freedSpace += size
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to delete cache file ${file.name}", e)
                    }
                }
            }
        }
        
        return CleanupDetail(
            dataType = DataType.MODEL_CACHE,
            itemsDeleted = deletedCount,
            spaceFreedBytes = freedSpace
        )
    }
    
    private suspend fun cleanupLogs(cutoffTime: Long): CleanupDetail {
        val logDir = File(context.filesDir, "logs")
        var deletedCount = 0
        var freedSpace = 0L
        
        if (logDir.exists()) {
            logDir.listFiles()?.forEach { file ->
                if (file.lastModified() < cutoffTime) {
                    try {
                        val size = file.length()
                        if (file.delete()) {
                            deletedCount++
                            freedSpace += size
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to delete log file ${file.name}", e)
                    }
                }
            }
        }
        
        return CleanupDetail(
            dataType = DataType.LOGS,
            itemsDeleted = deletedCount,
            spaceFreedBytes = freedSpace
        )
    }
    
    private suspend fun cleanupTemporaryFiles(cutoffTime: Long): CleanupDetail {
        val tempDir = context.cacheDir
        var deletedCount = 0
        var freedSpace = 0L
        
        tempDir.listFiles()?.forEach { file ->
            if (file.lastModified() < cutoffTime && file.name.startsWith("temp_")) {
                try {
                    val size = file.length()
                    if (file.delete()) {
                        deletedCount++
                        freedSpace += size
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to delete temp file ${file.name}", e)
                }
            }
        }
        
        return CleanupDetail(
            dataType = DataType.TEMPORARY_FILES,
            itemsDeleted = deletedCount,
            spaceFreedBytes = freedSpace
        )
    }
    
    private suspend fun getCleanupPreviewForPolicy(policy: DataRetentionPolicy): CleanupItemPreview {
        if (!policy.enabled) {
            return CleanupItemPreview(
                dataType = policy.dataType,
                itemCount = 0,
                estimatedSizeBytes = 0L,
                enabled = false
            )
        }
        
        val cutoffTime = System.currentTimeMillis() - (policy.retentionPeriodDays * 24 * 60 * 60 * 1000L)
        
        return when (policy.dataType) {
            DataType.CONVERSATIONS -> {
                val conversations = conversationDao.getConversationsOlderThan(cutoffTime)
                CleanupItemPreview(
                    dataType = policy.dataType,
                    itemCount = conversations.size,
                    estimatedSizeBytes = conversations.sumOf { estimateConversationSize(it) },
                    enabled = true
                )
            }
            DataType.MESSAGES -> {
                val messages = conversationDao.getMessagesOlderThan(cutoffTime)
                CleanupItemPreview(
                    dataType = policy.dataType,
                    itemCount = messages.size,
                    estimatedSizeBytes = messages.sumOf { it.content.length.toLong() * 2 },
                    enabled = true
                )
            }
            else -> CleanupItemPreview(
                dataType = policy.dataType,
                itemCount = 0,
                estimatedSizeBytes = 0L,
                enabled = true
            )
        }
    }
    
    private fun getModelCacheForDeletion(cutoffTime: Long): List<DeletableItem> {
        val cacheDir = File(context.cacheDir, "models")
        val items = mutableListOf<DeletableItem>()
        
        if (cacheDir.exists()) {
            cacheDir.listFiles()?.forEach { file ->
                if (file.lastModified() < cutoffTime) {
                    items.add(DeletableItem(
                        id = file.name,
                        type = DataType.MODEL_CACHE,
                        timestamp = file.lastModified(),
                        sizeBytes = file.length(),
                        description = "Cache file: ${file.name}"
                    ))
                }
            }
        }
        
        return items
    }
    
    private fun getLogsForDeletion(cutoffTime: Long): List<DeletableItem> {
        val logDir = File(context.filesDir, "logs")
        val items = mutableListOf<DeletableItem>()
        
        if (logDir.exists()) {
            logDir.listFiles()?.forEach { file ->
                if (file.lastModified() < cutoffTime) {
                    items.add(DeletableItem(
                        id = file.name,
                        type = DataType.LOGS,
                        timestamp = file.lastModified(),
                        sizeBytes = file.length(),
                        description = "Log file: ${file.name}"
                    ))
                }
            }
        }
        
        return items
    }
    
    private fun getTemporaryFilesForDeletion(cutoffTime: Long): List<DeletableItem> {
        val tempDir = context.cacheDir
        val items = mutableListOf<DeletableItem>()
        
        tempDir.listFiles()?.forEach { file ->
            if (file.lastModified() < cutoffTime && file.name.startsWith("temp_")) {
                items.add(DeletableItem(
                    id = file.name,
                    type = DataType.TEMPORARY_FILES,
                    timestamp = file.lastModified(),
                    sizeBytes = file.length(),
                    description = "Temp file: ${file.name}"
                ))
            }
        }
        
        return items
    }
    
    private suspend fun estimateConversationSize(conversation: Conversation): Long {
        val messages = conversationDao.getMessagesForConversation(conversation.id)
        return messages.sumOf { it.content.length.toLong() * 2 } + conversation.title.length * 2
    }
    
    private fun loadRetentionPolicies(): List<DataRetentionPolicy> {
        return try {
            if (retentionPoliciesFile.exists()) {
                val jsonData = retentionPoliciesFile.readText()
                json.decodeFromString<List<DataRetentionPolicy>>(jsonData)
            } else {
                getDefaultRetentionPolicies()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load retention policies", e)
            getDefaultRetentionPolicies()
        }
    }
    
    private fun saveRetentionPolicies(policies: List<DataRetentionPolicy>) {
        try {
            val jsonData = json.encodeToString(policies)
            retentionPoliciesFile.writeText(jsonData)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save retention policies", e)
            throw e
        }
    }
    
    private fun formatBytes(bytes: Long): String {
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var size = bytes.toDouble()
        var unitIndex = 0
        
        while (size >= 1024 && unitIndex < units.size - 1) {
            size /= 1024
            unitIndex++
        }
        
        return "%.2f %s".format(size, units[unitIndex])
    }
}

// Data classes and enums

@Serializable
data class DataRetentionPolicy(
    val dataType: DataType,
    val retentionPeriodDays: Int,
    val enabled: Boolean = true,
    val autoCleanup: Boolean = true,
    val exportBeforeDelete: Boolean = false,
    val description: String = "",
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)

@Serializable
enum class DataType {
    CONVERSATIONS,
    MESSAGES,
    ATTACHMENTS,
    MODEL_CACHE,
    LOGS,
    TEMPORARY_FILES
}

@Serializable
data class CleanupResult(
    val success: Boolean,
    val totalItemsDeleted: Int = 0,
    val totalSpaceFreed: Long = 0L,
    val durationMs: Long = 0L,
    val error: String? = null,
    val details: List<CleanupDetail> = emptyList()
)

@Serializable
data class CleanupDetail(
    val dataType: DataType,
    val itemsDeleted: Int,
    val spaceFreedBytes: Long,
    val skipped: Boolean = false,
    val reason: String? = null
)

@Serializable
data class CleanupPreview(
    val totalItemsToDelete: Int,
    val estimatedSpaceToFree: Long,
    val items: List<CleanupItemPreview>
)

@Serializable
data class CleanupItemPreview(
    val dataType: DataType,
    val itemCount: Int,
    val estimatedSizeBytes: Long,
    val enabled: Boolean
)

@Serializable
data class DeletableItem(
    val id: String,
    val type: DataType,
    val timestamp: Long,
    val sizeBytes: Long,
    val description: String
)

@Serializable
data class DataExport(
    val exportedAt: Long,
    val items: List<DeletableItem>,
    val reason: String
)

// Extension functions for ConversationDao (these would be added to the actual DAO)
suspend fun ConversationDao.getConversationsOlderThan(timestamp: Long): List<Conversation> {
    // Implementation would be added to the actual DAO
    return emptyList() // Placeholder
}

suspend fun ConversationDao.getMessagesOlderThan(timestamp: Long): List<Message> {
    // Implementation would be added to the actual DAO
    return emptyList() // Placeholder
}

suspend fun ConversationDao.deleteConversation(conversationId: Long) {
    // Implementation would be added to the actual DAO
}

suspend fun ConversationDao.deleteMessage(messageId: Long) {
    // Implementation would be added to the actual DAO
}