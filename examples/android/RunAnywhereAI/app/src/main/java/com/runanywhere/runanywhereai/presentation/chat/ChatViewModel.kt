package com.runanywhere.runanywhereai.presentation.chat

import android.app.Application
import timber.log.Timber
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
import com.runanywhere.sdk.public.extensions.LLM.ToolValue
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.LLMEvent
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.availableModels
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.currentLLMModel
import com.runanywhere.sdk.public.extensions.currentLLMModelId
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.isLLMModelLoaded
import com.runanywhere.sdk.public.extensions.getLoadedLoraAdapters
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingOptions
import com.runanywhere.sdk.public.extensions.LLM.ToolCallFormat
import com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling
import com.runanywhere.runanywhereai.presentation.settings.ToolSettingsViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.launch
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
class ChatViewModel(application: Application) : AndroidViewModel(application) {
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
                .filterIsInstance<LLMEvent>()
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
    private fun handleLLMEvent(event: LLMEvent) {
        when (event.eventType) {
            LLMEvent.LLMEventType.GENERATION_STARTED -> {
                Timber.d("LLM generation started: ${event.modelId}")
            }
            LLMEvent.LLMEventType.GENERATION_COMPLETED -> {
                Timber.i("✅ Generation completed: ${event.tokensGenerated} tokens")
                _uiState.value = _uiState.value.copy(isGenerating = false)
            }
            LLMEvent.LLMEventType.GENERATION_FAILED -> {
                Timber.e("Generation failed: ${event.error}")
                _uiState.value =
                    _uiState.value.copy(
                        isGenerating = false,
                        error = Exception(event.error ?: "Generation failed"),
                    )
            }
            LLMEvent.LLMEventType.STREAM_TOKEN -> {
                // Token received during streaming - handled by flow collection
            }
            LLMEvent.LLMEventType.STREAM_COMPLETED -> {
                Timber.d("Stream completed")
            }
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
                    val registeredTools = RunAnywhereToolCalling.getRegisteredTools()

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
     * Generate with tool calling support
     * Matches iOS generateWithToolCalling pattern
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
            val toolOptions = ToolCallingOptions(
                maxToolCalls = 3,
                autoExecute = true,
                temperature = 0.7f,
                maxTokens = 1024,
                format = format
            )

            // Generate with tools
            val result = RunAnywhereToolCalling.generateWithTools(prompt, toolOptions)
            val endTime = System.currentTimeMillis()

            // Update the assistant message with the result
            val response = result.text
            updateAssistantMessage(messageId, response, null)

            // Log tool calls and create tool call info
            if (result.toolCalls.isNotEmpty()) {
                Timber.i("🔧 Tool calls made: ${result.toolCalls.map { it.toolName }}")
                result.toolResults.forEach { toolResult ->
                    Timber.i("📋 Tool result: ${toolResult.toolName} - success: ${toolResult.success}")
                }

                // Create ToolCallInfo from the first tool call and result
                val firstToolCall = result.toolCalls.first()
                val firstToolResult = result.toolResults.firstOrNull { it.toolName == firstToolCall.toolName }

                val toolCallInfo = ToolCallInfo(
                    toolName = firstToolCall.toolName,
                    arguments = formatToolValueMapToJson(firstToolCall.arguments),
                    result = firstToolResult?.result?.let { formatToolValueMapToJson(it) },
                    success = firstToolResult?.success ?: false,
                    error = firstToolResult?.error,
                )

                updateAssistantMessageWithToolCallInfo(messageId, toolCallInfo)
            }

            // Create analytics
            val analytics = createMessageAnalytics(
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

        } catch (e: Exception) {
            Timber.e(e, "Tool calling failed")
            throw e
        } finally {
            _uiState.value = _uiState.value.copy(isGenerating = false)
        }
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
            // Use SDK streaming generation - returns Flow<String>
            RunAnywhere.generateStream(prompt, getGenerationOptions()).collect { token ->
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

                // Handle thinking mode
                if (fullResponse.contains("<think>") && !isInThinkingMode) {
                    isInThinkingMode = true
                    thinkingStartTime = System.currentTimeMillis()
                    Timber.i("🧠 Entering thinking mode")
                }

                if (isInThinkingMode) {
                    if (fullResponse.contains("</think>")) {
                        // Extract thinking and response content
                        val thinkingRange = fullResponse.indexOf("<think>") + 7
                        val thinkingEndRange = fullResponse.indexOf("</think>")

                        if (thinkingRange < thinkingEndRange) {
                            thinkingContent = fullResponse.substring(thinkingRange, thinkingEndRange)
                            responseContent = fullResponse.substring(thinkingEndRange + 8)
                            isInThinkingMode = false
                            thinkingEndTime = System.currentTimeMillis()
                            Timber.i("🧠 Exiting thinking mode")
                        }
                    } else {
                        // Still in thinking mode
                        val thinkingRange = fullResponse.indexOf("<think>") + 7
                        if (thinkingRange < fullResponse.length) {
                            thinkingContent = fullResponse.substring(thinkingRange)
                        }
                    }
                } else {
                    // Not in thinking mode, show response tokens directly
                    responseContent = fullResponse
                        .replace("<think>", "")
                        .replace("</think>", "")
                        .trim()
                }

                // Update the assistant message
                updateAssistantMessage(
                    messageId = messageId,
                    content = if (isInThinkingMode) "" else responseContent,
                    thinkingContent = if (thinkingContent.isEmpty()) null else thinkingContent.trim(),
                )
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            Timber.i("Streaming cancelled by user")
            wasInterrupted = true
        } catch (e: Exception) {
            Timber.e(e, "Streaming failed")
            wasInterrupted = true
            throw e
        }

        val endTime = System.currentTimeMillis()

        // Handle edge case: Stream ended while still in thinking mode
        if (isInThinkingMode && !fullResponse.contains("</think>")) {
            Timber.w("⚠️ Stream ended while in thinking mode")
            wasInterrupted = true

            if (thinkingContent.isNotEmpty()) {
                val remainingContent =
                    fullResponse
                        .replace("<think>", "")
                        .replace(thinkingContent, "")
                        .trim()

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
    private fun estimateTokenCount(text: String): Int {
        return ceil(text.length / 4.0).toInt()
    }

    /**
     * Create MessageModelInfo for the current loaded model
     */
    private fun createCurrentModelInfo(): MessageModelInfo? {
        val modelName = _uiState.value.loadedModelName ?: return null
        val modelId = RunAnywhere.currentLLMModelId ?: modelName

        return MessageModelInfo(
            modelId = modelId,
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
     * Check model status and load appropriate chat model.
     */
    suspend fun checkModelStatus() {
        try {
            if (app.isSDKReady()) {
                // Check if LLM is already loaded via SDK
                if (RunAnywhere.isLLMModelLoaded()) {
                    val currentModel = RunAnywhere.currentLLMModel()
                    val displayName = currentModel?.name ?: RunAnywhere.currentLLMModelId
                    Timber.i("✅ LLM model already loaded: $displayName")
                    _uiState.value =
                        _uiState.value.copy(
                            isModelLoaded = true,
                            loadedModelName = displayName,
                            currentModelSupportsLora = currentModel?.supportsLora == true,
                        )
                    refreshLoraState()
                    addSystemMessageIfNeeded()
                    return
                }

                // Use SDK's model listing API to find chat models
                val allModels = RunAnywhere.availableModels()
                val chatModel =
                    allModels.firstOrNull { model ->
                        model.category == ModelCategory.LANGUAGE && model.isDownloaded
                    }

                if (chatModel != null) {
                    Timber.i("📦 Found downloaded chat model: ${chatModel.name}, loading...")

                    try {
                        // Load the chat model into memory
                        RunAnywhere.loadLLMModel(chatModel.id)

                        _uiState.value =
                            _uiState.value.copy(
                                isModelLoaded = true,
                                loadedModelName = chatModel.name,
                                currentModelSupportsLora = chatModel.supportsLora,
                            )
                        refreshLoraState()
                        Timber.i("✅ Chat model loaded successfully: ${chatModel.name}")
                    } catch (e: Throwable) {
                        // Catch Throwable to handle both Exception and Error (e.g., UnsatisfiedLinkError)
                        Timber.e(e, "❌ Failed to load chat model: ${e.message}")
                        _uiState.value =
                            _uiState.value.copy(
                                isModelLoaded = false,
                                loadedModelName = null,
                                error = if (e is Exception) e else Exception("Native library not available: ${e.message}", e),
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
            // Catch Throwable to handle both Exception and Error (e.g., UnsatisfiedLinkError)
            Timber.e(e, "Failed to check model status: ${e.message}")
            _uiState.value =
                _uiState.value.copy(
                    isModelLoaded = false,
                    loadedModelName = null,
                    error = if (e is Exception) e else Exception("Failed to check model status: ${e.message}", e),
                )
        }
    }

    /** Refresh LoRA loaded state for the active adapters indicator. */
    private var loraRefreshJob: Job? = null
    fun refreshLoraState() {
        loraRefreshJob?.cancel()
        loraRefreshJob = viewModelScope.launch {
            try {
                val loaded = withContext(Dispatchers.IO) { RunAnywhere.getLoadedLoraAdapters() }
                _uiState.value = _uiState.value.copy(hasActiveLoraAdapter = loaded.isNotEmpty())
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
    private fun getGenerationOptions(): com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions {
        val temperature = generationPrefs.getFloat("defaultTemperature", 0.7f)
        val maxTokens = generationPrefs.getInt("defaultMaxTokens", 1000)
        val systemPromptValue = generationPrefs.getString("defaultSystemPrompt", "")
        val systemPrompt = if (systemPromptValue.isNullOrEmpty()) null else systemPromptValue
        val systemPromptInfo = systemPrompt?.let { "set(${it.length} chars)" } ?: "nil"

        Timber.i("[PARAMS] App getGenerationOptions: temperature=$temperature, maxTokens=$maxTokens, systemPrompt=$systemPromptInfo")

        return com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions(
            maxTokens = maxTokens,
            temperature = temperature,
            systemPrompt = systemPrompt
        )
    }

    /**
     * Format a ToolValue map to JSON string for display.
     * Uses kotlinx.serialization for proper JSON escaping of special characters.
     */
    private fun formatToolValueMapToJson(map: Map<String, ToolValue>): String {
        val jsonObject = buildJsonObject {
            map.forEach { (key, value) ->
                put(key, formatToolValueToJsonElement(value))
            }
        }
        return Json.encodeToString(JsonObject.serializer(), jsonObject)
    }

    /**
     * Convert a ToolValue to the appropriate JsonElement type.
     * Handles all ToolValue variants with proper JSON escaping.
     */
    private fun formatToolValueToJsonElement(value: ToolValue): JsonElement {
        return when (value) {
            is ToolValue.StringValue -> JsonPrimitive(value.value)
            is ToolValue.NumberValue -> JsonPrimitive(value.value)
            is ToolValue.BoolValue -> JsonPrimitive(value.value)
            is ToolValue.NullValue -> JsonNull
            is ToolValue.ArrayValue -> buildJsonArray {
                value.value.forEach { add(formatToolValueToJsonElement(it)) }
            }
            is ToolValue.ObjectValue -> buildJsonObject {
                value.value.forEach { (k, v) -> put(k, formatToolValueToJsonElement(v)) }
            }
        }
    }

}
