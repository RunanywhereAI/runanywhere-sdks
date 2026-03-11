package com.runanywhere.runanywhereai.repositories

import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.data.db.ChatDatabase
import com.runanywhere.runanywhereai.data.db.toDomain
import com.runanywhere.runanywhereai.data.db.toEntity
import com.runanywhere.runanywhereai.models.ChatMessage
import com.runanywhere.runanywhereai.models.Conversation
import com.runanywhere.runanywhereai.models.MessageRole
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.util.UUID

class ConversationRepository(context: Context) {

    private val dao = ChatDatabase.getInstance(context).chatDao()

    private val _conversations = MutableStateFlow<ImmutableList<Conversation>>(persistentListOf())
    val conversations: StateFlow<ImmutableList<Conversation>> = _conversations.asStateFlow()

    /** Collect Room's Flow into the in-memory StateFlow. Call once after init. */
    suspend fun loadConversations() {
        withContext(Dispatchers.IO) {
            dao.getConversations().collect { entities ->
                _conversations.value = entities.map { it.toDomain() }.toImmutableList()
            }
        }
    }

    suspend fun createConversation(title: String? = null): Conversation {
        val conversation = Conversation(
            id = UUID.randomUUID().toString(),
            title = title,
        )
        withContext(Dispatchers.IO) {
            dao.insertConversation(conversation.toEntity())
        }
        return conversation
    }

    suspend fun addMessage(conversationId: String, message: ChatMessage) {
        withContext(Dispatchers.IO) {
            try {
                dao.insertMessage(message.toEntity(conversationId))

                // Auto-generate title from first user message
                val conv = dao.getConversation(conversationId)
                if (conv != null &&
                    conv.title.isNullOrBlank() &&
                    message.role == MessageRole.USER &&
                    message.content.isNotBlank()
                ) {
                    dao.updateConversation(
                        conv.copy(
                            title = generateTitle(message.content),
                            updatedAt = System.currentTimeMillis(),
                            messageCount = conv.messageCount + 1,
                        ),
                    )
                } else if (conv != null) {
                    dao.updateConversation(
                        conv.copy(
                            updatedAt = System.currentTimeMillis(),
                            messageCount = conv.messageCount + 1,
                        ),
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to add message", e)
            }
        }
    }

    suspend fun updateConversation(conversation: Conversation) {
        withContext(Dispatchers.IO) {
            try {
                val entity = conversation.toEntity().copy(updatedAt = System.currentTimeMillis())
                dao.updateConversation(entity)

                // Persist all messages (upsert)
                conversation.messages.forEach { msg ->
                    dao.insertMessage(msg.toEntity(conversation.id))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update conversation", e)
            }
        }
    }

    /** Load a conversation with its messages from Room. */
    suspend fun loadConversation(conversationId: String): Conversation? {
        return withContext(Dispatchers.IO) {
            try {
                val entity = dao.getConversation(conversationId) ?: return@withContext null
                val messages = dao.getMessagesForConversation(conversationId).map { it.toDomain() }
                entity.toDomain(messages)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load conversation $conversationId", e)
                null
            }
        }
    }

    suspend fun deleteConversation(id: String) {
        withContext(Dispatchers.IO) {
            try {
                dao.deleteConversation(id)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete conversation $id", e)
            }
        }
    }

    suspend fun deleteAllConversations() {
        withContext(Dispatchers.IO) {
            try {
                dao.deleteAllConversations()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete all conversations", e)
            }
        }
    }

    private fun generateTitle(content: String): String {
        val cleaned = content.trim()
        val firstLine = cleaned.substringBefore('\n')
        return firstLine.take(MAX_TITLE_LENGTH)
    }

    companion object {
        private const val TAG = "ConversationRepository"
        private const val MAX_TITLE_LENGTH = 50
    }
}
