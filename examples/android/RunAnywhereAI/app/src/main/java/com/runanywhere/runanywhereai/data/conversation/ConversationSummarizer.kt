package com.runanywhere.runanywhereai.data.conversation

import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.data.database.Message
import com.runanywhere.runanywhereai.llm.LLMService
import com.runanywhere.runanywhereai.llm.GenerationOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import java.io.File

/**
 * Service for automatically summarizing long conversations
 */
class ConversationSummarizer(
    private val context: Context,
    private val llmService: LLMService
) {
    companion object {
        private const val TAG = "ConversationSummarizer"
        private const val SUMMARIES_FILE = "conversation_summaries.json"
        private const val DEFAULT_SUMMARY_THRESHOLD = 20 // messages
        private const val SUMMARY_TOKEN_LIMIT = 300
        private const val CONTEXT_WINDOW_LIMIT = 4000 // tokens
    }
    
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        prettyPrint = true
    }
    
    private val summariesFile: File by lazy {
        File(context.filesDir, SUMMARIES_FILE)
    }
    
    /**
     * Check if conversation needs summarization
     */
    fun shouldSummarize(messages: List<Message>): Boolean {
        return messages.size >= DEFAULT_SUMMARY_THRESHOLD ||
               estimateTokenCount(messages) >= CONTEXT_WINDOW_LIMIT
    }
    
    /**
     * Summarize a conversation
     */
    suspend fun summarizeConversation(
        conversationId: Long,
        messages: List<Message>,
        options: SummarizationOptions = SummarizationOptions()
    ): ConversationSummary? = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Starting summarization for conversation $conversationId")
            
            // Filter messages based on options
            val messagesToSummarize = filterMessagesForSummarization(messages, options)
            
            if (messagesToSummarize.isEmpty()) {
                Log.w(TAG, "No messages to summarize for conversation $conversationId")
                return@withContext null
            }
            
            // Generate summary using LLM
            val summaryText = generateSummary(messagesToSummarize, options)
            
            if (summaryText.isBlank()) {
                Log.w(TAG, "Generated summary was empty for conversation $conversationId")
                return@withContext null
            }
            
            // Extract key topics and participants
            val keyTopics = extractKeyTopics(messagesToSummarize, summaryText)
            val participants = extractParticipants(messagesToSummarize)
            
            val summary = ConversationSummary(
                conversationId = conversationId,
                summaryText = summaryText,
                keyTopics = keyTopics,
                participants = participants,
                messageCount = messagesToSummarize.size,
                timeSpan = TimeSpan(
                    startTime = messagesToSummarize.first().timestamp,
                    endTime = messagesToSummarize.last().timestamp
                ),
                summarizedAt = System.currentTimeMillis(),
                summaryType = options.type,
                generationOptions = options.generationOptions
            )
            
            // Save summary
            saveSummary(summary)
            
            Log.d(TAG, "Successfully summarized conversation $conversationId")
            summary
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to summarize conversation $conversationId", e)
            null
        }
    }
    
    /**
     * Get existing summary for conversation
     */
    suspend fun getSummary(conversationId: Long): ConversationSummary? = withContext(Dispatchers.IO) {
        try {
            val summaries = loadSummaries()
            summaries.find { it.conversationId == conversationId }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load summary for conversation $conversationId", e)
            null
        }
    }
    
    /**
     * Get summaries with search and filtering
     */
    suspend fun searchSummaries(
        query: String = "",
        topics: List<String> = emptyList(),
        dateRange: DateRange? = null,
        limit: Int = 50
    ): List<ConversationSummary> = withContext(Dispatchers.IO) {
        try {
            val summaries = loadSummaries()
            
            summaries
                .filter { summary ->
                    // Text search
                    if (query.isNotEmpty()) {
                        summary.summaryText.contains(query, ignoreCase = true) ||
                        summary.keyTopics.any { it.contains(query, ignoreCase = true) }
                    } else true
                }
                .filter { summary ->
                    // Topic filter
                    if (topics.isNotEmpty()) {
                        topics.any { topic ->
                            summary.keyTopics.any { it.contains(topic, ignoreCase = true) }
                        }
                    } else true
                }
                .filter { summary ->
                    // Date range filter
                    dateRange?.let { range ->
                        summary.timeSpan.startTime >= range.startTime &&
                        summary.timeSpan.endTime <= range.endTime
                    } ?: true
                }
                .sortedByDescending { it.summarizedAt }
                .take(limit)
                
        } catch (e: Exception) {
            Log.e(TAG, "Failed to search summaries", e)
            emptyList()
        }
    }
    
    /**
     * Create progressive summary (summarize in chunks for very long conversations)
     */
    suspend fun createProgressiveSummary(
        conversationId: Long,
        messages: List<Message>,
        chunkSize: Int = 50
    ): ProgressiveSummary? = withContext(Dispatchers.IO) {
        try {
            val chunks = messages.chunked(chunkSize)
            val chunkSummaries = mutableListOf<String>()
            
            // Summarize each chunk
            for ((index, chunk) in chunks.withIndex()) {
                Log.d(TAG, "Summarizing chunk ${index + 1}/${chunks.size}")
                
                val chunkSummary = generateSummary(
                    chunk,
                    SummarizationOptions(
                        type = SummaryType.BRIEF,
                        maxLength = 150
                    )
                )
                
                if (chunkSummary.isNotBlank()) {
                    chunkSummaries.add(chunkSummary)
                }
            }
            
            // Create final summary from chunk summaries
            val finalSummary = if (chunkSummaries.size > 1) {
                summarizeText(
                    chunkSummaries.joinToString("\n\n"),
                    SummarizationOptions(
                        type = SummaryType.COMPREHENSIVE,
                        maxLength = 500
                    )
                )
            } else {
                chunkSummaries.firstOrNull() ?: ""
            }
            
            ProgressiveSummary(
                conversationId = conversationId,
                finalSummary = finalSummary,
                chunkSummaries = chunkSummaries,
                totalMessages = messages.size,
                chunksCount = chunks.size,
                createdAt = System.currentTimeMillis()
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create progressive summary", e)
            null
        }
    }
    
    /**
     * Update summary when new messages are added
     */
    suspend fun updateSummaryIncremental(
        conversationId: Long,
        newMessages: List<Message>,
        existingSummary: ConversationSummary
    ): ConversationSummary? = withContext(Dispatchers.IO) {
        try {
            // Generate summary for new messages only
            val newMessagesSummary = generateSummary(
                newMessages,
                SummarizationOptions(type = SummaryType.BRIEF, maxLength = 200)
            )
            
            // Combine with existing summary
            val combinedText = "${existingSummary.summaryText}\n\nRecent updates:\n$newMessagesSummary"
            
            // Summarize the combined text to keep it concise
            val updatedSummaryText = summarizeText(
                combinedText,
                SummarizationOptions(type = SummaryType.COMPREHENSIVE)
            )
            
            // Update key topics
            val newTopics = extractKeyTopics(newMessages, newMessagesSummary)
            val combinedTopics = (existingSummary.keyTopics + newTopics).distinct()
            
            val updatedSummary = existingSummary.copy(
                summaryText = updatedSummaryText,
                keyTopics = combinedTopics,
                messageCount = existingSummary.messageCount + newMessages.size,
                timeSpan = existingSummary.timeSpan.copy(
                    endTime = newMessages.lastOrNull()?.timestamp ?: existingSummary.timeSpan.endTime
                ),
                summarizedAt = System.currentTimeMillis()
            )
            
            saveSummary(updatedSummary)
            updatedSummary
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update summary incrementally", e)
            null
        }
    }
    
    /**
     * Delete summary
     */
    suspend fun deleteSummary(conversationId: Long): Boolean = withContext(Dispatchers.IO) {
        try {
            val summaries = loadSummaries().toMutableList()
            val removed = summaries.removeAll { it.conversationId == conversationId }
            
            if (removed) {
                saveSummaries(summaries)
            }
            
            removed
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete summary", e)
            false
        }
    }
    
    // Private helper methods
    
    private suspend fun generateSummary(
        messages: List<Message>,
        options: SummarizationOptions
    ): String {
        val conversationText = formatMessagesForSummarization(messages)
        return summarizeText(conversationText, options)
    }
    
    private suspend fun summarizeText(
        text: String,
        options: SummarizationOptions
    ): String {
        val prompt = buildSummarizationPrompt(text, options)
        
        val generationOptions = GenerationOptions(
            maxTokens = options.maxLength,
            temperature = options.generationOptions?.temperature ?: 0.3f,
            topP = options.generationOptions?.topP ?: 0.9f
        )
        
        val result = llmService.generate(prompt, generationOptions)
        return result.text.trim()
    }
    
    private fun buildSummarizationPrompt(text: String, options: SummarizationOptions): String {
        val typeInstruction = when (options.type) {
            SummaryType.BRIEF -> "Create a brief summary that captures the main points discussed."
            SummaryType.DETAILED -> "Create a detailed summary that includes key points, decisions made, and important details."
            SummaryType.COMPREHENSIVE -> "Create a comprehensive summary that covers all important aspects of the conversation."
            SummaryType.BULLET_POINTS -> "Create a summary using bullet points to organize the main topics and key points."
            SummaryType.ACTION_ITEMS -> "Focus on identifying action items, decisions, and next steps from the conversation."
        }
        
        val lengthInstruction = "Keep the summary to approximately ${options.maxLength} words."
        
        return """
            Please summarize the following conversation:
            
            $typeInstruction
            $lengthInstruction
            
            Conversation:
            $text
            
            Summary:
        """.trimIndent()
    }
    
    private fun formatMessagesForSummarization(messages: List<Message>): String {
        return messages.joinToString("\n\n") { message ->
            val role = when {
                message.isFromUser -> "User"
                else -> "Assistant"
            }
            "$role: ${message.content}"
        }
    }
    
    private fun filterMessagesForSummarization(
        messages: List<Message>,
        options: SummarizationOptions
    ): List<Message> {
        return messages.filter { message ->
            // Filter out very short messages if specified
            if (options.excludeShortMessages && message.content.length < 10) {
                false
            } else true
        }.let { filtered ->
            // Take only recent messages if timeframe is specified
            options.timeFrameHours?.let { hours ->
                val cutoffTime = System.currentTimeMillis() - (hours * 60 * 60 * 1000)
                filtered.filter { it.timestamp >= cutoffTime }
            } ?: filtered
        }
    }
    
    private fun extractKeyTopics(messages: List<Message>, summaryText: String): List<String> {
        // Simple keyword extraction - in production, use more sophisticated NLP
        val commonWords = setOf(
            "the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
            "from", "up", "about", "into", "through", "during", "before", "after", "above",
            "below", "between", "among", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
            "may", "might", "must", "can", "cannot", "a", "an", "this", "that", "these",
            "those", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us",
            "them", "my", "your", "his", "her", "its", "our", "their"
        )
        
        val words = (summaryText + " " + messages.joinToString(" ") { it.content })
            .lowercase()
            .replace(Regex("[^a-zA-Z\\s]"), "")
            .split("\\s+".toRegex())
            .filter { it.length > 3 && !commonWords.contains(it) }
        
        return words
            .groupingBy { it }
            .eachCount()
            .toList()
            .sortedByDescending { it.second }
            .take(10)
            .map { it.first }
    }
    
    private fun extractParticipants(messages: List<Message>): List<String> {
        return messages
            .map { if (it.isFromUser) "User" else "Assistant" }
            .distinct()
    }
    
    private fun estimateTokenCount(messages: List<Message>): Int {
        // Rough estimation: ~4 characters per token
        val totalChars = messages.sumOf { it.content.length }
        return totalChars / 4
    }
    
    private fun loadSummaries(): List<ConversationSummary> {
        return try {
            if (summariesFile.exists()) {
                val jsonData = summariesFile.readText()
                json.decodeFromString<List<ConversationSummary>>(jsonData)
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load summaries", e)
            emptyList()
        }
    }
    
    private fun saveSummary(summary: ConversationSummary) {
        try {
            val summaries = loadSummaries().toMutableList()
            val existingIndex = summaries.indexOfFirst { it.conversationId == summary.conversationId }
            
            if (existingIndex >= 0) {
                summaries[existingIndex] = summary
            } else {
                summaries.add(summary)
            }
            
            saveSummaries(summaries)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save summary", e)
            throw e
        }
    }
    
    private fun saveSummaries(summaries: List<ConversationSummary>) {
        try {
            val jsonData = json.encodeToString(summaries)
            summariesFile.writeText(jsonData)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save summaries", e)
            throw e
        }
    }
}

// Data classes

@Serializable
data class ConversationSummary(
    val conversationId: Long,
    val summaryText: String,
    val keyTopics: List<String>,
    val participants: List<String>,
    val messageCount: Int,
    val timeSpan: TimeSpan,
    val summarizedAt: Long,
    val summaryType: SummaryType,
    val generationOptions: SummarizationGenerationOptions?
)

@Serializable
data class ProgressiveSummary(
    val conversationId: Long,
    val finalSummary: String,
    val chunkSummaries: List<String>,
    val totalMessages: Int,
    val chunksCount: Int,
    val createdAt: Long
)

@Serializable
data class TimeSpan(
    val startTime: Long,
    val endTime: Long
) {
    val durationMs: Long get() = endTime - startTime
    val durationHours: Double get() = durationMs / (1000.0 * 60 * 60)
}

@Serializable
data class DateRange(
    val startTime: Long,
    val endTime: Long
)

@Serializable
enum class SummaryType {
    BRIEF,
    DETAILED,
    COMPREHENSIVE,
    BULLET_POINTS,
    ACTION_ITEMS
}

@Serializable
data class SummarizationOptions(
    val type: SummaryType = SummaryType.COMPREHENSIVE,
    val maxLength: Int = SUMMARY_TOKEN_LIMIT,
    val excludeShortMessages: Boolean = true,
    val timeFrameHours: Int? = null, // Only summarize messages from last N hours
    val generationOptions: SummarizationGenerationOptions? = null
)

@Serializable
data class SummarizationGenerationOptions(
    val temperature: Float = 0.3f,
    val topP: Float = 0.9f,
    val maxTokens: Int = 300
)

// Extension functions

fun ConversationSummary.isRecent(hoursThreshold: Int = 24): Boolean {
    val thresholdTime = System.currentTimeMillis() - (hoursThreshold * 60 * 60 * 1000)
    return summarizedAt >= thresholdTime
}

fun List<ConversationSummary>.groupByTopic(): Map<String, List<ConversationSummary>> {
    return flatMap { summary ->
        summary.keyTopics.map { topic -> topic to summary }
    }.groupBy({ it.first }, { it.second })
}

fun List<ConversationSummary>.filterByTimeRange(range: DateRange): List<ConversationSummary> {
    return filter { summary ->
        summary.timeSpan.startTime >= range.startTime &&
        summary.timeSpan.endTime <= range.endTime
    }
}