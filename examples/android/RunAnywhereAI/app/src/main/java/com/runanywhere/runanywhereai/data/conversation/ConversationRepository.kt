package com.runanywhere.runanywhereai.data.conversation

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File

object ConversationRepository {
    private var store: ConversationStore? = null

    var summaries by mutableStateOf<List<ConversationSummary>>(emptyList())
        private set

    fun initialize(context: Context) {
        if (store == null) {
            store = ConversationStore(File(context.filesDir, "conversations"))
        }
    }

    suspend fun refresh() {
        summaries = store?.loadAll().orEmpty()
            .sortedWith(compareByDescending<StoredConversation> { it.pinned }.thenByDescending { it.updatedAt })
            .map { it.toSummary() }
    }

    suspend fun get(id: String): StoredConversation? = store?.load(id)

    suspend fun save(conversation: StoredConversation) {
        store?.save(conversation)
        refresh()
    }

    suspend fun rename(id: String, title: String) {
        val existing = store?.load(id) ?: return
        store?.save(existing.copy(title = title.trim().ifBlank { existing.title }))
        refresh()
    }

    suspend fun setPinned(id: String, pinned: Boolean) {
        val existing = store?.load(id) ?: return
        store?.save(existing.copy(pinned = pinned))
        refresh()
    }

    suspend fun delete(id: String) {
        store?.delete(id)
        refresh()
    }
}

private fun StoredConversation.toSummary(): ConversationSummary {
    val lastText = messages.lastOrNull { it.text.isNotBlank() }?.text.orEmpty()
    return ConversationSummary(
        id = id,
        title = title,
        updatedAt = updatedAt,
        preview = lastText.replace("\n", " ").trim().take(90),
        pinned = pinned,
    )
}
