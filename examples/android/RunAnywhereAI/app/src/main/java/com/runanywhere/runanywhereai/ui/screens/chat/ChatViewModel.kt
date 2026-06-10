package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.LLMStreamFinalResult
import ai.runanywhere.proto.v1.ThinkingTagPattern
import ai.runanywhere.proto.v1.TokenKind
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.conversation.ConversationRepository
import com.runanywhere.runanywhereai.data.conversation.StoredConversation
import com.runanywhere.runanywhereai.data.conversation.StoredMessage
import com.runanywhere.runanywhereai.data.conversation.StoredStats
import com.runanywhere.runanywhereai.data.conversation.StoredTool
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.RAToolCallingOptions
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.generateWithTools
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

class ChatViewModel : ViewModel() {

    val messages = mutableStateListOf<ChatMessage>()

    var input by mutableStateOf("")
        private set
    var isGenerating by mutableStateOf(false)
        private set
    var toolsEnabled by mutableStateOf(false)
        private set

    val canSend: Boolean get() = input.isNotBlank() && !isGenerating && GlobalState.model.isLoaded

    private var job: Job? = null
    private var conversationId: String? = null
    private var createdAt: Long = 0L

    fun onInputChange(value: String) {
        input = value
    }

    fun sendPrompt(prompt: String) {
        if (isGenerating) return
        input = prompt
        send()
    }

    fun toggleTools() {
        toolsEnabled = !toolsEnabled
    }

    fun send() {
        if (!canSend) return
        val prompt = input.trim()
        input = ""
        messages += ChatMessage(prompt, isUser = true)
        val replyIndex = messages.size
        messages += ChatMessage("", isUser = false)
        isGenerating = true

        job = viewModelScope.launch {
            try {
                when {
                    toolsEnabled -> generateWithTools(prompt, replyIndex)
                    SettingsRepository.settings.streaming -> streamReply(prompt, replyIndex)
                    else -> generateReply(prompt, replyIndex)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("generation failed", e)
                messages[replyIndex] = messages[replyIndex].copy(text = "Error: ${e.message}")
            } finally {
                isGenerating = false
                persist()
            }
        }
    }

    private fun generationOptions(): RALLMGenerationOptions {
        val s = SettingsRepository.settings
        return RALLMGenerationOptions(
            max_tokens = s.maxTokens,
            temperature = s.temperature,
            system_prompt = s.systemPrompt.ifBlank { null },
            thinking_pattern = ThinkingTagPattern(open_tag = "<think>", close_tag = "</think>"),
        )
    }

    private suspend fun generateReply(prompt: String, index: Int) {
        val result = RunAnywhere.generate(prompt, generationOptions())
        if (!result.error_message.isNullOrBlank()) {
            messages[index] = messages[index].copy(text = "Error: ${result.error_message}")
            return
        }
        val totalMs = result.generation_time_ms.toLong()
        val tps = result.tokens_per_second.takeIf { it > 0 }
            ?: if (totalMs > 0 && result.tokens_generated > 0) result.tokens_generated * 1000.0 / totalMs else 0.0
        messages[index] = messages[index].copy(
            text = result.text,
            thinking = result.thinking_content?.takeIf { it.isNotBlank() },
            stats = GenerationStats(
                tokens = result.tokens_generated,
                tokensPerSecond = tps,
                timeToFirstTokenMs = result.ttft_ms?.toLong()?.takeIf { it > 0 },
                totalTimeMs = totalMs,
            ),
        )
    }

    private suspend fun streamReply(prompt: String, index: Int) {
        val options = generationOptions()
        val answer = StringBuilder()
        val thinking = StringBuilder()
        var finalResult: LLMStreamFinalResult? = null
        var streamError: String? = null
        val startTime = System.currentTimeMillis()
        var firstTokenTime: Long? = null

        RunAnywhere.generateStream(prompt, options).collect { event ->
            if (event.is_final) {
                finalResult = event.result
                if (event.error_message.isNotEmpty()) streamError = event.error_message
                return@collect
            }
            if (event.token.isNotEmpty()) {
                if (firstTokenTime == null) firstTokenTime = System.currentTimeMillis()
                when (event.kind) {
                    TokenKind.TOKEN_KIND_THOUGHT -> thinking.append(event.token)
                    else -> answer.append(event.token)
                }
                messages[index] = messages[index].copy(
                    text = answer.toString(),
                    thinking = thinking.toString().takeIf { it.isNotBlank() },
                )
            }
        }

        if (streamError != null) {
            messages[index] = messages[index].copy(text = "Error: $streamError", thinking = null)
            return
        }

        val finalThinking = finalResult?.thinking_content?.takeIf { it.isNotBlank() }
            ?: thinking.toString().takeIf { it.isNotBlank() }
        messages[index] = messages[index].copy(
            text = finalResult?.text?.takeIf { it.isNotBlank() } ?: answer.toString(),
            thinking = finalThinking,
            stats = buildStats(finalResult, startTime, firstTokenTime),
        )
    }

    private suspend fun generateWithTools(prompt: String, index: Int) {
        val s = SettingsRepository.settings
        val toolOptions = RAToolCallingOptions(
            max_iterations = 3,
            auto_execute = true,
            temperature = s.temperature,
            max_tokens = s.maxTokens,
        )
        val result = RunAnywhere.generateWithTools(
            prompt = prompt,
            options = RALLMGenerationOptions(),
            toolOptions = toolOptions,
            toolChoice = null,
            forcedToolName = null,
        )
        val toolInfo = result.tool_calls.firstOrNull()?.let { call ->
            val toolResult = result.tool_results.firstOrNull { it.name == call.name }
            ToolCallInfo(
                name = call.name,
                arguments = prettyJson(call.arguments_json),
                result = toolResult?.result_json?.let(::prettyJson),
                success = toolResult != null && toolResult.error.isNullOrBlank(),
                error = toolResult?.error,
            )
        }
        val content = result.text.ifBlank {
            result.error_message?.takeIf { it.isNotBlank() }?.let { "Error: $it" }
                ?: toolInfo?.let { "Used ${it.name}." }
                ?: "(no response)"
        }
        messages[index] = messages[index].copy(
            text = content,
            thinking = result.thinking_content?.takeIf { it.isNotBlank() },
            tool = toolInfo,
        )
    }

    fun stop() {
        job?.cancel()
        viewModelScope.launch { RunAnywhere.cancelGeneration() }
        isGenerating = false
    }

    fun clearChat() {
        job?.cancel()
        messages.clear()
        input = ""
        isGenerating = false
        conversationId = null
        createdAt = 0L
    }

    fun loadConversation(id: String) {
        viewModelScope.launch {
            val stored = ConversationRepository.get(id) ?: return@launch
            job?.cancel()
            isGenerating = false
            input = ""
            conversationId = stored.id
            createdAt = stored.createdAt
            messages.clear()
            messages.addAll(stored.messages.map { it.toUi() })
        }
    }

    fun deleteConversation(id: String) {
        viewModelScope.launch {
            ConversationRepository.delete(id)
            if (id == conversationId) clearChat()
        }
    }

    fun rename(id: String, title: String) {
        viewModelScope.launch { ConversationRepository.rename(id, title) }
    }

    fun setPinned(id: String, pinned: Boolean) {
        viewModelScope.launch { ConversationRepository.setPinned(id, pinned) }
    }

    private fun persist() {
        if (messages.none { it.isUser }) return
        val id = conversationId ?: UUID.randomUUID().toString().also {
            conversationId = it
            createdAt = System.currentTimeMillis()
        }
        val createdLocal = createdAt
        val derivedTitle = messages.firstOrNull { it.isUser }?.text?.trim()?.take(60)?.ifBlank { null } ?: "New chat"
        val storedMessages = messages.map { it.toStored() }
        viewModelScope.launch {
            val existing = ConversationRepository.get(id)
            val now = System.currentTimeMillis()
            ConversationRepository.save(
                StoredConversation(
                    id = id,
                    title = existing?.title ?: derivedTitle,
                    createdAt = existing?.createdAt ?: createdLocal.takeIf { it > 0 } ?: now,
                    updatedAt = now,
                    pinned = existing?.pinned ?: false,
                    messages = storedMessages,
                ),
            )
        }
    }
}

private fun ChatMessage.toStored() = StoredMessage(
    text = text,
    isUser = isUser,
    thinking = thinking,
    tool = tool?.let { StoredTool(it.name, it.arguments, it.result, it.success, it.error) },
    stats = stats?.let { StoredStats(it.tokens, it.tokensPerSecond, it.timeToFirstTokenMs, it.totalTimeMs) },
)

private fun StoredMessage.toUi() = ChatMessage(
    text = text,
    isUser = isUser,
    thinking = thinking,
    tool = tool?.let { ToolCallInfo(it.name, it.arguments, it.result, it.success, it.error) },
    stats = stats?.let { GenerationStats(it.tokens, it.tokensPerSecond, it.timeToFirstTokenMs, it.totalTimeMs) },
)

private fun buildStats(
    result: LLMStreamFinalResult?,
    startTime: Long,
    firstTokenTime: Long?,
): GenerationStats {
    val now = System.currentTimeMillis()
    val tokens = result?.completion_tokens ?: 0
    val totalTimeMs = result?.total_time_ms?.takeIf { it > 0 } ?: (now - startTime)
    val ttft = result?.time_to_first_token_ms?.takeIf { it > 0 }
        ?: firstTokenTime?.let { it - startTime }?.takeIf { it > 0 }
    val tps = result?.tokens_per_second?.toDouble()?.takeIf { it > 0 }
        ?: if (totalTimeMs > 0 && tokens > 0) tokens * 1000.0 / totalTimeMs else 0.0
    return GenerationStats(
        tokens = tokens,
        tokensPerSecond = tps,
        timeToFirstTokenMs = ttft,
        totalTimeMs = totalTimeMs,
    )
}

private fun prettyJson(raw: String): String = runCatching {
    val trimmed = raw.trim()
    when {
        trimmed.isEmpty() -> raw
        trimmed.startsWith("[") -> org.json.JSONArray(trimmed).toString(2)
        else -> org.json.JSONObject(trimmed).toString(2)
    }
}.getOrDefault(raw)
