package com.runanywhere.runanywhereai.presentation.chat

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.GenerationEvent
import ai.runanywhere.proto.v1.GenerationEventKind
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ToolCallingOptions
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.runanywhereai.data.ConversationStore
import com.runanywhere.runanywhereai.domain.models.ChatMessage
import com.runanywhere.runanywhereai.domain.models.CompletionStatus
import com.runanywhere.runanywhereai.domain.models.Conversation
import com.runanywhere.runanywhereai.domain.models.MessageAnalytics
import com.runanywhere.runanywhereai.domain.models.MessageModelInfo
import com.runanywhere.runanywhereai.domain.models.MessageRole
import com.runanywhere.runanywhereai.domain.models.ToolCallInfo
import com.runanywhere.runanywhereai.presentation.settings.ToolSettingsViewModel
import com.runanywhere.runanywhereai.util.ThinkingContentParser
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.generateWithTools
import com.runanywhere.sdk.public.extensions.getRegisteredTools
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.lora
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import kotlin.math.ceil

/**
 * Enhanced ChatUiState  functionality
 */
data class ChatUiState(
    val messages: List<ChatMessage> = emptyList(),
    val isGenerating: Boolean = false,
    val isModelLoaded: Boolean = false,
    val loadedModelName: String? = null,
    val currentInput: String = "",
    val error: Throwable? = null,
    val useStreaming: Boolean = true,
    val currentConversation: Conversation? = null,
    val currentModelSupportsLora: Boolean = false,
    val hasActiveLoraAdapter: Boolean = false,
) {
    val canSend: Boolean
        get() = currentInput.trim().isNotEmpty() && !isGenerating && isModelLoaded
}

/**
 * Enhanced ChatViewModel  ChatViewModel functionality
 * Includes streaming, thinking mode, analytics, and conversation management
 *
 * Architecture:
 * - Uses RunAnywhere SDK extension functions directly
 * - Model lifecycle via EventBus with LLMEvent filtering
 * - Generation via RunAnywhere.generate() and RunAnywhere.generateStream()
 */
class ChatViewModel(
    application: Application,
) : AndroidViewModel(application) {
    private val app = application as RunAnywhereApplication
    private val conversationStore = ConversationStore.getInstance(application)
    private val tokensPerSecondHistory = java.util.concurrent.CopyOnWriteArrayList<Double>()

    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    private var generationJob: Job? = null

    private val generationPrefs by lazy {
        getApplication<Application>().getSharedPreferences("generation_settings", android.content.Context.MODE_PRIVATE)
    }

    init {
        // Always start with a new conversation for a fresh chat experience
        val conversation = conversationStore.createConversation()
        _uiState.value = _uiState.value.copy(currentConversation = conversation)

        // Subscribe to LLM events from SDK EventBus
        viewModelScope.launch {
            EventBus.events
                .mapNotNull { it.generation }
                .collect { event ->
                    handleLLMEvent(event)
                }
        }

        // Initialize with system message if model is already loaded
        viewModelScope.launch {
            checkModelStatus()
        }
    }

    /**
     * Handle LLM events from SDK EventBus
     * Uses the new data class with enum event types pattern
     */
    private fun handleLLMEvent(event: GenerationEvent) {
        when (event.kind) {
            GenerationEventKind.GENERATION_EVENT_KIND_STARTED -> {
                Timber.d("LLM generation started: ${event.model_id}")
            }
            GenerationEventKind.GENERATION_EVENT_KIND_COMPLETED -> {
                Timber.i("✅ Generation completed: ${event.tokens_used} tokens")
                // Force-clear isGenerating in case generateAndCollect's
                // Flow never received is_final=true. Also sync the conversation store.
                if (_uiState.value.isGenerating) {
                    _uiState.value = _uiState.value.copy(isGenerating = false)
                    syncCurrentConversationToStore()
                }
            }
            GenerationEventKind.GENERATION_EVENT_KIND_FAILED -> {
                Timber.e("Generation failed: ${event.error}")
                _uiState.value =
                    _uiState.value.copy(
                        isGenerating = false,
                        error = Exception(event.error.ifBlank { "Generation failed" }),
                    )
            }
            GenerationEventKind.GENERATION_EVENT_KIND_TOKEN_GENERATED -> {
                // Token received during streaming - handled by flow collection
            }
            GenerationEventKind.GENERATION_EVENT_KIND_STREAM_COMPLETED -> {
                Timber.d("Stream completed")
                // Fallback: if the Flow collector never sees is_final=true the UI stays
                // stuck in isGenerating=true. STREAM_COMPLETED is the definitive signal
                // from native that the stream is closed — always clear the generating flag.
                if (_uiState.value.isGenerating) {
                    _uiState.value = _uiState.value.copy(isGenerating = false)
                    syncCurrentConversationToStore()
                }
            }
            else -> Unit
        }
    }

    /**
     * Send message with streaming support and analytics
     *  sendMessage functionality
     */
    fun sendMessage() {
        val currentState = _uiState.value

        Timber.i("🎯 sendMessage() called")
        Timber.i("📝 canSend: ${currentState.canSend}, isModelLoaded: ${currentState.isModelLoaded}, loadedModelName: ${currentState.loadedModelName}")

        if (!currentState.canSend) {
            Timber.w("Cannot send message - canSend is false")
            return
        }

        Timber.i("✅ canSend is true, proceeding")

        val prompt = currentState.currentInput
        Timber.i("🎯 Sending message: ${prompt.take(50)}...")

        // Clear input and set generating state
        _uiState.value =
            currentState.copy(
                currentInput = "",
                isGenerating = true,
                error = null,
            )

        // Add user message
        val userMessage = ChatMessage.user(prompt)

        _uiState.value =
            _uiState.value.copy(
                messages = _uiState.value.messages + userMessage,
            )

        // Save user message to conversation (store sets title from first user input)
        // Refresh currentConversation from store so title appears in history immediately
        _uiState.value.currentConversation?.let { conversation ->
            conversationStore.addMessage(userMessage, conversation)
            conversationStore.loadConversation(conversation.id)?.let { updated ->
                _uiState.value = _uiState.value.copy(currentConversation = updated)
            }
        }

        // Create assistant message that will be updated with streaming tokens
        val currentModelInfo = createCurrentModelInfo()
        val assistantMessage =
            ChatMessage.assistant(
                content = "",
                modelInfo = currentModelInfo,
            )

        _uiState.value =
            _uiState.value.copy(
                messages = _uiState.value.messages + assistantMessage,
            )

        // Start generation
        generationJob =
            viewModelScope.launch {
                try {
                    // Clear metrics from previous generation
                    tokensPerSecondHistory.clear()

                    // Check if tool calling is enabled and tools are registered
                    val toolViewModel = ToolSettingsViewModel.getInstance(app)
                    val useToolCalling = toolViewModel.toolCallingEnabled
                    val registeredTools = RunAnywhere.getRegisteredTools()

                    if (useToolCalling && registeredTools.isNotEmpty()) {
                        Timber.i("🔧 Using tool calling with ${registeredTools.size} tools")
                        generateWithToolCalling(prompt, assistantMessage.id)
                    } else if (currentState.useStreaming) {
                        generateWithStreaming(prompt, assistantMessage.id)
                    } else {
                        generateWithoutStreaming(prompt, assistantMessage.id)
                    }
                } catch (e: Exception) {
                    handleGenerationError(e, assistantMessage.id)
                }
            }
    }

    /**
     * Generate with tool calling support.
     *
     * Mirrors iOS `LLMViewModel+ToolCalling.generateWithToolCalling`:
     *  1. Detect format hint per loaded model name.
     *  2. Call `RunAnywhere.generateWithTools(...)`.
     *  3. Split `<think>...</think>` from the response so the thinking section
     *     renders independently of the final text (iOS uses
     *     ThinkingContentParser.extract).
     *  4. Populate `toolCallInfo` from the first executed tool call so the
     *     assistant bubble shows a "Tool" indicator the user can tap to see
     *     arguments + return value (matches iOS ToolCallIndicator /
     *     ToolCallDetailSheet).
     *  5. Surface SDK-level errors (`result.error_message`) as the message
     *     content so the chain never dies silently.
     */
    private suspend fun generateWithToolCalling(
        prompt: String,
        messageId: String,
    ) {
        val startTime = System.currentTimeMillis()

        try {
            // Detect the appropriate tool call format based on loaded model
            // Note: loadedModelName can be null if model state changes during generation
            val modelName = _uiState.value.loadedModelName
            if (modelName == null) {
                Timber.w("⚠️ Tool calling initiated but model name is null, using default format")
            }
            val toolViewModel = ToolSettingsViewModel.getInstance(app)
            val format = toolViewModel.detectToolCallFormat(modelName)

            Timber.i("🔧 Tool calling with format: $format for model: ${modelName ?: "unknown"}")

            // Create tool calling options
            val toolOptions =
                ToolCallingOptions(
                    max_iterations = 3,
                    auto_execute = true,
                    temperature = 0.7f,
                    max_tokens = 1024,
                    format_hint = format,
                )

            // Generate with tools
            val result =
                RunAnywhere.generateWithTools(
                    prompt = prompt,
                    options = RALLMGenerationOptions(tool_calling = toolOptions),
                    toolOptions = null,
                    toolChoice = null,
                    forcedToolName = null,
                )
            val endTime = System.currentTimeMillis()

            // Log tool calls + populate ToolCallInfo FIRST, so the indicator
            // shows even if the final text is empty (e.g. when the model
            // calls a tool but produces no follow-up text). Matches iOS
            // MessageBubbleView's `if hasToolCall { toolCallSection }` block.
            var toolCallInfo: ToolCallInfo? = null
            if (result.tool_calls.isNotEmpty()) {
                Timber.i("🔧 Tool calls made: ${result.tool_calls.map { it.name }}")
                result.tool_results.forEach { toolResult ->
                    Timber.i(
                        "📋 Tool result: ${toolResult.name} - success: ${toolResult.error.isNullOrBlank()}",
                    )
                }

                val firstToolCall = result.tool_calls.first()
                val firstToolResult =
                    result.tool_results.firstOrNull { it.name == firstToolCall.name }

                toolCallInfo =
                    ToolCallInfo(
                        toolName = firstToolCall.name,
                        arguments = prettyJson(firstToolCall.arguments_json),
                        result = firstToolResult?.result_json?.let { prettyJson(it) },
                        success = firstToolResult != null && firstToolResult.error.isNullOrBlank(),
                        error = firstToolResult?.error,
                    )

                updateAssistantMessageWithToolCallInfo(messageId, toolCallInfo)
            }

            // Extract `<think>...</think>` from the final text. iOS does this via
            // ThinkingContentParser so the thinking block renders separately and
            // the SDK-supplied thinking content is not silently dropped on the
            // tool-calling path.
            val (displayText, thinkingContent) = extractThinking(result.text)

            // Choose the user-visible content: prefer the model's final text,
            // fall back to an SDK error message, then to a synthesized
            // tool-summary so the bubble is never empty when tools ran.
            val errorMessage = result.error_message
            val content =
                when {
                    displayText.isNotBlank() -> displayText
                    !errorMessage.isNullOrBlank() -> "⚠️ Tool calling failed: $errorMessage"
                    toolCallInfo != null -> synthesizeToolSummary(toolCallInfo)
                    else -> "(no response)"
                }
            updateAssistantMessage(messageId, content, thinkingContent)

            // Create analytics
            val analytics =
                createMessageAnalytics(
                    startTime = startTime,
                    endTime = endTime,
                    firstTokenTime = null,
                    thinkingStartTime = null,
                    thinkingEndTime = null,
                    inputText = prompt,
                    outputText = content,
                    thinkingText = thinkingContent,
                    wasInterrupted = false,
                )

            updateAssistantMessageWithAnalytics(messageId, analytics)
            syncCurrentConversationToStore()
        } catch (e: Exception) {
            Timber.e(e, "Tool calling failed")
            throw e
        } finally {
            _uiState.value = _uiState.value.copy(isGenerating = false)
        }
    }

    /**
     * Split `<think>...</think>` from a model response via the shared
     * example-app `ThinkingContentParser` (mirrors iOS). Returns the
     * user-facing display text and the captured thinking content (null
     * when there's no complete `<think>` block).
     */
    private fun extractThinking(rawText: String): Pair<String, String?> {
        val extracted = ThinkingContentParser.extract(rawText)
        return extracted.text to extracted.thinking
    }

    /**
     * Pretty-print a JSON string so the tool-detail sheet shows readable
     * arguments / results, matching iOS `RAToolValue.toJSONString(pretty: true)`.
     * Falls back to the raw string when parsing fails so we never throw on
     * a non-JSON payload.
     */
    private fun prettyJson(raw: String): String {
        if (raw.isBlank()) return raw
        return runCatching {
            val element = PRETTY_JSON.parseToJsonElement(raw)
            PRETTY_JSON.encodeToString(
                kotlinx.serialization.json.JsonElement
                    .serializer(),
                element,
            )
        }.getOrDefault(raw)
    }

    /**
     * When the model produces no follow-up text after running a tool, render
     * a one-line natural-language summary so the chat doesn't appear stuck.
     * The user can still tap the tool indicator for the full arguments +
     * return value.
     */
    private fun synthesizeToolSummary(info: ToolCallInfo): String {
        if (!info.success) {
            return "Tool `${info.toolName}` failed${info.error?.let { ": $it" } ?: ""}."
        }
        return "Ran `${info.toolName}` — tap the tool indicator above to see the result."
    }

    /**
     * Generate with streaming support and thinking mode
     *  streaming generation pattern
     */
    private suspend fun generateWithStreaming(
        prompt: String,
        messageId: String,
    ) {
        val startTime = System.currentTimeMillis()
        var firstTokenTime: Long? = null
        var thinkingStartTime: Long? = null
        var thinkingEndTime: Long? = null

        var fullResponse = ""
        var isInThinkingMode = false
        var thinkingContent = ""
        var responseContent = ""
        var totalTokensReceived = 0
        var wasInterrupted = false

        Timber.i("📤 Starting streaming generation")

        try {
            // generateStream now returns
            // Flow<LLMStreamEvent>; collect token text off each event.
            // Use transformWhile so the flow terminates as soon as is_final=true
            // arrives — plain return@collect does NOT close the upstream flow,
            // leaving the collector suspended indefinitely.
            var streamError: String? = null
            RunAnywhere
                .generateStream(prompt, getGenerationOptions())
                .transformWhile { event ->
                    if (event.is_final) {
                        if (event.error_message.isNotEmpty()) streamError = event.error_message
                        false // stop the flow
                    } else {
                        emit(event)
                        true // keep going
                    }
                }.collect { event ->
                    val token = event.token
                    if (token.isEmpty()) return@collect
                    fullResponse += token
                    totalTokensReceived++

                    // Track first token time
                    if (firstTokenTime == null) {
                        firstTokenTime = System.currentTimeMillis()
                    }

                    // Calculate real-time tokens per second
                    if (totalTokensReceived % 10 == 0) {
                        val elapsed = System.currentTimeMillis() - (firstTokenTime ?: startTime)
                        if (elapsed > 0) {
                            val currentSpeed = totalTokensReceived.toDouble() / (elapsed / 1000.0)
                            tokensPerSecondHistory.add(currentSpeed)
                        }
                    }

                    // Track transitions into / out of a thinking block for
                    // analytics. Tag-scanning + splitting is owned by the
                    // shared example-app `ThinkingContentParser` (mirrors
                    // iOS) so this ViewModel only does flow-control via the
                    // parser's exported tag constants.
                    val hasOpen = fullResponse.contains(ThinkingContentParser.OPEN_TAG)
                    val hasClose = fullResponse.contains(ThinkingContentParser.CLOSE_TAG)

                    if (hasOpen && !isInThinkingMode && thinkingStartTime == null) {
                        isInThinkingMode = true
                        thinkingStartTime = System.currentTimeMillis()
                        Timber.i("🧠 Entering thinking mode")
                    }
                    if (isInThinkingMode && hasClose) {
                        isInThinkingMode = false
                        thinkingEndTime = System.currentTimeMillis()
                        Timber.i("🧠 Exiting thinking mode")
                    }

                    if (isInThinkingMode) {
                        // Partial buffer — capture the in-progress thinking
                        // tail (no closing tag yet). `ThinkingContentParser
                        // .extract` only returns content for closed blocks,
                        // so we slice the unterminated open tag here.
                        val openIdx = fullResponse.indexOf(ThinkingContentParser.OPEN_TAG)
                        if (openIdx >= 0) {
                            thinkingContent =
                                fullResponse.substring(openIdx + ThinkingContentParser.OPEN_TAG.length)
                        }
                        responseContent = ""
                    } else {
                        val extracted = ThinkingContentParser.extract(fullResponse)
                        responseContent = extracted.text
                        extracted.thinking?.let { thinkingContent = it }
                    }

                    // Update the assistant message
                    updateAssistantMessage(
                        messageId = messageId,
                        content = if (isInThinkingMode) "" else responseContent,
                        thinkingContent = if (thinkingContent.isEmpty()) null else thinkingContent.trim(),
                    )
                }
            if (streamError != null) throw RuntimeException(streamError)
        } catch (e: kotlinx.coroutines.CancellationException) {
            Timber.i("Streaming cancelled by user")
            wasInterrupted = true
        } catch (e: Exception) {
            Timber.e(e, "Streaming failed")
            wasInterrupted = true
            throw e
        }

        val endTime = System.currentTimeMillis()

        // Handle edge case: stream ended while still inside an unterminated
        // `<think>` block. Delegate to the shared parser to drop the
        // unclosed open tag, then carve out the captured thinking tail.
        if (isInThinkingMode) {
            Timber.w("⚠️ Stream ended while in thinking mode")
            wasInterrupted = true

            if (thinkingContent.isNotEmpty()) {
                val stripped = ThinkingContentParser.strip(fullResponse)
                val remainingContent = stripped.replace(thinkingContent, "").trim()

                val intelligentResponse =
                    if (remainingContent.isEmpty()) {
                        generateThinkingSummaryResponse(thinkingContent)
                    } else {
                        remainingContent
                    }

                updateAssistantMessage(
                    messageId = messageId,
                    content = intelligentResponse,
                    thinkingContent = thinkingContent.trim(),
                )
            }
        }

        // Create analytics
        val analytics =
            createMessageAnalytics(
                startTime = startTime,
                endTime = endTime,
                firstTokenTime = firstTokenTime,
                thinkingStartTime = thinkingStartTime,
                thinkingEndTime = thinkingEndTime,
                inputText = prompt,
                outputText = responseContent,
                thinkingText = thinkingContent.takeIf { it.isNotEmpty() },
                wasInterrupted = wasInterrupted,
            )

        // Update message with analytics
        updateAssistantMessageWithAnalytics(messageId, analytics)

        syncCurrentConversationToStore()
        _uiState.value = _uiState.value.copy(isGenerating = false)
        Timber.i("✅ Streaming generation completed")
    }

    /**
     * Generate without streaming
     */
    private suspend fun generateWithoutStreaming(
        prompt: String,
        messageId: String,
    ) {
        val startTime = System.currentTimeMillis()

        try {
            // RunAnywhere.generate() returns LLMGenerationResult
            val result = RunAnywhere.generate(prompt, getGenerationOptions())
            val response = result.text
            val endTime = System.currentTimeMillis()

            updateAssistantMessage(messageId, response, null)

            val analytics =
                createMessageAnalytics(
                    startTime = startTime,
                    endTime = endTime,
                    firstTokenTime = null,
                    thinkingStartTime = null,
                    thinkingEndTime = null,
                    inputText = prompt,
                    outputText = response,
                    thinkingText = null,
                    wasInterrupted = false,
                )

            updateAssistantMessageWithAnalytics(messageId, analytics)
            syncCurrentConversationToStore()
        } catch (e: Exception) {
            throw e
        } finally {
            _uiState.value = _uiState.value.copy(isGenerating = false)
        }
    }

    /**
     * Handle generation errors
     */
    private fun handleGenerationError(
        error: Exception,
        messageId: String,
    ) {
        // Don't show error for user-initiated cancellation
        if (error is kotlinx.coroutines.CancellationException) {
            Timber.i("Generation cancelled by user")
            _uiState.value = _uiState.value.copy(isGenerating = false)
            syncCurrentConversationToStore()
            return
        }

        Timber.e(error, "❌ Generation failed")

        val errorMessage =
            when {
                !_uiState.value.isModelLoaded -> "❌ No model is loaded. Please select and load a model first."
                else -> "❌ Generation failed: ${error.message}"
            }

        updateAssistantMessage(messageId, errorMessage, null)
        syncCurrentConversationToStore()

        _uiState.value =
            _uiState.value.copy(
                isGenerating = false,
                error = error,
            )
    }

    /**
     * Update assistant message content
     */
    private fun updateAssistantMessage(
        messageId: String,
        content: String,
        thinkingContent: String?,
    ) {
        val currentMessages = _uiState.value.messages
        val updatedMessages =
            currentMessages.map { message ->
                if (message.id == messageId) {
                    message.copy(
                        content = content,
                        thinkingContent = thinkingContent,
                    )
                } else {
                    message
                }
            }

        _uiState.value = _uiState.value.copy(messages = updatedMessages)
    }

    /**
     * Update assistant message with analytics
     */
    private fun updateAssistantMessageWithAnalytics(
        messageId: String,
        analytics: MessageAnalytics,
    ) {
        val currentMessages = _uiState.value.messages
        val updatedMessages =
            currentMessages.map { message ->
                if (message.id == messageId) {
                    message.copy(analytics = analytics)
                } else {
                    message
                }
            }

        _uiState.value = _uiState.value.copy(messages = updatedMessages)
    }

    private fun updateAssistantMessageWithToolCallInfo(
        messageId: String,
        toolCallInfo: ToolCallInfo,
    ) {
        val currentMessages = _uiState.value.messages
        val updatedMessages =
            currentMessages.map { message ->
                if (message.id == messageId) {
                    message.copy(toolCallInfo = toolCallInfo)
                } else {
                    message
                }
            }

        _uiState.value = _uiState.value.copy(messages = updatedMessages)
    }

    /**
     * Persist current conversation messages to the store so that loading the conversation
     * later shows both user and assistant messages.
     */
    private fun syncCurrentConversationToStore() {
        val conv = _uiState.value.currentConversation ?: return
        val messages = _uiState.value.messages
        val updated = conv.copy(messages = messages)
        conversationStore.updateConversation(updated)
        _uiState.value = _uiState.value.copy(currentConversation = updated)
    }

    /**
     * Create message analytics using app-local types
     */
    @Suppress("UnusedParameter")
    private fun createMessageAnalytics(
        startTime: Long,
        endTime: Long,
        firstTokenTime: Long?,
        thinkingStartTime: Long?,
        thinkingEndTime: Long?,
        inputText: String,
        outputText: String,
        thinkingText: String?,
        wasInterrupted: Boolean,
    ): MessageAnalytics {
        val totalGenerationTime = endTime - startTime
        val timeToFirstToken = firstTokenTime?.let { it - startTime } ?: 0L

        // Estimate token counts (simple approximation)
        val inputTokens = estimateTokenCount(inputText)
        val outputTokens = estimateTokenCount(outputText)

        val averageTokensPerSecond =
            if (totalGenerationTime > 0) {
                outputTokens.toDouble() / (totalGenerationTime / 1000.0)
            } else {
                0.0
            }

        val completionStatus =
            if (wasInterrupted) {
                CompletionStatus.INTERRUPTED
            } else {
                CompletionStatus.COMPLETE
            }

        return MessageAnalytics(
            inputTokens = inputTokens,
            outputTokens = outputTokens,
            totalGenerationTime = totalGenerationTime,
            timeToFirstToken = timeToFirstToken,
            averageTokensPerSecond = averageTokensPerSecond,
            wasThinkingMode = thinkingText != null,
            completionStatus = completionStatus,
        )
    }

    /**
     * Simple token estimation (approximately 4 characters per token)
     */
    private fun estimateTokenCount(text: String): Int = ceil(text.length / 4.0).toInt()

    /**
     * Create MessageModelInfo for the current loaded model
     */
    private fun createCurrentModelInfo(): MessageModelInfo? {
        val modelName = _uiState.value.loadedModelName ?: return null
        // currentLLMModelId removed. Reuse loadedModelName as
        // the modelId fallback; the proper resolved id is captured in
        // [refreshLoraState] / [checkModelStatus] via currentLLMModel().
        return MessageModelInfo(
            modelId = modelName,
            modelName = modelName,
            framework = "LLAMA_CPP",
        )
    }

    /**
     * Generate intelligent response from thinking content
     */
    private fun generateThinkingSummaryResponse(thinkingContent: String): String {
        val thinking = thinkingContent.trim()

        return when {
            thinking.lowercase().contains("user") && thinking.lowercase().contains("help") ->
                "I'm here to help! Let me know what you need."

            thinking.lowercase().contains("question") || thinking.lowercase().contains("ask") ->
                "That's a good question. Let me think about this more."

            thinking.lowercase().contains("consider") || thinking.lowercase().contains("think") ->
                "Let me consider this carefully. How can I help you further?"

            thinking.length > 200 ->
                "I was thinking through this carefully. Could you help me understand what you're looking for?"

            else ->
                "I'm processing your message. What would be most helpful for you?"
        }
    }

    /**
     * Update current input text
     */
    fun updateInput(input: String) {
        _uiState.value = _uiState.value.copy(currentInput = input)
    }

    /**
     * Clear chat messages
     */
    fun clearChat() {
        generationJob?.cancel()

        _uiState.value =
            _uiState.value.copy(
                messages = emptyList(),
                currentInput = "",
                isGenerating = false,
                error = null,
            )

        // Create new conversation
        val conversation = conversationStore.createConversation()
        _uiState.value = _uiState.value.copy(currentConversation = conversation)
    }

    /**
     * Stop current generation
     */
    fun stopGeneration() {
        generationJob?.cancel()
        RunAnywhere.cancelGeneration()
        _uiState.value = _uiState.value.copy(isGenerating = false)
    }

    /**
     * Set the loaded model display name (e.g. when user selects a model from the sheet).
     * Ensures the app bar shows the correct model icon immediately.
     */
    fun setLoadedModelName(modelName: String) {
        _uiState.value = _uiState.value.copy(loadedModelName = modelName)
    }

    /**
     * Check model status and best-effort auto-load a chat model.
     *
     * IMPORTANT: This runs on cold start before the user has expressed
     * intent. Failures (e.g. native library missing on a non-Snapdragon
     * device, error -423 from llama.cpp on Pixel) MUST NOT surface a
     * Debug Info dialog — they are expected on devices that simply
     * don't have a model downloaded yet. We only log and leave UI in
     * the "select a model" state. The dialog is reserved for explicit
     * user-initiated load failures elsewhere.
     */
    suspend fun checkModelStatus() {
        try {
            if (app.isSDKReady()) {
                // Check if LLM is already loaded via SDK
                val currentLLM =
                    RunAnywhere.currentModel(
                        CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_LANGUAGE),
                    )
                if (currentLLM.found && currentLLM.model_id.isNotEmpty()) {
                    val loadedModel = currentLLM.model
                    val displayName = loadedModel?.name ?: currentLLM.model_id
                    Timber.i("✅ LLM model already loaded: $displayName")
                    _uiState.value =
                        _uiState.value.copy(
                            isModelLoaded = true,
                            loadedModelName = displayName,
                            currentModelSupportsLora = loadedModel?.supports_lora == true,
                        )
                    refreshLoraState()
                    addSystemMessageIfNeeded()
                    return
                }

                // Use SDK's model listing API to find chat models
                // Prefer Genie (NPU) models over CPU models for testing
                val allModels =
                    RunAnywhere
                        .listModels(ModelListRequest())
                        .models
                        ?.models
                        .orEmpty()
                val chatModel =
                    allModels.firstOrNull { model ->
                        model.category == ModelCategory.MODEL_CATEGORY_LANGUAGE &&
                            model.isDownloadedOnDisk &&
                            model.framework == InferenceFramework.INFERENCE_FRAMEWORK_GENIE
                    } ?: allModels.firstOrNull { model ->
                        model.category == ModelCategory.MODEL_CATEGORY_LANGUAGE && model.isDownloadedOnDisk
                    }

                if (chatModel != null) {
                    Timber.i("📦 Found downloaded chat model: ${chatModel.name}, loading...")

                    try {
                        val loadResult =
                            RunAnywhere.loadModel(
                                RAModelLoadRequest(
                                    model_id = chatModel.id,
                                    category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                                ),
                            )
                        if (!loadResult.success) {
                            throw IllegalStateException(
                                loadResult.error_message.ifBlank { "Failed to load LLM model '${chatModel.id}'" },
                            )
                        }

                        _uiState.value =
                            _uiState.value.copy(
                                isModelLoaded = true,
                                loadedModelName = chatModel.name,
                                currentModelSupportsLora = chatModel.supports_lora,
                            )
                        refreshLoraState()
                        Timber.i("✅ Chat model loaded successfully: ${chatModel.name}")
                    } catch (e: Throwable) {
                        // Cold-start best-effort load — DO NOT propagate to UI as
                        // an error dialog. Just log and let the user
                        // pick a model from the sheet.
                        Timber.w(e, "Cold-start auto-load skipped (${e.message})")
                        _uiState.value =
                            _uiState.value.copy(
                                isModelLoaded = false,
                                loadedModelName = null,
                            )
                    }
                } else {
                    _uiState.value =
                        _uiState.value.copy(
                            isModelLoaded = false,
                            loadedModelName = null,
                        )
                    Timber.i("ℹ️ No downloaded chat models found.")
                }

                addSystemMessageIfNeeded()
            } else {
                _uiState.value =
                    _uiState.value.copy(
                        isModelLoaded = false,
                        loadedModelName = null,
                    )
                Timber.i("❌ SDK not ready")
            }
        } catch (e: Throwable) {
            // Outer try also degrades silently on cold start.
            Timber.w(e, "checkModelStatus skipped: ${e.message}")
            _uiState.value =
                _uiState.value.copy(
                    isModelLoaded = false,
                    loadedModelName = null,
                )
        }
    }

    /** Refresh LoRA loaded state for the active adapters indicator. */
    private var loraRefreshJob: Job? = null

    fun refreshLoraState() {
        loraRefreshJob?.cancel()
        loraRefreshJob =
            viewModelScope.launch {
                try {
                    val state = withContext(Dispatchers.IO) { RunAnywhere.lora.list() }
                    _uiState.value =
                        _uiState.value.copy(
                            hasActiveLoraAdapter =
                                state.error_message.isNullOrBlank() &&
                                    state.loaded_adapters.isNotEmpty(),
                        )
                } catch (e: Exception) {
                    Timber.e(e, "Failed to refresh LoRA state")
                }
            }
    }

    /**
     * Helper to add system message if model is loaded and not already present.
     */
    private fun addSystemMessageIfNeeded() {
        // Update system message to reflect current state
        val currentMessages = _uiState.value.messages.toMutableList()
        if (currentMessages.firstOrNull()?.role == MessageRole.SYSTEM) {
            currentMessages.removeAt(0)
        }
        _uiState.value = _uiState.value.copy(messages = currentMessages)
    }

    /**
     * Load a conversation by ID from store (or disk) so we always have the latest messages,
     * then update UI state. Using the store ensures we don't rely on a possibly stale list item.
     */
    fun loadConversation(conversation: Conversation) {
        val loaded = conversationStore.loadConversation(conversation.id) ?: conversation
        conversationStore.ensureConversationInList(loaded)
        _uiState.value = _uiState.value.copy(currentConversation = loaded)

        if (loaded.messages.isEmpty()) {
            _uiState.value = _uiState.value.copy(messages = emptyList())
        } else {
            _uiState.value = _uiState.value.copy(messages = loaded.messages)
            val analyticsCount = loaded.messages.mapNotNull { it.analytics }.size
            Timber.i("📂 Loaded conversation with ${loaded.messages.size} messages, $analyticsCount have analytics")
        }

        loaded.modelName?.let { modelName ->
            _uiState.value = _uiState.value.copy(loadedModelName = modelName)
        }
    }

    /**
     * Create a new conversation
     */
    fun createNewConversation() {
        clearChat()
    }

    /**
     * Ensure the current chat is in the store's list and persisted before showing history.
     * Syncs latest messages to the store and adds the conversation to the list if absent.
     */
    fun ensureCurrentConversationInHistory() {
        syncCurrentConversationToStore()
        _uiState.value.currentConversation?.let { conversationStore.ensureConversationInList(it) }
    }

    /**
     * Clear error state
     */
    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }

    /**
     * Get generation options from SharedPreferences
     */
    private fun getGenerationOptions(): RALLMGenerationOptions {
        val temperature = generationPrefs.getFloat("defaultTemperature", 0.7f)
        val maxTokens = generationPrefs.getInt("defaultMaxTokens", 1000)
        val systemPromptValue = generationPrefs.getString("defaultSystemPrompt", "")
        val systemPrompt = if (systemPromptValue.isNullOrEmpty()) null else systemPromptValue
        val systemPromptInfo = systemPrompt?.let { "set(${it.length} chars)" } ?: "nil"

        Timber.i("[PARAMS] App getGenerationOptions: temperature=$temperature, maxTokens=$maxTokens, systemPrompt=$systemPromptInfo")

        return RALLMGenerationOptions(
            max_tokens = maxTokens,
            temperature = temperature,
            system_prompt = systemPrompt,
        )
    }

    private companion object {
        /**
         * Shared pretty-printer for tool-call arguments / results. iOS uses
         * `RAToolValue.toJSONString(pretty: true)`; we mirror the indented
         * shape so the tool-detail sheet renders the same payload format.
         */
        val PRETTY_JSON: kotlinx.serialization.json.Json =
            kotlinx.serialization.json.Json { prettyPrint = true }
    }
}
