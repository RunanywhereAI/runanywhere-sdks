package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.GenerationEventKind
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.VLMImageFormat
import ai.runanywhere.proto.v1.VLMStreamEventKind
import android.app.Application
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.conversation.ConversationRepository
import com.runanywhere.runanywhereai.data.conversation.GenerationMode
import com.runanywhere.runanywhereai.data.conversation.StoredAttachment
import com.runanywhere.runanywhereai.data.conversation.StoredAttachmentKind
import com.runanywhere.runanywhereai.data.conversation.StoredConversation
import com.runanywhere.runanywhereai.data.conversation.StoredMessage
import com.runanywhere.runanywhereai.data.conversation.StoredSource
import com.runanywhere.runanywhereai.data.conversation.StoredStats
import com.runanywhere.runanywhereai.data.conversation.StoredTool
import com.runanywhere.runanywhereai.data.rag.DocumentExtractor
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.SDKEvent
import com.runanywhere.sdk.public.extensions.LLM.RAToolCallingOptions
import com.runanywhere.sdk.public.extensions.Models.analyticsKey
import com.runanywhere.sdk.public.extensions.aggregateStream
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.defaults
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.generateWithTools
import com.runanywhere.sdk.public.extensions.getRegisteredTools
import com.runanywhere.sdk.public.extensions.ragCreatePipeline
import com.runanywhere.sdk.public.extensions.ragDestroyPipeline
import com.runanywhere.sdk.public.extensions.ragGetStatistics
import com.runanywhere.sdk.public.extensions.ragIngest
import com.runanywhere.sdk.public.extensions.ragQuery
import com.runanywhere.sdk.public.extensions.processImageStream
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

class ChatViewModel(application: Application) : AndroidViewModel(application) {

    val messages = mutableStateListOf<ChatMessage>()

    var input by mutableStateOf("")
        private set
    var isGenerating by mutableStateOf(false)
        private set

    // Mirrors iOS Conversation.modelName restore (LLMViewModel+ModelManagement
    // loadConversation): the recorded model is preselected for display only,
    // never auto-loaded.
    var conversationModelName by mutableStateOf<String?>(null)
        private set

    val conversationCreatedAt: Long get() = createdAt

    // Mirrors iOS LLMViewModel.useToolCalling: the in-chat toggle reads and
    // writes the persisted setting shared with the Web & Tools screen.
    val toolsEnabled: Boolean get() = SettingsRepository.settings.toolCallingEnabled

    val canSend: Boolean get() = input.isNotBlank() && !isGenerating && GlobalState.model.isLoaded

    private var job: Job? = null
    private var conversationId: String? = null
    private var createdAt: Long = 0L
    private var ragPipelineKey: Pair<String, String>? = null

    // TTFT/completion metrics from the SDK event bus, keyed like iOS
    // LLMViewModel.firstTokenLatencies. The chat runs one generation at a time,
    // so the latest values are merged into the message stats (mirrors iOS
    // activeGenerationTTFTMs).
    private val firstTokenLatencies = mutableMapOf<String, Long>()
    private var activeGenerationTTFTMs: Long? = null
    private var activeGenerationMetrics: SdkGenerationMetrics? = null

    init {
        // Mirrors iOS LLMViewModel+Events.subscribeToModelLifecycle: generation
        // analytics (TTFT, completion metrics) come from the raw SDK event bus.
        viewModelScope.launch {
            RunAnywhere.events.events.collect { event ->
                if (event.category == EventCategory.EVENT_CATEGORY_LLM ||
                    event.component == SDKComponent.SDK_COMPONENT_LLM
                ) {
                    handleGenerationEvent(event)
                }
            }
        }
    }

    fun onInputChange(value: String) {
        input = value
    }

    fun sendPrompt(prompt: String) {
        if (isGenerating) return
        input = prompt
        send()
    }

    fun toggleTools() {
        SettingsRepository.setToolCallingEnabled(!toolsEnabled)
    }

    fun send() {
        if (!canSend) return
        val prompt = input.trim()
        input = ""
        messages += ChatMessage(prompt, isUser = true)
        val replyIndex = messages.size
        messages += ChatMessage("", isUser = false)
        isGenerating = true
        activeGenerationTTFTMs = null
        activeGenerationMetrics = null

        job = viewModelScope.launch {
            try {
                when {
                    toolsEnabled && RunAnywhere.getRegisteredTools().isNotEmpty() ->
                        generateWithTools(prompt, replyIndex)
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

    fun sendImage(uri: Uri, loadedModelName: String?) {
        if (isGenerating) return
        val prompt = input.trim().ifBlank { "Describe this image in detail." }
        input = ""
        val name = displayName(uri) ?: "Selected image"
        messages += ChatMessage(
            text = prompt,
            isUser = true,
            attachment = ChatAttachment(
                kind = ChatAttachmentKind.IMAGE,
                name = name,
                detail = loadedModelName?.let { "Image model: $it" },
            ),
        )
        val replyIndex = messages.size
        messages += ChatMessage("", isUser = false)
        isGenerating = true
        activeGenerationTTFTMs = null
        activeGenerationMetrics = null

        job = viewModelScope.launch {
            var file: File? = null
            try {
                file = withContext(Dispatchers.IO) { copyUriToCache(uri, "chat_image_", imageCacheSuffix(uri)) }
                val image = RAVLMImage(
                    file_path = file.absolutePath,
                    format = VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
                )
                val options = RAVLMGenerationOptions(prompt = prompt, max_tokens = 300, temperature = 0.7f)
                var accumulated = ""
                RunAnywhere.processImageStream(image, options).collect { event ->
                    when (event.kind) {
                        VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN -> {
                            if (event.token.isNotEmpty()) {
                                accumulated += event.token
                                messages[replyIndex] = messages[replyIndex].copy(text = accumulated)
                            }
                        }
                        VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED -> {
                            val result = event.result ?: return@collect
                            val text = result.text.ifBlank { accumulated }
                            messages[replyIndex] = messages[replyIndex].copy(
                                text = text.ifBlank { "I could not read that image." },
                                stats = GenerationStats(
                                    tokens = result.completion_tokens,
                                    tokensPerSecond = result.tokens_per_second.toDouble(),
                                    timeToFirstTokenMs = result.time_to_first_token_ms.takeIf { it > 0 },
                                    totalTimeMs = result.processing_time_ms,
                                    modelName = loadedModelName,
                                    mode = GenerationMode.STREAMING,
                                ),
                            )
                        }
                        else -> Unit
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("image question failed", e)
                messages[replyIndex] = messages[replyIndex].copy(text = "Error: ${e.message}")
            } finally {
                file?.delete()
                isGenerating = false
                persist()
            }
        }
    }

    fun sendDocument(uri: Uri, embeddingModel: RAModelInfo?, answerModel: RAModelInfo?) {
        if (isGenerating) return
        val prompt = input.trim().ifBlank { "Summarize this document." }
        input = ""
        val name = displayName(uri) ?: "Selected document"
        val answerModelName = answerModel?.name
        messages += ChatMessage(
            text = prompt,
            isUser = true,
            attachment = ChatAttachment(
                kind = ChatAttachmentKind.DOCUMENT,
                name = name,
                detail = answerModelName?.let { "Answer model: $it" },
            ),
        )
        val replyIndex = messages.size
        messages += ChatMessage("", isUser = false)
        isGenerating = true
        activeGenerationTTFTMs = null
        activeGenerationMetrics = null

        job = viewModelScope.launch {
            try {
                val embedding = embeddingModel ?: error("Choose or download a document index model first.")
                val answer = answerModel ?: error("Choose or download a document answer model first.")
                val doc = withContext(Dispatchers.IO) { DocumentExtractor.extract(getApplication(), uri) }
                ensureRagPipeline(embedding, answer)
                RunAnywhere.ragIngest(doc.text, doc.metadataJSON)
                runCatching { RunAnywhere.ragGetStatistics() }
                val result = RunAnywhere.ragQuery(prompt, RAGQueryOptions.defaults(question = prompt))
                val sources = result.retrieved_chunks.map {
                    ChatSource(
                        text = it.text.trim(),
                        score = it.similarity_score,
                        document = it.source_document.orEmpty(),
                    )
                }
                messages[replyIndex] = messages[replyIndex].copy(
                    text = result.answer.ifBlank { "I could not find an answer in that document." },
                    sources = sources,
                    stats = GenerationStats(
                        tokens = 0,
                        tokensPerSecond = 0.0,
                        timeToFirstTokenMs = null,
                        totalTimeMs = result.total_time_ms,
                        modelName = answerModelName,
                        mode = GenerationMode.NON_STREAMING,
                    ),
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("document question failed", e)
                messages[replyIndex] = messages[replyIndex].copy(text = "Error: ${e.message}")
            } finally {
                isGenerating = false
                persist()
            }
        }
    }

    // Mirrors iOS LLMViewModel+Events.handleGenerationEvent: record TTFT on
    // FIRST_TOKEN_GENERATED and completion metrics on COMPLETED/STREAM_COMPLETED.
    private fun handleGenerationEvent(event: SDKEvent) {
        val generation = event.generation ?: return
        val generationId = generation.session_id.ifEmpty { event.operation_id }
        when (generation.kind) {
            GenerationEventKind.GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED -> {
                firstTokenLatencies[generationId] = generation.first_token_latency_ms
                activeGenerationTTFTMs = generation.first_token_latency_ms
            }
            GenerationEventKind.GENERATION_EVENT_KIND_COMPLETED,
            GenerationEventKind.GENERATION_EVENT_KIND_STREAM_COMPLETED,
            -> {
                val outputTokens = generation.tokens_used
                val durationMs = generation.latency_ms
                val tps = if (durationMs > 0 && outputTokens > 0) {
                    outputTokens * 1000.0 / durationMs
                } else {
                    0.0
                }
                activeGenerationMetrics = SdkGenerationMetrics(
                    inputTokens = generation.input_tokens,
                    outputTokens = outputTokens,
                    durationMs = durationMs,
                    tokensPerSecond = tps,
                    timeToFirstTokenMs = firstTokenLatencies[generationId] ?: activeGenerationTTFTMs,
                )
                if (firstTokenLatencies.size > MAX_TRACKED_GENERATIONS) firstTokenLatencies.clear()
            }
            else -> Unit
        }
    }

    private fun generationOptions(): RALLMGenerationOptions {
        val s = SettingsRepository.settings
        return RALLMGenerationOptions(
            max_tokens = s.maxTokens,
            temperature = s.temperature,
            system_prompt = s.systemPrompt.ifBlank { null },
            disable_thinking = s.disableThinking,
        )
    }

    private suspend fun ensureRagPipeline(embeddingModel: RAModelInfo, answerModel: RAModelInfo) {
        val key = embeddingModel.id to answerModel.id
        if (ragPipelineKey == key) return
        if (ragPipelineKey != null) runCatching { RunAnywhere.ragDestroyPipeline() }
        RunAnywhere.ragCreatePipeline(embeddingModel = embeddingModel, llmModel = answerModel)
        ragPipelineKey = key
    }

    private suspend fun generateReply(prompt: String, index: Int) {
        val result = RunAnywhere.generate(prompt, generationOptions())
        if (!result.error_message.isNullOrBlank()) {
            messages[index] = messages[index].copy(text = "Error: ${result.error_message}")
            return
        }
        val sdkMetrics = activeGenerationMetrics
        val totalMs = result.generation_time_ms.toLong()
        val tps = result.tokens_per_second.takeIf { it > 0 }
            ?: if (totalMs > 0 && result.tokens_generated > 0) result.tokens_generated * 1000.0 / totalMs else 0.0
        messages[index] = messages[index].copy(
            text = result.text,
            thinking = result.thinking_content?.takeIf { it.isNotBlank() },
            // Mirrors iOS buildMessageAnalytics: prefer the result's TTFT and
            // fall back to the value recorded from the SDK's first-token event;
            // framework falls back to the loaded model's analytics key.
            stats = GenerationStats(
                tokens = result.tokens_generated,
                tokensPerSecond = tps,
                timeToFirstTokenMs = result.ttft_ms?.toLong()?.takeIf { it > 0 } ?: activeGenerationTTFTMs,
                totalTimeMs = totalMs,
                inputTokens = result.input_tokens.takeIf { it > 0 } ?: sdkMetrics?.inputTokens ?: 0,
                modelName = GlobalState.model.loaded?.name,
                framework = result.framework?.takeIf { it.isNotBlank() }
                    ?: GlobalState.model.loaded?.framework?.analyticsKey,
                mode = GenerationMode.NON_STREAMING,
            ),
        )
    }

    private suspend fun streamReply(prompt: String, index: Int) {
        val options = generationOptions()
        val events = RunAnywhere.generateStream(prompt, options)
        val result =
            RunAnywhere.aggregateStream(prompt, events) { accumulated ->
                messages[index] = messages[index].copy(text = accumulated)
            }

        if (!result.error_message.isNullOrBlank()) {
            messages[index] = messages[index].copy(text = "Error: ${result.error_message}", thinking = null)
            return
        }

        val sdkMetrics = activeGenerationMetrics
        val totalMs = result.generation_time_ms.toLong()
        val tokens = result.tokens_generated.takeIf { it > 0 } ?: sdkMetrics?.outputTokens ?: 0
        val tps = result.tokens_per_second.takeIf { it > 0 }
            ?: sdkMetrics?.tokensPerSecond?.takeIf { it > 0 }
            ?: if (totalMs > 0 && tokens > 0) tokens * 1000.0 / totalMs else 0.0
        messages[index] = messages[index].copy(
            text = result.text,
            thinking = result.thinking_content?.takeIf { it.isNotBlank() },
            stats = GenerationStats(
                tokens = tokens,
                tokensPerSecond = tps,
                timeToFirstTokenMs = result.ttft_ms?.toLong()?.takeIf { it > 0 }
                    ?: activeGenerationTTFTMs
                    ?: sdkMetrics?.timeToFirstTokenMs,
                totalTimeMs = totalMs,
                inputTokens = result.input_tokens.takeIf { it > 0 } ?: sdkMetrics?.inputTokens ?: 0,
                modelName = GlobalState.model.loaded?.name,
                framework = result.framework?.takeIf { it.isNotBlank() }
                    ?: GlobalState.model.loaded?.framework?.analyticsKey,
                mode = GenerationMode.STREAMING,
            ),
        )
    }

    private suspend fun generateWithTools(prompt: String, index: Int) {
        val result = RunAnywhere.generateWithTools(
            prompt = prompt,
            options = generationOptions(),
            toolOptions = RAToolCallingOptions(
                max_iterations = 3,
                auto_execute = true,
            ),
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
        viewModelScope.launch {
            runCatching { RunAnywhere.cancelGeneration() }
            runCatching { RunAnywhere.cancelVLMGeneration() }
        }
        isGenerating = false
    }

    fun clearChat() {
        job?.cancel()
        messages.clear()
        input = ""
        isGenerating = false
        conversationId = null
        createdAt = 0L
        conversationModelName = null
    }

    fun loadConversation(id: String) {
        viewModelScope.launch {
            val stored = ConversationRepository.get(id) ?: return@launch
            job?.cancel()
            isGenerating = false
            input = ""
            conversationId = stored.id
            createdAt = stored.createdAt
            conversationModelName = stored.modelName
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
        // Fallback title mirrors iOS ConversationStore.generateTitle (first
        // line of the first user message, 50 chars).
        val derivedTitle = messages.firstOrNull { it.isUser }?.text
            ?.let(ConversationRepository::fallbackTitle)?.ifBlank { null }
            ?: ConversationRepository.DEFAULT_TITLE
        val storedMessages = messages.map { it.toStored() }
        // Mirrors iOS finalizeGeneration: record the active model on the
        // conversation after each exchange.
        val activeModelName = GlobalState.model.loaded?.name
        val shouldGenerateSmartTitle = messages.size >= 2 && GlobalState.model.isLoaded
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
                    modelName = activeModelName ?: existing?.modelName,
                ),
            )
            // Mirrors iOS ConversationStore.addMessage: try a smart title after
            // an assistant reply lands (skipped while another generation runs).
            if (shouldGenerateSmartTitle && !isGenerating) {
                ConversationRepository.generateSmartTitleIfNeeded(id)
            }
        }
        conversationModelName = activeModelName ?: conversationModelName
    }

    private companion object {
        const val MAX_TRACKED_GENERATIONS = 10
    }
}

// Completion metrics decoded from the SDK event bus (iOS GenerationMetricsFromSDK).
private data class SdkGenerationMetrics(
    val inputTokens: Int,
    val outputTokens: Int,
    val durationMs: Long,
    val tokensPerSecond: Double,
    val timeToFirstTokenMs: Long?,
)

private fun ChatMessage.toStored() = StoredMessage(
    text = text,
    isUser = isUser,
    thinking = thinking,
    attachment = attachment?.let {
        StoredAttachment(
            kind = when (it.kind) {
                ChatAttachmentKind.IMAGE -> StoredAttachmentKind.IMAGE
                ChatAttachmentKind.DOCUMENT -> StoredAttachmentKind.DOCUMENT
            },
            name = it.name,
            detail = it.detail,
        )
    },
    sources = sources.map { StoredSource(it.text, it.score, it.document) },
    tool = tool?.let { StoredTool(it.name, it.arguments, it.result, it.success, it.error) },
    stats = stats?.let {
        StoredStats(
            tokens = it.tokens,
            tokensPerSecond = it.tokensPerSecond,
            timeToFirstTokenMs = it.timeToFirstTokenMs,
            totalTimeMs = it.totalTimeMs,
            inputTokens = it.inputTokens,
            modelName = it.modelName,
            framework = it.framework,
            mode = it.mode,
        )
    },
)

private fun StoredMessage.toUi() = ChatMessage(
    text = text,
    isUser = isUser,
    thinking = thinking,
    attachment = attachment?.let {
        ChatAttachment(
            kind = when (it.kind) {
                StoredAttachmentKind.IMAGE -> ChatAttachmentKind.IMAGE
                StoredAttachmentKind.DOCUMENT -> ChatAttachmentKind.DOCUMENT
            },
            name = it.name,
            detail = it.detail,
        )
    },
    sources = sources.map { ChatSource(it.text, it.score, it.document) },
    tool = tool?.let { ToolCallInfo(it.name, it.arguments, it.result, it.success, it.error) },
    stats = stats?.let {
        GenerationStats(
            tokens = it.tokens,
            tokensPerSecond = it.tokensPerSecond,
            timeToFirstTokenMs = it.timeToFirstTokenMs,
            totalTimeMs = it.totalTimeMs,
            inputTokens = it.inputTokens,
            modelName = it.modelName,
            framework = it.framework,
            mode = it.mode,
        )
    },
)

private fun ChatViewModel.displayName(uri: Uri): String? =
    getApplication<Application>().contentResolver
        .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (cursor.moveToFirst() && index >= 0) cursor.getString(index)?.takeIf { it.isNotBlank() } else null
        }

private fun ChatViewModel.copyUriToCache(uri: Uri, prefix: String, suffix: String): File {
    val app = getApplication<Application>()
    val file = File.createTempFile(prefix, suffix, app.cacheDir)
    val input = app.contentResolver.openInputStream(uri) ?: error("Could not open the selected file.")
    input.use { source ->
        FileOutputStream(file).use { destination -> source.copyTo(destination) }
    }
    return file
}

private fun ChatViewModel.imageCacheSuffix(uri: Uri): String {
    val app = getApplication<Application>()
    val extension = app.contentResolver.getType(uri)
        ?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
        ?.lowercase()
        ?.takeIf { it in setOf("jpg", "jpeg", "png", "webp", "gif", "heic", "heif") }
    return ".${extension ?: "jpg"}"
}

private fun prettyJson(raw: String): String = runCatching {
    val trimmed = raw.trim()
    when {
        trimmed.isEmpty() -> raw
        trimmed.startsWith("[") -> org.json.JSONArray(trimmed).toString(2)
        else -> org.json.JSONObject(trimmed).toString(2)
    }
}.getOrDefault(raw)
