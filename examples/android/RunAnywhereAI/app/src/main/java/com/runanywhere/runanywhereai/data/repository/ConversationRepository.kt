package com.runanywhere.runanywhereai.data.repository

import com.runanywhere.runanywhereai.data.database.*
import com.runanywhere.runanywhereai.data.models.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ConversationRepository @Inject constructor(
    private val conversationDao: ConversationDao,
    private val messageDao: MessageDao
) {
    fun getAllConversations(): Flow<List<Conversation>> {
        return conversationDao.getAllConversations().map { entities ->
            entities.map { it.toConversation() }
        }
    }
    
    suspend fun createConversation(
        title: String,
        framework: String,
        modelName: String
    ): Conversation {
        val conversation = ConversationEntity(
            id = UUID.randomUUID().toString(),
            title = title,
            createdAt = Instant.now(),
            updatedAt = Instant.now(),
            framework = framework,
            modelName = modelName
        )
        conversationDao.insertConversation(conversation)
        return conversation.toConversation()
    }
    
    suspend fun addMessage(
        conversationId: String,
        role: String,
        content: String,
        tokenCount: Int = 0,
        generationTimeMs: Long? = null
    ): Message {
        val message = MessageEntity(
            id = UUID.randomUUID().toString(),
            conversationId = conversationId,
            role = role,
            content = content,
            timestamp = Instant.now(),
            tokenCount = tokenCount,
            generationTimeMs = generationTimeMs
        )
        messageDao.insertMessage(message)
        
        // Update conversation
        val conversation = conversationDao.getConversation(conversationId)
        conversation?.let {
            conversationDao.updateConversation(
                it.copy(
                    updatedAt = Instant.now(),
                    messageCount = it.messageCount + 1,
                    totalTokens = it.totalTokens + tokenCount
                )
            )
        }
        
        return message.toMessage()
    }
    
    fun getConversationMessages(conversationId: String): Flow<List<Message>> {
        return messageDao.getMessagesForConversation(conversationId).map { entities ->
            entities.map { it.toMessage() }
        }
    }
    
    suspend fun deleteConversation(conversationId: String) {
        conversationDao.getConversation(conversationId)?.let {
            conversationDao.deleteConversation(it)
        }
    }
    
    suspend fun exportConversation(conversationId: String): String {
        // TODO: Implement export logic (JSON, TXT, etc.)
        return ""
    }
    
    suspend fun manageContextWindow(
        conversationId: String,
        maxTokens: Int,
        strategy: ContextWindowStrategy = ContextWindowStrategy.SLIDING
    ) {
        val totalTokens = messageDao.getTotalTokensForConversation(conversationId)
        
        if (totalTokens > maxTokens) {
            when (strategy) {
                ContextWindowStrategy.SLIDING -> {
                    // Remove oldest messages until under limit
                    // Implementation...
                }
                ContextWindowStrategy.SUMMARIZE -> {
                    // Summarize old messages
                    // Implementation...
                }
                ContextWindowStrategy.TRUNCATE -> {
                    // Hard truncate at limit
                    // Implementation...
                }
            }
        }
    }
}

enum class ContextWindowStrategy {
    SLIDING,    // Remove oldest messages
    SUMMARIZE,  // Summarize old context
    TRUNCATE    // Hard cut at token limit
}