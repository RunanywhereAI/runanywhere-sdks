package com.runanywhere.runanywhereai.viewmodels

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.runanywhereai.SDKInitState
import com.runanywhere.runanywhereai.models.ChatEvent
import com.runanywhere.runanywhereai.models.ChatMessage
import com.runanywhere.runanywhereai.models.ChatUiState
import com.runanywhere.runanywhereai.models.Conversation
import com.runanywhere.runanywhereai.models.MessageAnalytics
import com.runanywhere.runanywhereai.models.MessageModelInfo
import com.runanywhere.runanywhereai.repositories.ConversationRepository
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.LLMEvent
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.currentLLMModel
import com.runanywhere.sdk.public.extensions.currentLLMModelId
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.getLoadedLoraAdapters
import com.runanywhere.sdk.public.extensions.isLLMModelLoaded
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.PersistentList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentList
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.math.ceil

class ChatViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as RunAnywhereApplication
    private val conversationRepository = ConversationRepository(application)

    private val _uiState = MutableStateFlow<ChatUiState>(ChatUiState.Loading)
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    /** Conversations list exposed for the history bottom sheet. */
    val conversations: StateFlow<ImmutableList<Conversation>> = conversationRepository.conversations

    private val _events = Channel<ChatEvent>(Channel.BUFFERED)
    val events: Flow<ChatEvent> = _events.receiveAsFlow()

    private var generationJob: Job? = null

    init {
        subscribeToLLMEvents()
        observeSDKState()
        startObservingConversations()
    }

    private fun observeSDKState() {
        viewModelScope.launch {
            app.sdkState.collect { sdkState ->
                when (sdkState) {
                    is SDKInitState.Loading -> { /* stay in Loading */ }
                    is SDKInitState.Ready -> checkModelStatus()
                    is SDKInitState.Error -> {
                        _uiState.value = ChatUiState.Error(sdkState.message)
                    }
                }
            }
        }
    }

    /** Start collecting Room's Flow in the background so conversations stay up to date. */
    private fun startObservingConversations() {
        viewModelScope.launch(Dispatchers.IO) {
            conversationRepository.loadConversations()
        }
    }

    private fun subscribeToLLMEvents() {
        viewModelScope.launch {
            EventBus.events
                .filterIsInstance<LLMEvent>()
                .collect { event -> handleLLMEvent(event) }
        }
    }

    private fun handleLLMEvent(event: LLMEvent) {
        when (event.eventType) {
            LLMEvent.LLMEventType.GENERATION_COMPLETED -> {
                Log.d(TAG, "Generation completed: ${event.tokensGenerated} tokens")
                updateReady { copy(isGenerating = false) }
            }
            LLMEvent.LLMEventType.GENERATION_FAILED -> {
                Log.e(TAG, "Generation failed: ${event.error}")
                updateReady { copy(isGenerating = false, error = event.error) }
            }
            else -> { /* GENERATION_STARTED, STREAM_TOKEN, STREAM_COMPLETED handled elsewhere */ }
        }
    }

    private fun checkModelStatus() {
        viewModelScope.launch {
            try {
                val isLoaded = withContext(Dispatchers.IO) { RunAnywhere.isLLMModelLoaded() }
                val modelInfo = if (isLoaded) withContext(Dispatchers.IO) { RunAnywhere.currentLLMModel() } else null
                // Only show model name if both the SDK says loaded AND we got model info
                val actuallyLoaded = isLoaded && modelInfo != null
                val displayName = if (actuallyLoaded) modelInfo?.name else null

                Log.d(TAG, "checkModelStatus: isLoaded=$isLoaded, modelInfo=${modelInfo?.name}, actuallyLoaded=$actuallyLoaded")

                val conversation = conversationRepository.createConversation()

                _uiState.value = ChatUiState.Ready(
                    isModelLoaded = actuallyLoaded,
                    loadedModelName = displayName,
                    currentModelSupportsLora = if (actuallyLoaded) modelInfo?.supportsLora == true else false,
                    currentConversation = conversation,
                )

                if (actuallyLoaded) refreshLoraState()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to check model status", e)
                _uiState.value = ChatUiState.Ready()
            }
        }
    }

    fun sendMessage(content: String) {
        val state = (_uiState.value as? ChatUiState.Ready) ?: return
        if (content.isBlank() || state.isGenerating || !state.isModelLoaded) return

        val userMessage = ChatMessage.user(content)
        val assistantMessage = ChatMessage.assistant(
            content = "",
            modelInfo = createCurrentModelInfo(),
        )

        updateReady {
            copy(
                messages = (messages + userMessage + assistantMessage).toImmutableList(),
                isGenerating = true,
                error = null,
            )
        }

        // Persist user message
        viewModelScope.launch {
            state.currentConversation?.let { conv ->
                conversationRepository.addMessage(conv.id, userMessage)
            }
        }

        generationJob = viewModelScope.launch {
            try {
                generateWithStreaming(content, assistantMessage.id)
            } catch (e: kotlinx.coroutines.CancellationException) {
                Log.d(TAG, "Generation cancelled by user")
                updateReady { copy(isGenerating = false) }
            } catch (e: Exception) {
                handleGenerationError(e, assistantMessage.id)
            }
        }

        viewModelScope.launch { _events.send(ChatEvent.ScrollToBottom) }
    }

    private suspend fun generateWithStreaming(prompt: String, messageId: String) {
        val startTime = System.currentTimeMillis()
        var firstTokenTime: Long? = null
        var fullResponse = ""
        var isInThinkingMode = false
        var thinkingContent = ""
        var responseContent = ""
        var tokenCount = 0

        val options = LLMGenerationOptions(maxTokens = 1000, temperature = 0.7f)

        RunAnywhere.generateStream(prompt, options).collect { token ->
            fullResponse += token
            tokenCount++

            if (firstTokenTime == null) firstTokenTime = System.currentTimeMillis()

            // Detect thinking mode via <think></think> tags
            if (fullResponse.contains("<think>") && !isInThinkingMode) {
                isInThinkingMode = true
            }

            if (isInThinkingMode) {
                if (fullResponse.contains("</think>")) {
                    val thinkStart = fullResponse.indexOf("<think>") + 7
                    val thinkEnd = fullResponse.indexOf("</think>")
                    if (thinkStart < thinkEnd) {
                        thinkingContent = fullResponse.substring(thinkStart, thinkEnd)
                        responseContent = fullResponse.substring(thinkEnd + 8).trim()
                        isInThinkingMode = false
                    }
                } else {
                    val thinkStart = fullResponse.indexOf("<think>") + 7
                    if (thinkStart < fullResponse.length) {
                        thinkingContent = fullResponse.substring(thinkStart)
                    }
                }
            } else {
                responseContent = fullResponse
                    .replace("<think>", "")
                    .replace("</think>", "")
                    .trim()
            }

            updateAssistantMessage(
                messageId = messageId,
                content = if (isInThinkingMode) "" else responseContent,
                thinkingContent = thinkingContent.trim().takeIf { it.isNotEmpty() },
            )
        }

        val endTime = System.currentTimeMillis()
        val analytics = buildAnalytics(
            startTime = startTime,
            endTime = endTime,
            firstTokenTime = firstTokenTime,
            inputText = prompt,
            outputText = responseContent,
            hasThinking = thinkingContent.isNotEmpty(),
        )
        updateAssistantMessageAnalytics(messageId, analytics)
        syncConversation()

        updateReady { copy(isGenerating = false) }
    }

    private fun handleGenerationError(error: Exception, messageId: String) {
        Log.e(TAG, "Generation failed", error)
        updateAssistantMessage(messageId, "Generation failed: ${error.message}", null)

        // If the LLM component isn't ready, the model isn't actually usable
        val notReady = error.message?.contains("not ready", ignoreCase = true) == true
        updateReady {
            copy(
                isGenerating = false,
                error = error.message,
                isModelLoaded = if (notReady) false else isModelLoaded,
                loadedModelName = if (notReady) null else loadedModelName,
            )
        }
    }

    fun cancelGeneration() {
        generationJob?.cancel()
        RunAnywhere.cancelGeneration()
        updateReady { copy(isGenerating = false) }
    }

    fun onModelLoaded(modelName: String, supportsLora: Boolean = false) {
        updateReady { copy(isModelLoaded = true, loadedModelName = modelName, currentModelSupportsLora = supportsLora) }
        refreshLoraState()
    }

    fun onModelUnloaded() {
        updateReady { copy(isModelLoaded = false, loadedModelName = null) }
    }

    fun clearChat() {
        generationJob?.cancel()
        viewModelScope.launch {
            val conversation = conversationRepository.createConversation()
            updateReady {
                copy(
                    messages = emptyList<ChatMessage>().toImmutableList(),
                    isGenerating = false,
                    error = null,
                    currentConversation = conversation,
                )
            }
        }
    }

    /** Load an existing conversation from history and populate the chat. */
    fun loadConversation(conversationId: String) {
        generationJob?.cancel()
        viewModelScope.launch {
            val conversation = conversationRepository.loadConversation(conversationId)
            if (conversation != null) {
                updateReady {
                    copy(
                        messages = conversation.messages.toImmutableList(),
                        isGenerating = false,
                        error = null,
                        currentConversation = conversation,
                    )
                }
                _events.send(ChatEvent.ScrollToBottom)
            }
        }
    }

    fun deleteConversation(conversationId: String) {
        viewModelScope.launch {
            val state = (_uiState.value as? ChatUiState.Ready)
            conversationRepository.deleteConversation(conversationId)

            // If we just deleted the current conversation, start a new one
            if (state?.currentConversation?.id == conversationId) {
                clearChat()
            }
        }
    }

    fun deleteAllConversations() {
        viewModelScope.launch {
            conversationRepository.deleteAllConversations()
            clearChat()
        }
    }

    fun clearError() {
        updateReady { copy(error = null) }
    }

    private fun refreshLoraState() {
        viewModelScope.launch {
            try {
                val loaded = withContext(Dispatchers.IO) {
                    RunAnywhere.getLoadedLoraAdapters()
                }
                updateReady { copy(hasActiveLoraAdapter = loaded.isNotEmpty()) }
            } catch (e: Exception) {
                Log.d(TAG, "Failed to refresh LoRA state", e)
            }
        }
    }

    // -- Private helpers --

    private fun updateAssistantMessage(
        messageId: String,
        content: String,
        thinkingContent: String?,
    ) {
        updateReady {
            val index = messages.indexOfFirst { it.id == messageId }
            if (index == -1) return@updateReady this
            val persistent = messages as? PersistentList ?: messages.toPersistentList()
            val updated = persistent[index].copy(content = content, thinkingContent = thinkingContent)
            copy(messages = persistent.set(index, updated))
        }
    }

    private fun updateAssistantMessageAnalytics(messageId: String, analytics: MessageAnalytics) {
        updateReady {
            val index = messages.indexOfFirst { it.id == messageId }
            if (index == -1) return@updateReady this
            val persistent = messages as? PersistentList ?: messages.toPersistentList()
            val updated = persistent[index].copy(analytics = analytics)
            copy(messages = persistent.set(index, updated))
        }
    }

    private fun buildAnalytics(
        startTime: Long,
        endTime: Long,
        firstTokenTime: Long?,
        inputText: String,
        outputText: String,
        hasThinking: Boolean,
    ): MessageAnalytics {
        val totalTime = endTime - startTime
        val ttft = firstTokenTime?.let { it - startTime }
        val outputTokens = estimateTokenCount(outputText)
        val tps = if (totalTime > 0) outputTokens.toDouble() / (totalTime / 1000.0) else 0.0

        return MessageAnalytics(
            inputTokens = estimateTokenCount(inputText),
            outputTokens = outputTokens,
            totalGenerationTime = totalTime,
            timeToFirstToken = ttft,
            averageTokensPerSecond = tps,
        )
    }

    private fun estimateTokenCount(text: String): Int = ceil(text.length / 4.0).toInt()

    private fun createCurrentModelInfo(): MessageModelInfo? {
        val state = (_uiState.value as? ChatUiState.Ready) ?: return null
        val name = state.loadedModelName ?: return null
        val id = RunAnywhere.currentLLMModelId ?: name
        return MessageModelInfo(modelId = id, modelName = name, framework = "LLAMA_CPP")
    }

    private fun syncConversation() {
        val state = (_uiState.value as? ChatUiState.Ready) ?: return
        val conv = state.currentConversation ?: return
        val updated = conv.copy(messages = state.messages, updatedAt = System.currentTimeMillis())
        viewModelScope.launch { conversationRepository.updateConversation(updated) }
        updateReady { copy(currentConversation = updated) }
    }

    /** Atomically update the [ChatUiState.Ready] state. No-op if state is not Ready. */
    private inline fun updateReady(crossinline transform: ChatUiState.Ready.() -> ChatUiState.Ready) {
        _uiState.update { current ->
            when (current) {
                is ChatUiState.Ready -> current.transform()
                else -> current
            }
        }
    }

    companion object {
        private const val TAG = "ChatViewModel"
    }
}
