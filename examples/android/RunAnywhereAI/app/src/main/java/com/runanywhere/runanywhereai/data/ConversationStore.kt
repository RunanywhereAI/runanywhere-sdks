package com.runanywhere.runanywhereai.data

import android.annotation.SuppressLint
import android.content.Context
import timber.log.Timber
import com.runanywhere.runanywhereai.domain.models.ChatMessage
import com.runanywhere.runanywhereai.domain.models.Conversation
import com.runanywhere.runanywhereai.domain.models.MessageRole
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.*

/**
 * ConversationStore for Android - Exact match with iOS ConversationStore
 * Handles conversation persistence, management, and search
 */
class ConversationStore private constructor(context: Context) {
    companion object {
        @SuppressLint("StaticFieldLeak")
        @Volatile
        private var instance: ConversationStore? = null

        fun getInstance(context: Context): ConversationStore {
            return instance ?: synchronized(this) {
                instance ?: ConversationStore(context.applicationContext).also { instance = it }
            }
        }
    }

    // Store application context to avoid memory leaks
    private val context: Context = context.applicationContext

    private val _conversations = MutableStateFlow<List<Conversation>>(emptyList())
    val conversations: StateFlow<List<Conversation>> = _conversations.asStateFlow()

    private val _currentConversation = MutableStateFlow<Conversation?>(null)
    val currentConversation: StateFlow<Conversation?> = _currentConversation.asStateFlow()

    private val conversationsDirectory: File
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json =
        Json {
            prettyPrint = true
            ignoreUnknownKeys = true
        }

    init {
        conversationsDirectory = File(context.filesDir, "Conversations")
        if (!conversationsDirectory.exists()) {
            conversationsDirectory.mkdirs()
        }
        ioScope.launch { loadConversations() }
    }

    // MARK: - Public Methods

    /**
     * Create a new conversation
     */
    fun createConversation(title: String? = null): Conversation {
        val conversation =
            Conversation(
                id = UUID.randomUUID().toString(),
                title = title,
                messages = emptyList(),
                createdAt = System.currentTimeMillis(),
                updatedAt = System.currentTimeMillis(),
                modelName = null,
                analytics = null,
                performanceSummary = null,
            )

        _conversations.update { list -> listOf(conversation) + list }
        _currentConversation.value = conversation

        saveConversation(conversation)
        return conversation
    }

    /**
     * Ensure a conversation is in the in-memory list and persisted.
     * If not present (by id), adds it at the front so it appears in history.
     */
    fun ensureConversationInList(conversation: Conversation) {
        var wasAdded = false
        _conversations.update { list ->
            if (list.any { it.id == conversation.id }) {
                list
            } else {
                wasAdded = true
                listOf(conversation) + list
            }
        }
        if (wasAdded) saveConversation(conversation)
    }

    /**
     * Update an existing conversation
     */
    fun updateConversation(conversation: Conversation) {
        val updated = conversation.copy(updatedAt = System.currentTimeMillis())
        var found = false
        _conversations.update { list ->
            list.map {
                if (it.id == conversation.id) {
                    found = true
                    updated
                } else it
            }
        }
        if (found) {
            if (_currentConversation.value?.id == conversation.id) {
                _currentConversation.value = updated
            }
            saveConversation(updated)
        }
    }

    /**
     * Delete a conversation
     */
    fun deleteConversation(conversation: Conversation) {
        _conversations.update { list -> list.filter { it.id != conversation.id } }

        if (_currentConversation.value?.id == conversation.id) {
            _currentConversation.value = _conversations.value.firstOrNull()
        }

        // Delete file off main thread
        ioScope.launch {
            val file = conversationFileURL(conversation.id)
            if (file.exists()) {
                file.delete()
            }
        }
    }

    /**
     * Add a message to a conversation
     */
    fun addMessage(
        message: ChatMessage,
        conversation: Conversation,
    ) {
        val updatedMessages = conversation.messages.toMutableList()
        updatedMessages.add(message)

        var updated =
            conversation.copy(
                messages = updatedMessages,
                updatedAt = System.currentTimeMillis(),
            )

        // Use first user input as conversation title (instead of "New Chat")
        if (message.role == MessageRole.USER && message.content.isNotEmpty() &&
            (updated.title.isNullOrBlank() || updated.title == "New Chat")
        ) {
            updated = updated.copy(title = generateTitle(message.content))
        }

        updateConversation(updated)
    }

    /**
     * Load a conversation by ID
     */
    fun loadConversation(id: String): Conversation? {
        val conversation = _conversations.value.firstOrNull { it.id == id }
        if (conversation != null) {
            _currentConversation.value = conversation
            return conversation
        }

        // Try to load from disk
        val file = conversationFileURL(id)
        if (file.exists()) {
            try {
                val jsonString = file.readText()
                val loaded = json.decodeFromString<Conversation>(jsonString)
                _conversations.update { list -> list + loaded }
                _currentConversation.value = loaded
                return loaded
            } catch (e: Exception) {
                Timber.e(e, "Failed to load conversation from disk")
            }
        }

        return null
    }

    /**
     * Search conversations
     */
    fun searchConversations(query: String): List<Conversation> {
        if (query.isEmpty()) return _conversations.value

        val lowercaseQuery = query.lowercase()

        return _conversations.value.filter { conversation ->
            // Search in title
            if (conversation.title?.lowercase()?.contains(lowercaseQuery) == true) {
                return@filter true
            }

            // Search in messages
            conversation.messages.any { message ->
                message.content.lowercase().contains(lowercaseQuery)
            }
        }
    }

    // MARK: - Private Methods

    /**
     * Load all conversations from disk
     */
    private fun loadConversations() {
        try {
            val files =
                conversationsDirectory.listFiles { file ->
                    file.extension == "json"
                } ?: emptyArray()

            val loaded =
                files.mapNotNull { file ->
                    try {
                        val jsonString = file.readText()
                        json.decodeFromString<Conversation>(jsonString)
                    } catch (e: Exception) {
                        Timber.e(e, "Failed to load conversation: ${file.name}")
                        null
                    }
                }

            // Sort by update date, newest first
            _conversations.value = loaded.sortedByDescending { it.updatedAt }

            // Don't automatically set current conversation - let ChatViewModel create a new one
        } catch (e: Exception) {
            Timber.e(e, "Failed to load conversations")
        }
    }

    /**
     * Save a conversation to disk
     */
    private fun saveConversation(conversation: Conversation) {
        ioScope.launch {
            try {
                val file = conversationFileURL(conversation.id)
                val jsonString = json.encodeToString(conversation)
                file.writeText(jsonString)
            } catch (e: Exception) {
                Timber.e(e, "Failed to save conversation")
            }
        }
    }

    /**
     * Get file URL for a conversation
     */
    private fun conversationFileURL(id: String): File {
        return File(conversationsDirectory, "$id.json")
    }

    /**
     * Generate title from message content
     */
    private fun generateTitle(content: String): String {
        val maxLength = 50
        val cleaned = content.trim()

        val newlineIndex = cleaned.indexOf('\n')
        if (newlineIndex != -1) {
            val firstLine = cleaned.substring(0, newlineIndex)
            return firstLine.take(maxLength)
        }

        return cleaned.take(maxLength)
    }
}
