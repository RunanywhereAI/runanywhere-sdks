# SmolChat Android Integration Plan for KMP SDK
## Comprehensive Chat/LLM Functionality Integration

**Created**: September 7, 2025
**Purpose**: Analyze SmolChat Android project patterns and create comprehensive integration plan for KMP SDK chat functionality

---

## Executive Summary

Based on analysis of the SmolChat Android project, this plan outlines how to integrate chat/LLM functionality patterns into the existing KMP SDK's GenerationService and StreamingService components. The integration will provide Android-optimized chat UI components, streaming chat implementation, and efficient chat session management while leveraging the existing llama.cpp integration foundation.

### Key SmolChat Analysis Findings

1. **Architecture**: Uses llama.cpp with JNI bindings for native LLM inference
2. **Streaming**: Real-time token-by-token generation with `Flow<String>`
3. **Database**: Room database with chat sessions, messages, and model management
4. **UI**: Modern Compose UI with markdown rendering and real-time updates
5. **Memory Management**: Context-aware model loading/unloading with memory tracking
6. **Configuration**: Model-specific chat templates and inference parameters

---

## Phase 1: Core Chat Data Models and Components (Week 1)

### 1.1 Chat Data Models Integration

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/chat/ChatModels.kt`**

```kotlin
/**
 * Chat session data model
 */
data class ChatSession(
    val id: String = generateSessionId(),
    val name: String,
    val systemPrompt: String = "",
    val modelId: String,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),

    // Chat configuration
    val chatTemplate: String,
    val maxTokens: Int = 2048,
    val temperature: Float = 0.8f,
    val minP: Float = 0.1f,
    val contextSize: Int = 4096,

    // Session state
    val isActive: Boolean = false,
    val messageCount: Int = 0,
    val tokenUsage: Int = 0,

    // Metadata
    val tags: List<String> = emptyList(),
    val metadata: Map<String, Any> = emptyMap()
)

/**
 * Chat message data model
 */
data class ChatMessage(
    val id: String = generateMessageId(),
    val sessionId: String,
    val content: String,
    val role: MessageRole,
    val timestamp: Long = System.currentTimeMillis(),

    // Generation metadata
    val tokenCount: Int = 0,
    val processingTime: Long = 0,
    val confidence: Float = 1.0f,
    val modelId: String? = null,

    // Message state
    val isComplete: Boolean = true,
    val isEditable: Boolean = role == MessageRole.USER,
    val generationMetrics: GenerationMetrics? = null
)

enum class MessageRole {
    SYSTEM, USER, ASSISTANT
}

data class GenerationMetrics(
    val tokensPerSecond: Float,
    val generationTime: Long,
    val contextLength: Int,
    val stopReason: String?
)

/**
 * Chat streaming state
 */
data class ChatStreamingState(
    val isStreaming: Boolean = false,
    val currentMessage: String = "",
    val completedTokens: Int = 0,
    val estimatedCompletion: Float = 0.0f
)
```

### 1.2 Enhanced Generation Options for Chat

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/chat/ChatGenerationOptions.kt`**

```kotlin
/**
 * Extended generation options specifically for chat scenarios
 */
data class ChatGenerationOptions(
    // Base generation options
    val model: String? = null,
    val temperature: Float = 0.8f,
    val maxTokens: Int = 1000,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val minP: Float = 0.1f,
    val stopSequences: List<String> = emptyList(),
    val seed: Int? = null,

    // Chat-specific options
    val systemPrompt: String? = null,
    val chatTemplate: String? = null,
    val contextWindowSize: Int = 4096,
    val retainContextTokens: Int = 2048, // Keep this many tokens when context is full

    // Streaming options
    val streaming: Boolean = true,
    val streamingBufferSize: Int = 50, // Characters to buffer before emitting
    val partialResultsEnabled: Boolean = true,

    // Memory management
    val enableContextCompression: Boolean = true,
    val compressionRatio: Float = 0.7f,

    // Response formatting
    val enableMarkdownRendering: Boolean = true,
    val enableCodeHighlighting: Boolean = true,
    val enableMathRendering: Boolean = false,

    // Safety and filtering
    val enableContentFiltering: Boolean = true,
    val maxResponseTime: Long = 60_000L, // 60 seconds timeout

    // Analytics
    val trackMetrics: Boolean = true
) {
    fun toGenerationOptions(): GenerationOptions {
        return GenerationOptions(
            model = model,
            temperature = temperature,
            maxTokens = maxTokens,
            topP = topP,
            topK = topK,
            stopSequences = stopSequences,
            streaming = streaming,
            seed = seed
        )
    }
}
```

### 1.3 Chat Repository Interface and Implementation

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/chat/ChatRepository.kt`**

```kotlin
/**
 * Repository interface for chat persistence
 */
interface ChatRepository {
    suspend fun createSession(session: ChatSession): ChatSession
    suspend fun getSession(sessionId: String): ChatSession?
    suspend fun updateSession(session: ChatSession)
    suspend fun deleteSession(sessionId: String)
    suspend fun getAllSessions(): List<ChatSession>
    suspend fun getActiveSessions(): List<ChatSession>

    suspend fun addMessage(message: ChatMessage)
    suspend fun getMessages(sessionId: String): List<ChatMessage>
    suspend fun getMessagesFlow(sessionId: String): Flow<List<ChatMessage>>
    suspend fun updateMessage(message: ChatMessage)
    suspend fun deleteMessage(messageId: String)
    suspend fun deleteMessagesForSession(sessionId: String)

    suspend fun searchMessages(query: String): List<ChatMessage>
    suspend fun getSessionHistory(sessionId: String, limit: Int = 50): List<ChatMessage>
}
```

### 1.4 Android Room Implementation

**File: `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/chat/AndroidChatRepository.kt`**

```kotlin
@Entity(tableName = "chat_sessions")
data class ChatSessionEntity(
    @PrimaryKey val id: String,
    val name: String,
    val systemPrompt: String,
    val modelId: String,
    val createdAt: Long,
    val updatedAt: Long,
    val chatTemplate: String,
    val maxTokens: Int,
    val temperature: Float,
    val minP: Float,
    val contextSize: Int,
    val isActive: Boolean,
    val messageCount: Int,
    val tokenUsage: Int,
    val tags: String, // JSON string
    val metadata: String // JSON string
)

@Entity(tableName = "chat_messages")
data class ChatMessageEntity(
    @PrimaryKey val id: String,
    val sessionId: String,
    val content: String,
    val role: String,
    val timestamp: Long,
    val tokenCount: Int,
    val processingTime: Long,
    val confidence: Float,
    val modelId: String?,
    val isComplete: Boolean,
    val isEditable: Boolean,
    val generationMetrics: String? // JSON string
)

@Dao
interface ChatDao {
    @Query("SELECT * FROM chat_sessions ORDER BY updatedAt DESC")
    fun getAllSessions(): Flow<List<ChatSessionEntity>>

    @Query("SELECT * FROM chat_sessions WHERE id = :sessionId")
    suspend fun getSession(sessionId: String): ChatSessionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSession(session: ChatSessionEntity)

    @Update
    suspend fun updateSession(session: ChatSessionEntity)

    @Query("DELETE FROM chat_sessions WHERE id = :sessionId")
    suspend fun deleteSession(sessionId: String)

    @Query("SELECT * FROM chat_messages WHERE sessionId = :sessionId ORDER BY timestamp ASC")
    fun getMessages(sessionId: String): Flow<List<ChatMessageEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMessage(message: ChatMessageEntity)

    @Query("DELETE FROM chat_messages WHERE sessionId = :sessionId")
    suspend fun deleteMessagesForSession(sessionId: String)

    @Query("SELECT * FROM chat_messages WHERE content LIKE '%' || :query || '%'")
    suspend fun searchMessages(query: String): List<ChatMessageEntity>
}

class AndroidChatRepository(
    private val chatDao: ChatDao,
    private val jsonConverter: JsonConverter
) : ChatRepository {

    override suspend fun createSession(session: ChatSession): ChatSession {
        val entity = session.toEntity(jsonConverter)
        chatDao.insertSession(entity)
        return session
    }

    override suspend fun getSession(sessionId: String): ChatSession? {
        return chatDao.getSession(sessionId)?.toChatSession(jsonConverter)
    }

    override suspend fun getMessagesFlow(sessionId: String): Flow<List<ChatMessage>> {
        return chatDao.getMessages(sessionId).map { entities ->
            entities.map { it.toChatMessage(jsonConverter) }
        }
    }

    // ... other implementation methods
}
```

---

## Phase 2: Streaming Chat Service Integration (Week 2)

### 2.1 Enhanced Chat Service

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/chat/ChatService.kt`**

```kotlin
/**
 * Core chat service that integrates with existing GenerationService and StreamingService
 */
class ChatService(
    private val generationService: GenerationService,
    private val streamingService: StreamingService,
    private val chatRepository: ChatRepository,
    private val contextManager: ChatContextManager,
    private val messageProcessor: MessageProcessor
) {

    private val activeStreams = mutableMapOf<String, Job>()
    private val _streamingStates = MutableStateFlow<Map<String, ChatStreamingState>>(emptyMap())
    val streamingStates: StateFlow<Map<String, ChatStreamingState>> = _streamingStates.asStateFlow()

    /**
     * Send a message and get streaming response
     */
    suspend fun sendMessage(
        sessionId: String,
        content: String,
        options: ChatGenerationOptions = ChatGenerationOptions()
    ): Flow<ChatStreamingResult> = flow {

        val session = chatRepository.getSession(sessionId)
            ?: throw ChatException("Session not found: $sessionId")

        // Add user message to history
        val userMessage = ChatMessage(
            sessionId = sessionId,
            content = content,
            role = MessageRole.USER
        )
        chatRepository.addMessage(userMessage)

        // Prepare context with chat history
        val context = contextManager.prepareContext(session, options)
        val prompt = messageProcessor.buildPrompt(context, content, session.chatTemplate)

        // Start streaming generation
        updateStreamingState(sessionId, ChatStreamingState(isStreaming = true))
        emit(ChatStreamingResult.Started(sessionId))

        val assistantMessageId = generateMessageId()
        var accumulatedContent = ""
        var tokenCount = 0
        val startTime = System.currentTimeMillis()

        try {
            // Use existing StreamingService with enhanced options
            streamingService.stream(prompt, options.toGenerationOptions()).collect { chunk ->
                accumulatedContent += chunk.text
                tokenCount += chunk.tokenCount

                val partialMessage = ChatMessage(
                    id = assistantMessageId,
                    sessionId = sessionId,
                    content = accumulatedContent,
                    role = MessageRole.ASSISTANT,
                    tokenCount = tokenCount,
                    isComplete = chunk.isComplete
                )

                // Update streaming state
                updateStreamingState(sessionId, ChatStreamingState(
                    isStreaming = !chunk.isComplete,
                    currentMessage = accumulatedContent,
                    completedTokens = tokenCount,
                    estimatedCompletion = if (chunk.isComplete) 1.0f else tokenCount.toFloat() / options.maxTokens
                ))

                emit(ChatStreamingResult.ContentChunk(partialMessage, chunk.isComplete))

                // Auto-save partial content periodically
                if (tokenCount % 50 == 0 || chunk.isComplete) {
                    chatRepository.addMessage(partialMessage)
                }
            }

            // Final message processing
            val finalMessage = ChatMessage(
                id = assistantMessageId,
                sessionId = sessionId,
                content = accumulatedContent,
                role = MessageRole.ASSISTANT,
                tokenCount = tokenCount,
                processingTime = System.currentTimeMillis() - startTime,
                isComplete = true,
                generationMetrics = GenerationMetrics(
                    tokensPerSecond = tokenCount.toFloat() / ((System.currentTimeMillis() - startTime) / 1000f),
                    generationTime = System.currentTimeMillis() - startTime,
                    contextLength = context.totalTokens,
                    stopReason = "completed"
                )
            )

            chatRepository.addMessage(finalMessage)
            updateStreamingState(sessionId, ChatStreamingState()) // Reset state

            emit(ChatStreamingResult.Completed(finalMessage))

        } catch (e: Exception) {
            updateStreamingState(sessionId, ChatStreamingState()) // Reset state on error
            emit(ChatStreamingResult.Error(sessionId, e))
            throw ChatException("Generation failed", e)
        }
    }

    /**
     * Send message with non-streaming response
     */
    suspend fun sendMessageSync(
        sessionId: String,
        content: String,
        options: ChatGenerationOptions = ChatGenerationOptions()
    ): ChatMessage {
        val session = chatRepository.getSession(sessionId)
            ?: throw ChatException("Session not found: $sessionId")

        val userMessage = ChatMessage(
            sessionId = sessionId,
            content = content,
            role = MessageRole.USER
        )
        chatRepository.addMessage(userMessage)

        val context = contextManager.prepareContext(session, options)
        val prompt = messageProcessor.buildPrompt(context, content, session.chatTemplate)

        val startTime = System.currentTimeMillis()
        val result = generationService.generate(prompt, options.toGenerationOptions())

        val assistantMessage = ChatMessage(
            sessionId = sessionId,
            content = result.text,
            role = MessageRole.ASSISTANT,
            tokenCount = result.tokensUsed,
            processingTime = System.currentTimeMillis() - startTime,
            generationMetrics = GenerationMetrics(
                tokensPerSecond = result.tokensUsed.toFloat() / (result.latencyMs / 1000f),
                generationTime = result.latencyMs,
                contextLength = context.totalTokens,
                stopReason = "completed"
            )
        )

        chatRepository.addMessage(assistantMessage)
        return assistantMessage
    }

    /**
     * Cancel ongoing generation for a session
     */
    fun cancelGeneration(sessionId: String) {
        activeStreams[sessionId]?.cancel()
        activeStreams.remove(sessionId)
        updateStreamingState(sessionId, ChatStreamingState())
    }

    private fun updateStreamingState(sessionId: String, state: ChatStreamingState) {
        val currentStates = _streamingStates.value.toMutableMap()
        if (state.isStreaming || state.currentMessage.isNotEmpty()) {
            currentStates[sessionId] = state
        } else {
            currentStates.remove(sessionId)
        }
        _streamingStates.value = currentStates
    }
}

/**
 * Streaming result types
 */
sealed class ChatStreamingResult {
    data class Started(val sessionId: String) : ChatStreamingResult()
    data class ContentChunk(val message: ChatMessage, val isComplete: Boolean) : ChatStreamingResult()
    data class Completed(val message: ChatMessage) : ChatStreamingResult()
    data class Error(val sessionId: String, val error: Throwable) : ChatStreamingResult()
}
```

### 2.2 Context Manager for Chat History

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/chat/ChatContextManager.kt`**

```kotlin
/**
 * Manages chat context and memory for conversations
 */
class ChatContextManager(
    private val chatRepository: ChatRepository,
    private val tokenizer: ChatTokenizer
) {

    suspend fun prepareContext(
        session: ChatSession,
        options: ChatGenerationOptions
    ): ChatContext {

        val messages = chatRepository.getMessages(session.id)
        val availableTokens = options.contextWindowSize - options.maxTokens // Reserve space for response

        // Start with system prompt
        var tokenCount = tokenizer.countTokens(session.systemPrompt)
        val contextMessages = mutableListOf<ChatMessage>()

        // Add system message if exists
        if (session.systemPrompt.isNotEmpty()) {
            contextMessages.add(ChatMessage(
                sessionId = session.id,
                content = session.systemPrompt,
                role = MessageRole.SYSTEM
            ))
        }

        // Add messages in reverse chronological order until we hit token limit
        val recentMessages = messages.reversed()
        for (message in recentMessages) {
            val messageTokens = tokenizer.countTokens(message.content)

            if (tokenCount + messageTokens <= availableTokens) {
                contextMessages.add(0, message) // Add to beginning to maintain order
                tokenCount += messageTokens
            } else if (options.enableContextCompression) {
                // Try to compress older messages
                val compressedMessage = compressMessage(message, options.compressionRatio)
                val compressedTokens = tokenizer.countTokens(compressedMessage.content)

                if (tokenCount + compressedTokens <= availableTokens) {
                    contextMessages.add(0, compressedMessage)
                    tokenCount += compressedTokens
                }
            } else {
                break // Stop adding messages if no compression enabled
            }
        }

        return ChatContext(
            messages = contextMessages,
            totalTokens = tokenCount,
            availableTokens = availableTokens - tokenCount,
            isCompressed = contextMessages.any { it.metadata["compressed"] == true }
        )
    }

    private fun compressMessage(message: ChatMessage, ratio: Float): ChatMessage {
        // Simple compression - take first portion of message
        val targetLength = (message.content.length * ratio).toInt()
        val compressed = if (message.content.length > targetLength) {
            message.content.take(targetLength) + "..."
        } else {
            message.content
        }

        return message.copy(
            content = compressed,
            metadata = message.metadata + ("compressed" to true)
        )
    }
}

data class ChatContext(
    val messages: List<ChatMessage>,
    val totalTokens: Int,
    val availableTokens: Int,
    val isCompressed: Boolean
)

/**
 * Token counting interface
 */
interface ChatTokenizer {
    fun countTokens(text: String): Int
    fun tokenize(text: String): List<String>
}

/**
 * Simple tokenizer implementation (can be replaced with model-specific tokenizers)
 */
class SimpleChatTokenizer : ChatTokenizer {
    override fun countTokens(text: String): Int {
        // Simple estimation: ~4 characters per token
        return text.length / 4
    }

    override fun tokenize(text: String): List<String> {
        return text.split("\\s+".toRegex())
    }
}
```

### 2.3 Message Processor for Chat Templates

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/chat/MessageProcessor.kt`**

```kotlin
/**
 * Processes messages and applies chat templates (like ChatML, Llama, etc.)
 */
class MessageProcessor {

    fun buildPrompt(
        context: ChatContext,
        newUserMessage: String,
        chatTemplate: String
    ): String {

        // Add the new user message to context
        val allMessages = context.messages + ChatMessage(
            sessionId = "",
            content = newUserMessage,
            role = MessageRole.USER
        )

        return when {
            chatTemplate.contains("ChatML") -> buildChatMLPrompt(allMessages)
            chatTemplate.contains("Llama") -> buildLlamaPrompt(allMessages)
            chatTemplate.contains("Alpaca") -> buildAlpacaPrompt(allMessages)
            else -> buildDefaultPrompt(allMessages)
        }
    }

    private fun buildChatMLPrompt(messages: List<ChatMessage>): String {
        return buildString {
            for (message in messages) {
                when (message.role) {
                    MessageRole.SYSTEM -> append("<|im_start|>system\n${message.content}<|im_end|>\n")
                    MessageRole.USER -> append("<|im_start|>user\n${message.content}<|im_end|>\n")
                    MessageRole.ASSISTANT -> append("<|im_start|>assistant\n${message.content}<|im_end|>\n")
                }
            }
            append("<|im_start|>assistant\n")
        }
    }

    private fun buildLlamaPrompt(messages: List<ChatMessage>): String {
        return buildString {
            var systemPrompt = ""
            val conversationMessages = mutableListOf<ChatMessage>()

            // Separate system messages from conversation
            for (message in messages) {
                when (message.role) {
                    MessageRole.SYSTEM -> systemPrompt += message.content + "\n"
                    else -> conversationMessages.add(message)
                }
            }

            if (systemPrompt.isNotEmpty()) {
                append("<<SYS>>\n$systemPrompt<</SYS>>\n\n")
            }

            // Build conversation
            for ((index, message) in conversationMessages.withIndex()) {
                when (message.role) {
                    MessageRole.USER -> {
                        if (index == 0 && systemPrompt.isNotEmpty()) {
                            append("[INST] ${message.content} [/INST]")
                        } else {
                            append("[INST] ${message.content} [/INST]")
                        }
                    }
                    MessageRole.ASSISTANT -> append(" ${message.content} ")
                    MessageRole.SYSTEM -> { /* Already handled above */ }
                }
            }
        }
    }

    private fun buildAlpacaPrompt(messages: List<ChatMessage>): String {
        return buildString {
            val systemMessage = messages.find { it.role == MessageRole.SYSTEM }
            val userMessages = messages.filter { it.role == MessageRole.USER }
            val lastUserMessage = userMessages.lastOrNull()

            if (systemMessage != null) {
                append("${systemMessage.content}\n\n")
            }

            if (lastUserMessage != null) {
                append("### Instruction:\n${lastUserMessage.content}\n\n")
                append("### Response:\n")
            }
        }
    }

    private fun buildDefaultPrompt(messages: List<ChatMessage>): String {
        return buildString {
            for (message in messages) {
                when (message.role) {
                    MessageRole.SYSTEM -> append("System: ${message.content}\n\n")
                    MessageRole.USER -> append("Human: ${message.content}\n\n")
                    MessageRole.ASSISTANT -> append("Assistant: ${message.content}\n\n")
                }
            }
            append("Assistant: ")
        }
    }

    /**
     * Apply markdown processing for chat messages
     */
    fun processMessageContent(content: String, enableMarkdown: Boolean): String {
        if (!enableMarkdown) return content

        // Apply basic markdown processing
        return content
            .replace(Regex("```([\\s\\S]*?)```")) { match ->
                "<code_block>${match.groupValues[1]}</code_block>"
            }
            .replace(Regex("`([^`]+)`")) { match ->
                "<code>${match.groupValues[1]}</code>"
            }
            .replace(Regex("\\*\\*([^*]+)\\*\\*")) { match ->
                "<bold>${match.groupValues[1]}</bold>"
            }
    }
}
```

---

## Phase 3: Android Chat UI Components (Week 3)

### 3.1 Chat Component Integration with KMP SDK

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/chat/ChatComponent.kt`**

```kotlin
/**
 * Chat component that integrates with the existing component architecture
 */
class ChatComponent(
    configuration: ChatConfiguration,
    private val serviceContainer: ServiceContainer
) : BaseComponent<ChatService>(configuration) {

    override val componentType = SDKComponent.CHAT
    private val chatConfiguration = configuration as ChatConfiguration
    private val chatService: ChatService by lazy {
        serviceContainer.chatService
    }

    override suspend fun createService(): ChatService {
        return chatService
    }

    override suspend fun initializeService() {
        service?.initialize() ?: throw SDKError.ServiceNotInitialized
    }

    suspend fun createSession(
        name: String,
        modelId: String,
        systemPrompt: String = ""
    ): ChatSession {
        val service = this.service ?: throw SDKError.ComponentNotReady("Chat")

        val session = ChatSession(
            name = name,
            modelId = modelId,
            systemPrompt = systemPrompt,
            chatTemplate = chatConfiguration.defaultChatTemplate,
            maxTokens = chatConfiguration.maxTokens,
            temperature = chatConfiguration.temperature,
            contextSize = chatConfiguration.contextSize
        )

        return service.createSession(session)
    }

    suspend fun sendMessage(
        sessionId: String,
        content: String,
        streaming: Boolean = true
    ): Flow<ChatStreamingResult> {
        val service = this.service ?: throw SDKError.ComponentNotReady("Chat")

        val options = ChatGenerationOptions(
            model = chatConfiguration.defaultModel,
            streaming = streaming,
            maxTokens = chatConfiguration.maxTokens,
            temperature = chatConfiguration.temperature,
            enableMarkdownRendering = chatConfiguration.enableMarkdown
        )

        return service.sendMessage(sessionId, content, options)
    }

    fun getStreamingState(sessionId: String): StateFlow<ChatStreamingState?> {
        return chatService.streamingStates.map { states ->
            states[sessionId]
        }.stateIn(
            scope = componentScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = null
        )
    }

    suspend fun getMessages(sessionId: String): Flow<List<ChatMessage>> {
        return serviceContainer.chatRepository.getMessagesFlow(sessionId)
    }

    suspend fun getAllSessions(): List<ChatSession> {
        return serviceContainer.chatRepository.getAllSessions()
    }

    fun cancelGeneration(sessionId: String) {
        chatService.cancelGeneration(sessionId)
    }

    override suspend fun cleanup() {
        // Cleanup chat-specific resources
        service?.cleanup()
    }
}

data class ChatConfiguration(
    val defaultModel: String = "llama-7b-chat",
    val defaultChatTemplate: String = "ChatML",
    val maxTokens: Int = 1000,
    val temperature: Float = 0.8f,
    val contextSize: Int = 4096,
    val enableMarkdown: Boolean = true,
    val enableAutoSave: Boolean = true,
    val autoSaveInterval: Long = 30_000L // 30 seconds
) : ComponentConfiguration
```

### 3.2 Android Chat UI Components

**File: `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/components/chat/ui/ChatUI.kt`**

```kotlin
/**
 * Android-specific chat UI components
 */

@Composable
fun ChatScreen(
    chatComponent: ChatComponent,
    sessionId: String,
    modifier: Modifier = Modifier,
    onNavigateBack: () -> Unit = {}
) {
    val messages by chatComponent.getMessages(sessionId).collectAsState(initial = emptyList())
    val streamingState by chatComponent.getStreamingState(sessionId).collectAsState()

    var inputText by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val keyboardController = LocalSoftwareKeyboardController.current

    // Auto-scroll to bottom when new messages arrive
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size)
        }
    }

    Column(
        modifier = modifier.fillMaxSize()
    ) {
        // Chat header
        ChatHeader(
            sessionId = sessionId,
            onNavigateBack = onNavigateBack,
            modifier = Modifier.fillMaxWidth()
        )

        // Messages list
        LazyColumn(
            state = listState,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentPadding = PaddingValues(16.dp)
        ) {
            itemsIndexed(messages) { index, message ->
                ChatMessageItem(
                    message = message,
                    isStreaming = streamingState?.isStreaming == true && index == messages.lastIndex,
                    modifier = Modifier.padding(vertical = 4.dp)
                )
            }

            // Show streaming indicator
            if (streamingState?.isStreaming == true && streamingState.currentMessage.isNotEmpty()) {
                item {
                    ChatStreamingIndicator(
                        partialMessage = streamingState.currentMessage,
                        progress = streamingState.estimatedCompletion,
                        modifier = Modifier.padding(vertical = 4.dp)
                    )
                }
            }
        }

        // Message input
        ChatInput(
            text = inputText,
            onTextChange = { inputText = it },
            onSend = { message ->
                if (message.isNotBlank()) {
                    // Launch sending in component scope
                    CoroutineScope(Dispatchers.Main).launch {
                        try {
                            chatComponent.sendMessage(sessionId, message).collect { result ->
                                when (result) {
                                    is ChatStreamingResult.Started -> {
                                        // Clear input when generation starts
                                        inputText = ""
                                        keyboardController?.hide()
                                    }
                                    is ChatStreamingResult.Error -> {
                                        // Handle error (show snackbar, etc.)
                                    }
                                    else -> { /* Handle other cases */ }
                                }
                            }
                        } catch (e: Exception) {
                            // Handle sending error
                        }
                    }
                }
            },
            isGenerating = streamingState?.isStreaming == true,
            onCancelGeneration = {
                chatComponent.cancelGeneration(sessionId)
            },
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
fun ChatMessageItem(
    message: ChatMessage,
    isStreaming: Boolean = false,
    modifier: Modifier = Modifier
) {
    val isUser = message.role == MessageRole.USER

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        if (!isUser) {
            // Assistant avatar
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .background(
                        MaterialTheme.colorScheme.primary,
                        CircleShape
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.Android,
                    contentDescription = "AI",
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.size(20.dp)
                )
            }

            Spacer(modifier = Modifier.width(8.dp))
        }

        Column(
            modifier = Modifier.widthIn(max = 280.dp)
        ) {
            // Message content
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = if (isUser) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.surfaceVariant
                    }
                ),
                shape = RoundedCornerShape(
                    topStart = 16.dp,
                    topEnd = 16.dp,
                    bottomStart = if (isUser) 16.dp else 4.dp,
                    bottomEnd = if (isUser) 4.dp else 16.dp
                )
            ) {
                // Use markdown rendering for assistant messages
                if (isUser) {
                    Text(
                        text = message.content,
                        modifier = Modifier.padding(12.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        style = MaterialTheme.typography.bodyMedium
                    )
                } else {
                    MarkdownText(
                        markdown = message.content,
                        modifier = Modifier.padding(12.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }

            // Message metadata
            if (!isUser && message.generationMetrics != null) {
                Text(
                    text = "${message.generationMetrics.tokensPerSecond.format(1)} tokens/s • ${message.generationMetrics.generationTime}ms",
                    modifier = Modifier.padding(top = 4.dp, start = 8.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        if (isUser) {
            Spacer(modifier = Modifier.width(8.dp))

            // User avatar
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .background(
                        MaterialTheme.colorScheme.secondary,
                        CircleShape
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.Person,
                    contentDescription = "User",
                    tint = MaterialTheme.colorScheme.onSecondary,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

@Composable
fun ChatStreamingIndicator(
    partialMessage: String,
    progress: Float,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start
    ) {
        // AI avatar
        Box(
            modifier = Modifier
                .size(32.dp)
                .background(
                    MaterialTheme.colorScheme.primary,
                    CircleShape
                ),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator(
                progress = progress,
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        Card(
            modifier = Modifier.widthIn(max = 280.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.7f)
            ),
            shape = RoundedCornerShape(
                topStart = 16.dp,
                topEnd = 16.dp,
                bottomStart = 4.dp,
                bottomEnd = 16.dp
            )
        ) {
            Column(
                modifier = Modifier.padding(12.dp)
            ) {
                MarkdownText(
                    markdown = partialMessage,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium
                )

                // Typing indicator
                Row(
                    modifier = Modifier.padding(top = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    repeat(3) { index ->
                        val animatedAlpha by animateFloatAsState(
                            targetValue = if ((System.currentTimeMillis() / 300 % 3).toInt() == index) 1f else 0.3f,
                            animationSpec = tween(300)
                        )

                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .alpha(animatedAlpha)
                                .background(
                                    MaterialTheme.colorScheme.primary,
                                    CircleShape
                                )
                        )

                        if (index < 2) {
                            Spacer(modifier = Modifier.width(4.dp))
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatInput(
    text: String,
    onTextChange: (String) -> Unit,
    onSend: (String) -> Unit,
    isGenerating: Boolean = false,
    onCancelGeneration: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 8.dp
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.Bottom
        ) {
            OutlinedTextField(
                value = text,
                onValueChange = onTextChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text("Type a message...") },
                minLines = 1,
                maxLines = 5,
                shape = RoundedCornerShape(24.dp),
                enabled = !isGenerating,
                keyboardOptions = KeyboardOptions(
                    imeAction = ImeAction.Send,
                    capitalization = KeyboardCapitalization.Sentences
                ),
                keyboardActions = KeyboardActions(
                    onSend = {
                        if (text.isNotBlank() && !isGenerating) {
                            onSend(text)
                        }
                    }
                )
            )

            Spacer(modifier = Modifier.width(8.dp))

            // Send/Cancel button
            if (isGenerating) {
                IconButton(
                    onClick = onCancelGeneration,
                    modifier = Modifier.size(48.dp)
                ) {
                    Icon(
                        Icons.Default.Stop,
                        contentDescription = "Cancel",
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            } else {
                IconButton(
                    onClick = {
                        if (text.isNotBlank()) {
                            onSend(text)
                        }
                    },
                    enabled = text.isNotBlank(),
                    modifier = Modifier
                        .size(48.dp)
                        .background(
                            if (text.isNotBlank()) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.surfaceVariant,
                            CircleShape
                        )
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.Send,
                        contentDescription = "Send",
                        tint = if (text.isNotBlank()) MaterialTheme.colorScheme.onPrimary
                               else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatHeader(
    sessionId: String,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    TopAppBar(
        title = { Text("Chat") },
        navigationIcon = {
            IconButton(onClick = onNavigateBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
        },
        actions = {
            IconButton(onClick = { /* Show session info */ }) {
                Icon(Icons.Default.Info, contentDescription = "Info")
            }
        },
        modifier = modifier
    )
}

@Composable
fun MarkdownText(
    markdown: String,
    modifier: Modifier = Modifier,
    color: Color = LocalContentColor.current,
    style: TextStyle = LocalTextStyle.current
) {
    // Simplified markdown rendering - in production, use a proper markdown library
    val processedText = remember(markdown) {
        markdown
            .replace(Regex("\\*\\*(.+?)\\*\\*"), "$1") // Bold
            .replace(Regex("\\*(.+?)\\*"), "$1") // Italic
            .replace(Regex("`(.+?)`"), "$1") // Code
    }

    Text(
        text = processedText,
        modifier = modifier,
        color = color,
        style = style
    )
}

private fun Float.format(digits: Int): String = "%.${digits}f".format(this)
```

### 3.3 Chat Session Management UI

**File: `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/components/chat/ui/ChatSessionsUI.kt`**

```kotlin
@Composable
fun ChatSessionsScreen(
    chatComponent: ChatComponent,
    onSessionSelected: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    var sessions by remember { mutableStateOf<List<ChatSession>>(emptyList()) }
    var showCreateDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        sessions = chatComponent.getAllSessions()
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Header with create button
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Chat Sessions",
                style = MaterialTheme.typography.headlineMedium
            )

            FloatingActionButton(
                onClick = { showCreateDialog = true },
                modifier = Modifier.size(56.dp)
            ) {
                Icon(Icons.Default.Add, contentDescription = "Create Chat")
            }
        }

        // Sessions list
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 16.dp)
        ) {
            items(sessions) { session ->
                ChatSessionItem(
                    session = session,
                    onClick = { onSessionSelected(session.id) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                )
            }
        }
    }

    // Create session dialog
    if (showCreateDialog) {
        CreateChatSessionDialog(
            onDismiss = { showCreateDialog = false },
            onCreateSession = { name, modelId, systemPrompt ->
                CoroutineScope(Dispatchers.Main).launch {
                    try {
                        val newSession = chatComponent.createSession(name, modelId, systemPrompt)
                        sessions = chatComponent.getAllSessions()
                        showCreateDialog = false
                        onSessionSelected(newSession.id)
                    } catch (e: Exception) {
                        // Handle error
                    }
                }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatSessionItem(
    session: ChatSession,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.clickable { onClick() },
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = session.name,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f)
                )

                if (session.isActive) {
                    Badge {
                        Text("Active")
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = session.modelId,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (session.systemPrompt.isNotEmpty()) {
                Text(
                    text = session.systemPrompt.take(100) + if (session.systemPrompt.length > 100) "..." else "",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "${session.messageCount} messages",
                    style = MaterialTheme.typography.labelSmall
                )

                Text(
                    text = formatTimestamp(session.updatedAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateChatSessionDialog(
    onDismiss: () -> Unit,
    onCreateSession: (String, String, String) -> Unit,
    availableModels: List<String> = listOf("llama-7b-chat", "llama-13b-chat", "gpt-3.5-turbo")
) {
    var sessionName by remember { mutableStateOf("") }
    var selectedModel by remember { mutableStateOf(availableModels.firstOrNull() ?: "") }
    var systemPrompt by remember { mutableStateOf("") }
    var expandedDropdown by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Create New Chat Session") },
        text = {
            Column {
                OutlinedTextField(
                    value = sessionName,
                    onValueChange = { sessionName = it },
                    label = { Text("Session Name") },
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Model selection dropdown
                ExposedDropdownMenuBox(
                    expanded = expandedDropdown,
                    onExpandedChange = { expandedDropdown = !expandedDropdown },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    OutlinedTextField(
                        value = selectedModel,
                        onValueChange = { },
                        readOnly = true,
                        label = { Text("Model") },
                        trailingIcon = {
                            ExposedDropdownMenuDefaults.TrailingIcon(expanded = expandedDropdown)
                        },
                        modifier = Modifier
                            .menuAnchor()
                            .fillMaxWidth()
                    )

                    ExposedDropdownMenu(
                        expanded = expandedDropdown,
                        onDismissRequest = { expandedDropdown = false }
                    ) {
                        availableModels.forEach { model ->
                            DropdownMenuItem(
                                text = { Text(model) },
                                onClick = {
                                    selectedModel = model
                                    expandedDropdown = false
                                }
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                OutlinedTextField(
                    value = systemPrompt,
                    onValueChange = { systemPrompt = it },
                    label = { Text("System Prompt (Optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 3,
                    maxLines = 5
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (sessionName.isNotBlank() && selectedModel.isNotBlank()) {
                        onCreateSession(sessionName, selectedModel, systemPrompt)
                    }
                },
                enabled = sessionName.isNotBlank() && selectedModel.isNotBlank()
            ) {
                Text("Create")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

private fun formatTimestamp(timestamp: Long): String {
    val now = System.currentTimeMillis()
    val diff = now - timestamp

    return when {
        diff < 60_000 -> "Just now"
        diff < 3600_000 -> "${diff / 60_000}m ago"
        diff < 86400_000 -> "${diff / 3600_000}h ago"
        else -> "${diff / 86400_000}d ago"
    }
}
```

---

## Phase 4: Memory Management and Performance (Week 4)

### 4.1 Chat Memory Management

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/chat/ChatMemoryManager.kt`**

```kotlin
/**
 * Manages memory for chat sessions and models
 */
class ChatMemoryManager(
    private val memoryService: MemoryService,
    private val chatRepository: ChatRepository
) {

    private val activeSessions = mutableMapOf<String, ActiveSession>()
    private val sessionMemoryUsage = mutableMapOf<String, Long>()
    private val maxActiveSessions = 3
    private val maxMemoryPerSession = 512 * 1024 * 1024 // 512MB per session

    suspend fun activateSession(sessionId: String, modelId: String): Boolean {
        // Check if we can activate this session
        if (activeSessions.size >= maxActiveSessions) {
            evictLeastRecentlyUsedSession()
        }

        // Check memory availability
        val estimatedMemory = estimateSessionMemoryUsage(sessionId)
        if (!memoryService.hasAvailableMemory(estimatedMemory)) {
            freeMemoryForSession(estimatedMemory)
        }

        // Activate the session
        val activeSession = ActiveSession(
            sessionId = sessionId,
            modelId = modelId,
            activatedAt = System.currentTimeMillis(),
            lastAccessedAt = System.currentTimeMillis()
        )

        activeSessions[sessionId] = activeSession
        sessionMemoryUsage[sessionId] = estimatedMemory

        return true
    }

    fun accessSession(sessionId: String) {
        activeSessions[sessionId]?.let { session ->
            activeSessions[sessionId] = session.copy(lastAccessedAt = System.currentTimeMillis())
        }
    }

    suspend fun deactivateSession(sessionId: String) {
        activeSessions.remove(sessionId)
        sessionMemoryUsage.remove(sessionId)

        // Free memory associated with the session
        memoryService.freeSessionMemory(sessionId)
    }

    private suspend fun evictLeastRecentlyUsedSession() {
        val lruSession = activeSessions.values.minByOrNull { it.lastAccessedAt }
        lruSession?.let { session ->
            deactivateSession(session.sessionId)
        }
    }

    private suspend fun estimateSessionMemoryUsage(sessionId: String): Long {
        val messages = chatRepository.getMessages(sessionId)
        val messageMemory = messages.sumOf { message ->
            message.content.length * 2L // Rough estimate: 2 bytes per character
        }

        // Base model memory + context memory
        return 200 * 1024 * 1024L + messageMemory // 200MB base + message content
    }

    private suspend fun freeMemoryForSession(requiredMemory: Long) {
        var freedMemory = 0L
        val sessionsToEvict = activeSessions.values
            .sortedBy { it.lastAccessedAt }
            .toList()

        for (session in sessionsToEvict) {
            if (freedMemory >= requiredMemory) break

            val sessionMemory = sessionMemoryUsage[session.sessionId] ?: 0L
            deactivateSession(session.sessionId)
            freedMemory += sessionMemory
        }
    }

    fun getMemoryStats(): ChatMemoryStats {
        val totalSessions = activeSessions.size
        val totalMemory = sessionMemoryUsage.values.sum()
        val averageMemoryPerSession = if (totalSessions > 0) totalMemory / totalSessions else 0L

        return ChatMemoryStats(
            activeSessions = totalSessions,
            totalMemoryUsed = totalMemory,
            averageMemoryPerSession = averageMemoryPerSession,
            maxActiveSessions = maxActiveSessions
        )
    }
}

data class ActiveSession(
    val sessionId: String,
    val modelId: String,
    val activatedAt: Long,
    val lastAccessedAt: Long
)

data class ChatMemoryStats(
    val activeSessions: Int,
    val totalMemoryUsed: Long,
    val averageMemoryPerSession: Long,
    val maxActiveSessions: Int
)
```

### 4.2 Chat Performance Monitoring

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/chat/ChatPerformanceMonitor.kt`**

```kotlin
/**
 * Monitors chat performance and provides optimization suggestions
 */
class ChatPerformanceMonitor(
    private val analyticsService: STTAnalyticsService
) {

    private val generationMetrics = mutableMapOf<String, MutableList<GenerationPerformanceMetric>>()
    private val sessionMetrics = mutableMapOf<String, SessionPerformanceMetric>()

    fun recordGenerationMetrics(
        sessionId: String,
        prompt: String,
        response: String,
        metrics: GenerationMetrics
    ) {
        val metric = GenerationPerformanceMetric(
            sessionId = sessionId,
            promptLength = prompt.length,
            responseLength = response.length,
            tokensGenerated = metrics.generationTime.toInt(),
            tokensPerSecond = metrics.tokensPerSecond,
            totalTime = metrics.generationTime,
            contextLength = metrics.contextLength,
            timestamp = System.currentTimeMillis()
        )

        generationMetrics.getOrPut(sessionId) { mutableListOf() }.add(metric)
        updateSessionMetrics(sessionId, metric)

        // Track analytics
        CoroutineScope(Dispatchers.Default).launch {
            analyticsService.trackTranscriptionCompleted(
                text = response,
                confidence = 1.0f,
                duration = metrics.generationTime,
                audioLength = prompt.length.toLong(),
                modelId = "chat-model"
            )
        }
    }

    private fun updateSessionMetrics(sessionId: String, metric: GenerationPerformanceMetric) {
        val currentMetrics = sessionMetrics[sessionId]

        if (currentMetrics == null) {
            sessionMetrics[sessionId] = SessionPerformanceMetric(
                sessionId = sessionId,
                totalGenerations = 1,
                averageTokensPerSecond = metric.tokensPerSecond,
                averageResponseTime = metric.totalTime,
                totalTokensGenerated = metric.tokensGenerated,
                firstGenerationTime = metric.timestamp,
                lastGenerationTime = metric.timestamp
            )
        } else {
            val totalGens = currentMetrics.totalGenerations + 1
            sessionMetrics[sessionId] = currentMetrics.copy(
                totalGenerations = totalGens,
                averageTokensPerSecond = ((currentMetrics.averageTokensPerSecond * currentMetrics.totalGenerations) + metric.tokensPerSecond) / totalGens,
                averageResponseTime = ((currentMetrics.averageResponseTime * currentMetrics.totalGenerations) + metric.totalTime) / totalGens,
                totalTokensGenerated = currentMetrics.totalTokensGenerated + metric.tokensGenerated,
                lastGenerationTime = metric.timestamp
            )
        }
    }

    fun getSessionPerformanceReport(sessionId: String): SessionPerformanceReport? {
        val metrics = sessionMetrics[sessionId] ?: return null
        val generationHistory = generationMetrics[sessionId] ?: emptyList()

        val recommendations = generateOptimizationRecommendations(metrics, generationHistory)

        return SessionPerformanceReport(
            sessionMetrics = metrics,
            recommendations = recommendations,
            generationHistory = generationHistory.takeLast(10) // Last 10 generations
        )
    }

    private fun generateOptimizationRecommendations(
        metrics: SessionPerformanceMetric,
        history: List<GenerationPerformanceMetric>
    ): List<PerformanceRecommendation> {
        val recommendations = mutableListOf<PerformanceRecommendation>()

        // Slow generation speed
        if (metrics.averageTokensPerSecond < 10.0f) {
            recommendations.add(PerformanceRecommendation(
                type = RecommendationType.PERFORMANCE,
                severity = RecommendationSeverity.HIGH,
                title = "Slow Generation Speed",
                description = "Average generation speed is ${metrics.averageTokensPerSecond.format(1)} tokens/second. Consider using a smaller model or reducing context size.",
                actionable = true
            ))
        }

        // High response time
        if (metrics.averageResponseTime > 5000) {
            recommendations.add(PerformanceRecommendation(
                type = RecommendationType.LATENCY,
                severity = RecommendationSeverity.MEDIUM,
                title = "High Response Latency",
                description = "Average response time is ${metrics.averageResponseTime}ms. Consider enabling streaming for better user experience.",
                actionable = true
            ))
        }

        // Context size optimization
        val avgContextLength = history.map { it.contextLength }.average()
        if (avgContextLength > 3000) {
            recommendations.add(PerformanceRecommendation(
                type = RecommendationType.MEMORY,
                severity = RecommendationSeverity.MEDIUM,
                title = "Large Context Size",
                description = "Average context length is ${avgContextLength.toInt()} tokens. Enable context compression to improve performance.",
                actionable = true
            ))
        }

        return recommendations
    }

    fun getGlobalPerformanceStats(): GlobalPerformanceStats {
        val allMetrics = sessionMetrics.values
        if (allMetrics.isEmpty()) {
            return GlobalPerformanceStats(
                totalSessions = 0,
                totalGenerations = 0,
                averageTokensPerSecond = 0.0f,
                averageResponseTime = 0L,
                totalTokensGenerated = 0
            )
        }

        return GlobalPerformanceStats(
            totalSessions = allMetrics.size,
            totalGenerations = allMetrics.sumOf { it.totalGenerations },
            averageTokensPerSecond = allMetrics.map { it.averageTokensPerSecond }.average().toFloat(),
            averageResponseTime = allMetrics.map { it.averageResponseTime }.average().toLong(),
            totalTokensGenerated = allMetrics.sumOf { it.totalTokensGenerated }
        )
    }
}

data class GenerationPerformanceMetric(
    val sessionId: String,
    val promptLength: Int,
    val responseLength: Int,
    val tokensGenerated: Int,
    val tokensPerSecond: Float,
    val totalTime: Long,
    val contextLength: Int,
    val timestamp: Long
)

data class SessionPerformanceMetric(
    val sessionId: String,
    val totalGenerations: Int,
    val averageTokensPerSecond: Float,
    val averageResponseTime: Long,
    val totalTokensGenerated: Int,
    val firstGenerationTime: Long,
    val lastGenerationTime: Long
)

data class SessionPerformanceReport(
    val sessionMetrics: SessionPerformanceMetric,
    val recommendations: List<PerformanceRecommendation>,
    val generationHistory: List<GenerationPerformanceMetric>
)

data class PerformanceRecommendation(
    val type: RecommendationType,
    val severity: RecommendationSeverity,
    val title: String,
    val description: String,
    val actionable: Boolean
)

enum class RecommendationType {
    PERFORMANCE, LATENCY, MEMORY, MODEL_SELECTION
}

enum class RecommendationSeverity {
    LOW, MEDIUM, HIGH
}

data class GlobalPerformanceStats(
    val totalSessions: Int,
    val totalGenerations: Int,
    val averageTokensPerSecond: Float,
    val averageResponseTime: Long,
    val totalTokensGenerated: Int
)

private fun Float.format(digits: Int): String = "%.${digits}f".format(this)
```

---

## Phase 5: Integration Examples and Documentation (Week 5)

### 5.1 Complete Integration Example

**File: `examples/chat-integration/ChatIntegrationExample.kt`**

```kotlin
/**
 * Complete example showing how to integrate chat functionality with the KMP SDK
 */
class ChatIntegrationExample {

    private lateinit var sdk: RunAnywhere
    private lateinit var chatComponent: ChatComponent

    suspend fun initializeSDK() {
        // Initialize the SDK with chat support
        sdk = RunAnywhere.initialize {
            apiKey = "your-api-key"

            // Configure chat-specific settings
            chatConfiguration = ChatConfiguration(
                defaultModel = "llama-7b-chat",
                defaultChatTemplate = "ChatML",
                maxTokens = 1000,
                temperature = 0.8f,
                contextSize = 4096,
                enableMarkdown = true
            )
        }

        // Get the chat component
        chatComponent = sdk.chatComponent
    }

    suspend fun basicChatExample() {
        // Create a new chat session
        val session = chatComponent.createSession(
            name = "General Chat",
            modelId = "llama-7b-chat",
            systemPrompt = "You are a helpful AI assistant."
        )

        println("Created chat session: ${session.name}")

        // Send a message with streaming
        chatComponent.sendMessage(session.id, "Hello! How are you today?").collect { result ->
            when (result) {
                is ChatStreamingResult.Started -> {
                    println("Generation started...")
                }
                is ChatStreamingResult.ContentChunk -> {
                    print(result.message.content)
                    if (result.isComplete) {
                        println("\nGeneration completed!")
                    }
                }
                is ChatStreamingResult.Completed -> {
                    println("Final message: ${result.message.content}")
                    println("Generation metrics: ${result.message.generationMetrics}")
                }
                is ChatStreamingResult.Error -> {
                    println("Error: ${result.error.message}")
                }
            }
        }
    }

    suspend fun advancedChatExample() {
        // Create a specialized chat session
        val session = chatComponent.createSession(
            name = "Code Assistant",
            modelId = "llama-7b-code",
            systemPrompt = """
                You are an expert programming assistant. You help users with:
                - Writing clean, efficient code
                - Debugging issues
                - Explaining programming concepts
                - Code reviews and optimizations

                Always provide code examples when relevant and explain your reasoning.
            """.trimIndent()
        )

        // Multi-turn conversation
        val conversations = listOf(
            "Can you help me write a function to calculate fibonacci numbers?",
            "Now can you optimize it using memoization?",
            "Great! Can you explain how the time complexity improved?"
        )

        for (userMessage in conversations) {
            println("\nUser: $userMessage")
            println("Assistant: ", "")

            var fullResponse = ""
            chatComponent.sendMessage(session.id, userMessage).collect { result ->
                when (result) {
                    is ChatStreamingResult.ContentChunk -> {
                        val newContent = result.message.content.removePrefix(fullResponse)
                        print(newContent)
                        fullResponse = result.message.content
                    }
                    is ChatStreamingResult.Completed -> {
                        println("\n")
                    }
                    is ChatStreamingResult.Error -> {
                        println("Error: ${result.error.message}")
                    }
                    else -> { /* Handle other cases */ }
                }
            }
        }
    }

    suspend fun memoryManagementExample() {
        // Create multiple sessions to demonstrate memory management
        val sessions = (1..5).map { index ->
            chatComponent.createSession(
                name = "Session $index",
                modelId = "llama-7b-chat",
                systemPrompt = "You are assistant $index."
            )
        }

        // Simulate active usage
        for (session in sessions) {
            chatComponent.sendMessage(session.id, "Hello from session ${session.name}!").collect { result ->
                when (result) {
                    is ChatStreamingResult.Completed -> {
                        println("Session ${session.name}: ${result.message.content}")
                    }
                    else -> { /* Handle other cases */ }
                }
            }
        }

        // Check memory usage
        val memoryStats = sdk.memoryService.getMemoryUsage()
        println("Memory usage: ${memoryStats.actualBytes / 1024 / 1024}MB")
    }

    suspend fun performanceMonitoringExample() {
        val session = chatComponent.createSession(
            name = "Performance Test",
            modelId = "llama-7b-chat"
        )

        // Send multiple messages to collect performance data
        val testMessages = listOf(
            "Tell me a short story.",
            "Explain quantum computing in simple terms.",
            "Write a poem about the ocean.",
            "What are the benefits of renewable energy?",
            "Describe the process of photosynthesis."
        )

        for ((index, message) in testMessages.withIndex()) {
            println("Test ${index + 1}: $message")

            val startTime = System.currentTimeMillis()
            var tokenCount = 0

            chatComponent.sendMessage(session.id, message).collect { result ->
                when (result) {
                    is ChatStreamingResult.ContentChunk -> {
                        tokenCount = result.message.tokenCount
                    }
                    is ChatStreamingResult.Completed -> {
                        val totalTime = System.currentTimeMillis() - startTime
                        val tokensPerSecond = if (totalTime > 0) tokenCount / (totalTime / 1000f) else 0f

                        println("Completed in ${totalTime}ms")
                        println("Tokens: $tokenCount")
                        println("Speed: ${"%.2f".format(tokensPerSecond)} tokens/second")
                        println()
                    }
                    else -> { /* Handle other cases */ }
                }
            }
        }

        // Get performance report
        val performanceMonitor = sdk.chatPerformanceMonitor
        val report = performanceMonitor.getSessionPerformanceReport(session.id)

        report?.let {
            println("Performance Report:")
            println("- Total generations: ${it.sessionMetrics.totalGenerations}")
            println("- Average speed: ${"%.2f".format(it.sessionMetrics.averageTokensPerSecond)} tokens/second")
            println("- Average response time: ${it.sessionMetrics.averageResponseTime}ms")

            if (it.recommendations.isNotEmpty()) {
                println("\nRecommendations:")
                it.recommendations.forEach { rec ->
                    println("- [${rec.severity}] ${rec.title}: ${rec.description}")
                }
            }
        }
    }

    suspend fun errorHandlingExample() {
        val session = chatComponent.createSession(
            name = "Error Handling Test",
            modelId = "nonexistent-model" // This will cause an error
        )

        try {
            chatComponent.sendMessage(session.id, "This should fail").collect { result ->
                when (result) {
                    is ChatStreamingResult.Error -> {
                        println("Expected error occurred: ${result.error.message}")

                        // Handle specific error types
                        when (result.error) {
                            is ChatException -> {
                                println("Chat-specific error: ${result.error.message}")
                            }
                            is SDKError -> {
                                when (result.error.type) {
                                    SDKError.ErrorType.MODEL_NOT_FOUND -> {
                                        println("Model not found, trying fallback...")
                                        // Try with a different model
                                    }
                                    SDKError.ErrorType.INSUFFICIENT_MEMORY -> {
                                        println("Insufficient memory, freeing resources...")
                                        // Free some memory
                                    }
                                    else -> {
                                        println("Other SDK error: ${result.error.message}")
                                    }
                                }
                            }
                        }
                    }
                    else -> {
                        println("Unexpected result: $result")
                    }
                }
            }
        } catch (e: Exception) {
            println("Exception caught: ${e.message}")
        }
    }

    suspend fun batchProcessingExample() {
        val session = chatComponent.createSession(
            name = "Batch Processing",
            modelId = "llama-7b-chat",
            systemPrompt = "You are a helpful assistant that provides concise answers."
        )

        val questions = listOf(
            "What is the capital of France?",
            "How do computers work?",
            "What is machine learning?",
            "Explain gravity briefly.",
            "What are the benefits of exercise?"
        )

        // Process questions in parallel with limited concurrency
        val semaphore = Semaphore(2) // Max 2 concurrent generations

        questions.mapIndexed { index, question ->
            async(Dispatchers.Default) {
                semaphore.withPermit {
                    var response = ""

                    chatComponent.sendMessage(session.id, question).collect { result ->
                        when (result) {
                            is ChatStreamingResult.Completed -> {
                                response = result.message.content
                            }
                            else -> { /* Handle other cases */ }
                        }
                    }

                    "Q${index + 1}: $question\nA${index + 1}: $response"
                }
            }
        }.awaitAll().forEach { result ->
            println(result)
            println("---")
        }
    }
}

/**
 * Exception class for chat-specific errors
 */
class ChatException(
    message: String,
    cause: Throwable? = null
) : Exception(message, cause)

/**
 * Extension function for semaphore usage
 */
suspend fun <T> Semaphore.withPermit(action: suspend () -> T): T {
    acquire()
    try {
        return action()
    } finally {
        release()
    }
}
```

### 5.2 Android Activity Integration Example

**File: `examples/chat-integration/ChatActivity.kt`**

```kotlin
/**
 * Example Android Activity showing full chat integration
 */
@AndroidEntryPoint
class ChatExampleActivity : ComponentActivity() {

    private val chatViewModel: ChatExampleViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            ChatExampleTheme {
                ChatExampleApp(chatViewModel)
            }
        }
    }
}

@HiltViewModel
class ChatExampleViewModel @Inject constructor(
    private val chatComponent: ChatComponent
) : ViewModel() {

    private val _sessions = MutableStateFlow<List<ChatSession>>(emptyList())
    val sessions: StateFlow<List<ChatSession>> = _sessions.asStateFlow()

    private val _currentSessionId = MutableStateFlow<String?>(null)
    val currentSessionId: StateFlow<String?> = _currentSessionId.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        loadSessions()
    }

    private fun loadSessions() {
        viewModelScope.launch {
            try {
                _isLoading.value = true
                _sessions.value = chatComponent.getAllSessions()
            } catch (e: Exception) {
                _error.value = "Failed to load sessions: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun createSession(name: String, modelId: String, systemPrompt: String) {
        viewModelScope.launch {
            try {
                _isLoading.value = true
                val session = chatComponent.createSession(name, modelId, systemPrompt)
                _currentSessionId.value = session.id
                loadSessions()
            } catch (e: Exception) {
                _error.value = "Failed to create session: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun selectSession(sessionId: String) {
        _currentSessionId.value = sessionId
    }

    fun clearError() {
        _error.value = null
    }

    fun sendMessage(sessionId: String, message: String): Flow<ChatStreamingResult> {
        return chatComponent.sendMessage(sessionId, message)
    }

    fun cancelGeneration(sessionId: String) {
        chatComponent.cancelGeneration(sessionId)
    }

    fun getMessages(sessionId: String): Flow<List<ChatMessage>> {
        return chatComponent.getMessages(sessionId)
    }

    fun getStreamingState(sessionId: String): StateFlow<ChatStreamingState?> {
        return chatComponent.getStreamingState(sessionId)
    }
}

@Composable
fun ChatExampleApp(viewModel: ChatExampleViewModel) {
    val sessions by viewModel.sessions.collectAsState()
    val currentSessionId by viewModel.currentSessionId.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()

    // Show error message
    error?.let { errorMessage ->
        LaunchedEffect(errorMessage) {
            // Show snackbar or toast
            viewModel.clearError()
        }
    }

    if (currentSessionId != null) {
        // Show chat screen
        ChatScreen(
            chatComponent = viewModel.chatComponent,
            sessionId = currentSessionId!!,
            onNavigateBack = {
                viewModel.selectSession("")
            }
        )
    } else {
        // Show sessions list
        ChatSessionsScreen(
            chatComponent = viewModel.chatComponent,
            onSessionSelected = { sessionId ->
                viewModel.selectSession(sessionId)
            }
        )
    }

    // Show loading indicator
    if (isLoading) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
    }
}

@Preview(showBackground = true)
@Composable
fun ChatExamplePreview() {
    ChatExampleTheme {
        // Preview content
    }
}
```

---

## Summary and Integration Benefits

### Key Integration Points with KMP SDK

1. **Seamless Integration**: Chat functionality builds on existing GenerationService and StreamingService
2. **Component Architecture**: Follows the same BaseComponent pattern as STT and VAD components
3. **Memory Management**: Integrates with existing MemoryService for efficient resource usage
4. **Event System**: Uses EventBus for chat events and analytics
5. **Database Layer**: Extends Android Room implementation with chat-specific entities
6. **Configuration**: Uses same pattern as other component configurations

### SmolChat Patterns Adopted

1. **Real-time Streaming**: Token-by-token generation with Flow-based UI updates
2. **Context Management**: Smart context window management with compression
3. **Memory Optimization**: Session-based memory management and model loading/unloading
4. **Markdown Rendering**: Rich text display for AI responses
5. **Error Recovery**: Robust error handling with fallback strategies
6. **Performance Monitoring**: Real-time performance metrics and optimization suggestions

### Benefits for Developers

1. **Rich Chat UI**: Ready-to-use Compose components for chat interfaces
2. **Streaming Support**: Real-time response generation with progress indicators
3. **Memory Efficient**: Automatic memory management and session lifecycle
4. **Multi-Platform**: Shared business logic with platform-specific UI optimization
5. **Extensible**: Easy to customize chat templates, models, and UI themes
6. **Production Ready**: Includes error handling, analytics, and performance monitoring

### Usage Example

```kotlin
// Initialize SDK with chat support
val sdk = RunAnywhere.initialize {
    apiKey = "your-api-key"
}

// Create and use chat
val session = sdk.chatComponent.createSession(
    name = "My Chat",
    modelId = "llama-7b-chat"
)

sdk.chatComponent.sendMessage(session.id, "Hello!").collect { result ->
    when (result) {
        is ChatStreamingResult.ContentChunk -> updateUI(result.message.content)
        is ChatStreamingResult.Completed -> showCompleteMessage(result.message)
    }
}
```

This comprehensive integration plan provides everything needed to build production-ready chat applications using the KMP SDK, following the proven patterns from SmolChat while maintaining consistency with the existing SDK architecture.
