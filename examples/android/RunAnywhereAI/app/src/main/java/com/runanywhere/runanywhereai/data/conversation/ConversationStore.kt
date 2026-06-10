package com.runanywhere.runanywhereai.data.conversation

import com.runanywhere.runanywhereai.util.RACLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

internal class ConversationStore(private val dir: File) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    init {
        runCatching { dir.mkdirs() }
    }

    private fun fileFor(id: String) = File(dir, "$id.json")

    suspend fun save(conversation: StoredConversation) = withContext(Dispatchers.IO) {
        val target = fileFor(conversation.id)
        val tmp = File(dir, "${conversation.id}.json.tmp")
        runCatching {
            tmp.writeText(json.encodeToString(conversation))
            if (!tmp.renameTo(target)) {
                target.writeText(tmp.readText())
                tmp.delete()
            }
        }.onFailure {
            RACLog.e("save conversation failed: ${conversation.id}", it)
            tmp.delete()
        }
        Unit
    }

    suspend fun load(id: String): StoredConversation? = withContext(Dispatchers.IO) {
        decode(fileFor(id))
    }

    suspend fun delete(id: String) = withContext(Dispatchers.IO) {
        runCatching { fileFor(id).delete() }
        Unit
    }

    suspend fun loadAll(): List<StoredConversation> = withContext(Dispatchers.IO) {
        val files = dir.listFiles { file -> file.isFile && file.extension == "json" } ?: return@withContext emptyList()
        files.mapNotNull { decode(it) }
    }

    private fun decode(file: File): StoredConversation? =
        runCatching { json.decodeFromString<StoredConversation>(file.readText()) }
            .getOrElse {
                RACLog.w("dropping unreadable conversation: ${file.name} (${it.message})")
                file.delete()
                null
            }
}
