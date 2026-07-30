package com.runanywhere.runanywhereai.ui.screens.chat

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
import com.runanywhere.runanywhereai.BuildConfig
import com.runanywhere.runanywhereai.data.conversation.ConversationRepository
import com.runanywhere.runanywhereai.data.conversation.GenerationMode
import com.runanywhere.runanywhereai.data.conversation.StoredAttachment
import com.runanywhere.runanywhereai.data.conversation.StoredAttachmentKind
import com.runanywhere.runanywhereai.data.conversation.StoredConversation
import com.runanywhere.runanywhereai.data.conversation.StoredMessage
import com.runanywhere.runanywhereai.data.conversation.StoredSource
import com.runanywhere.runanywhereai.data.conversation.StoredStats
import com.runanywhere.runanywhereai.data.conversation.StoredTool
import com.runanywhere.runanywhereai.data.conversation.SmartTitleLifecycle
import com.runanywhere.runanywhereai.data.conversation.SmartTitlePolicy
import com.runanywhere.runanywhereai.data.rag.DocumentExtractor
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.data.settings.WebSearchConsentPolicy
import com.runanywhere.runanywhereai.data.settings.WebSearchConsentState
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.models.LlmModelChangeInterlock
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSnapshot
import com.runanywhere.runanywhereai.ui.screens.vision.DEFAULT_VISION_PROMPT
import com.runanywhere.runanywhereai.ui.screens.vision.VisionAnswerMode
import com.runanywhere.runanywhereai.ui.screens.vision.VisionGenerationPolicy
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.GenerationEvent
import com.runanywhere.sdk.public.api.GenerationResult
import com.runanywhere.sdk.public.api.ImageInput
import com.runanywhere.sdk.public.api.LlmOptions
import com.runanywhere.sdk.public.api.ModelRef
import com.runanywhere.sdk.public.api.RagDocument
import com.runanywhere.sdk.public.api.RagSession
import com.runanywhere.sdk.public.api.ReasoningMode
import com.runanywhere.sdk.public.api.ReasoningOptions
import com.runanywhere.sdk.public.api.TokenKind
import com.runanywhere.sdk.public.api.ToolDefinition
import com.runanywhere.sdk.public.api.ChatMessage as SdkChatMessage
import com.runanywhere.sdk.public.api.llm
import com.runanywhere.sdk.public.api.rag
import com.runanywhere.sdk.public.api.vlm
import com.runanywhere.sdk.public.extensions.Models.analyticsKey
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
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
    var isStopping by mutableStateOf(false)
        private set
    private var isTransitioning by mutableStateOf(false)

    /** True while inference, native cancellation, or a conversation swap owns the chat. */
    val isBusy: Boolean get() = isGenerating || isStopping || isTransitioning

    // Mirrors iOS Conversation.modelName restore (LLMViewModel+ModelManagement
    // loadConversation): the recorded model is preselected for display only,
    // never auto-loaded.
    var conversationModelName by mutableStateOf<String?>(null)
        private set

    val conversationCreatedAt: Long get() = createdAt

    // The preference records user intent; availability is derived from the
    // lifecycle-confirmed model capability so an undersized context model can
    // never reach the native tool run loop.
    private val toolsRequested: Boolean
        get() = WebSearchConsentPolicy.permitsTransfer(
            WebSearchConsentState(
                toolsEnabled = SettingsRepository.settings.toolCallingEnabled,
                acceptedScope = SettingsRepository.settings.webSearchConsentScope,
                currentScope = WebSearchConsentPolicy.routeFor(BuildConfig.WEB_SEARCH_URL)?.scope,
            ),
        )
    private var showToolGateNotice by mutableStateOf(false)

    var showWebSearchDisclosure by mutableStateOf(false)
        private set

    val toolsEnabled: Boolean
        get() = toolsRequested && ToolCallingModelPolicy.evaluate(GlobalState.model.loaded).isAvailable

    val toolsUnavailableMessage: String?
        get() {
            val availability = ToolCallingModelPolicy.evaluate(GlobalState.model.loaded)
            return availability.message.takeIf {
                !availability.isAvailable && (toolsRequested || showToolGateNotice)
            }
        }

    val thinkingSupported: Boolean
        get() = GlobalState.model.loaded?.supports_thinking == true

    val thinkingEnabled: Boolean
        get() = thinkingSupported && !SettingsRepository.settings.disableThinking

    fun toggleThinking() {
        SettingsRepository.setDisableThinking(!SettingsRepository.settings.disableThinking)
    }

    val canSend: Boolean
        get() = input.isNotBlank() && !isBusy && !generationOwnership.isBusy() && GlobalState.model.isLoaded

    private var job: Job? = null
    private var cancellationJob: Job? = null
    private var conversationTransitionJob: Job? = null
    private var persistJob: Job? = null
    private var smartTitleJob: Job? = null
    private val smartTitleLifecycle = SmartTitleLifecycle()
    private val generationOwnership = ChatGenerationOwnership()
    private var activeReplyIndex: Int? = null
    private var activeGenerationModel: Pair<ChatGenerationRequest, String>? = null
    private var conversationId: String? = null
    private var createdAt: Long = 0L
    private var contentRevision: Long = 0L
    private var ragSession: RagSession? = null
    private var ragSessionKey: Pair<String, String>? = null

    init {
        LlmModelChangeInterlock.install(this, ::awaitReadyForLlmModelChange)

        viewModelScope.launch {
            RuntimeModelSelection.observe(ModelSelectionContext.LLM).collect { snapshot ->
                val claim = activeGenerationModel ?: return@collect
                if (generationOwnership.owns(claim.first) && snapshot?.id != claim.second) {
                    // A non-picker path (for example a benchmark) changed the
                    // process-wide model. Revoke the old request immediately;
                    // the picker path is additionally interlocked before load.
                    requestGenerationCancellation(
                        finalizeVisibleReply = true,
                        persistTerminalReply = true,
                    )
                }
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun onCleared() {
        LlmModelChangeInterlock.remove(this)
        val openRag = ragSession
        ragSession = null
        ragSessionKey = null
        if (openRag != null) GlobalScope.launch { runCatching { openRag.close() } }
        conversationTransitionJob?.cancel()
        cancellationJob?.cancel()
        job?.cancel()
        persistJob?.cancel()
        smartTitleJob?.cancel()
        super.onCleared()
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
        if (toolsRequested) {
            SettingsRepository.setWebToolsTransferEnabled(false)
            showToolGateNotice = false
            return
        }
        val availability = ToolCallingModelPolicy.evaluate(GlobalState.model.loaded)
        if (availability.isAvailable) {
            showWebSearchDisclosure = true
            showToolGateNotice = false
        } else {
            showToolGateNotice = true
        }
    }

    fun acceptWebSearchDisclosure() {
        SettingsRepository.setWebToolsTransferEnabled(true)
        showWebSearchDisclosure = false
        showToolGateNotice = false
    }

    fun dismissWebSearchDisclosure() {
        showWebSearchDisclosure = false
    }

    private fun ensureConversationId(): String {
        val existingId = conversationId
        if (existingId != null) {
            return existingId
        }

        val newId = UUID.randomUUID().toString()
        conversationId = newId
        createdAt = System.currentTimeMillis()
        return newId
    }

    fun send() {
        if (!canSend) return
        val request = beginGeneration() ?: return
        val turn = ChatRequestPolicy.snapshot(input.trim(), messages)
        val prompt = turn.prompt
        input = ""
        messages += ChatMessage(text = prompt, isUser = true)
        val replyIndex = messages.size
        messages += ChatMessage("", isUser = false)
        activeReplyIndex = replyIndex

        val titleToStop = cancelSmartTitle()
        val launched = viewModelScope.launch {
            try {
                awaitSmartTitleStopped(titleToStop)
                ensureOwns(request)
                val activeModel = RuntimeModelSelection.requireCurrent(ModelSelectionContext.LLM)
                bindActiveModel(request, activeModel)
                // Trim old turns to the model's context window so small-context models (e.g.
                // Llama-3.2-1B = 512 on v79) don't rc=-130 once a long conversation overruns MAXCTX.
                val effectiveTurn = ChatRequestPolicy.windowHistory(
                    turn = turn,
                    contextTokens = activeModel.model.context_length,
                    outputTokens = ChatGenerationBudgetPolicy.resolve(
                        requestedMaxTokens = SettingsRepository.settings.maxTokens,
                        modelContextTokens = activeModel.model.context_length,
                    ).effectiveMaxTokens,
                    systemPrompt = SettingsRepository.settings.systemPrompt.ifBlank { null },
                )
                val registeredTools = if (toolsRequested) {
                    RunAnywhere.llm.tools.list()
                } else {
                    emptyList()
                }
                val toolPreflight = ToolCallingModelPolicy.preflight(
                    toolsRequested = toolsRequested,
                    registeredToolCount = registeredTools.size,
                    model = activeModel.model,
                )
                when (toolPreflight.route) {
                    ToolCallingRoute.TOOL_GENERATION ->
                        generateWithTools(
                            request,
                            ChatRequestPolicy.toMessages(effectiveTurn),
                            replyIndex,
                            activeModel,
                            registeredTools,
                        )
                    ToolCallingRoute.BLOCKED -> {
                        showToolGateNotice = true
                        updateReply(request, replyIndex) { reply ->
                            reply.copy(
                                text = toolPreflight.availability.message
                                    ?: "Web & tools are unavailable for the current model.",
                            )
                        }
                    }
                    ToolCallingRoute.STANDARD_GENERATION -> {
                        ensureConversationId()
                        val turnMessages = ChatRequestPolicy.toMessages(effectiveTurn)
                        val options = generationOptions(activeModel)
                        if (SettingsRepository.settings.streaming) {
                            streamReply(request, turnMessages, options, replyIndex, activeModel)
                        } else {
                            generateReply(request, turnMessages, options, replyIndex, activeModel)
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("generation failed", e)
                updateReply(request, replyIndex) { it.copy(text = "Error: ${e.message}", thinking = null) }
            } finally {
                finishGeneration(request, replyIndex)
            }
        }
        attachGenerationJob(request, launched)
    }

    fun sendImage(uri: Uri, loadedModel: RAModelInfo?) {
        val request = beginGeneration() ?: return
        val typedPrompt = input.trim()
        val prompt = typedPrompt.ifBlank { DEFAULT_VISION_PROMPT }
        val answerMode = if (typedPrompt.isBlank()) {
            VisionAnswerMode.DETAILED_DESCRIPTION
        } else {
            VisionAnswerMode.FOCUSED_QUESTION
        }
        input = ""

        val titleToStop = cancelSmartTitle()
        val launched = viewModelScope.launch {
            var replyIndex: Int? = null
            try {
                awaitSmartTitleStopped(titleToStop)
                ensureOwns(request)
                val name = withContext(Dispatchers.IO) {
                    runCatching { displayName(uri) }.getOrNull()
                } ?: "Selected image"
                val file = withContext(Dispatchers.IO) {
                    copyUriToAttachmentFile(uri, "chat_image_", imageCacheSuffix(uri))
                }
                ensureOwns(request)
                messages += ChatMessage(
                    text = prompt,
                    isUser = true,
                    attachment = ChatAttachment(
                        kind = ChatAttachmentKind.IMAGE,
                        name = name,
                        localPath = file.absolutePath,
                    ),
                )
                val imageReplyIndex = messages.size
                replyIndex = imageReplyIndex
                messages += ChatMessage("", isUser = false)
                activeReplyIndex = imageReplyIndex
                val image = ImageInput.file(file.absolutePath)
                val activeModel = RuntimeModelSelection.requireCurrent(
                    ModelSelectionContext.VLM,
                    listOfNotNull(loadedModel),
                )
                val options = VisionGenerationPolicy.options(
                    model = activeModel.model,
                    mode = answerMode,
                    userLimit = SettingsRepository.settings.maxTokens,
                )
                ensureOwns(request)
                messages[imageReplyIndex - 1] = messages[imageReplyIndex - 1].copy(
                    attachment = messages[imageReplyIndex - 1].attachment?.copy(
                        detail = "Image model: ${activeModel.model.name}",
                    ),
                )
                // Image answers need the canonical final caption and native
                // metrics. Use the result path so behavior stays uniform across
                // backends with token, chunked, or whole-response streams.
                val started = System.currentTimeMillis()
                val result = RunAnywhere.vlm.generate(image, prompt, options)
                updateReply(request, imageReplyIndex) { reply ->
                    reply.copy(
                        text = result.text.ifBlank { "I could not read that image." },
                        stats = result.toStats(
                            activeModel = activeModel,
                            totalTimeMs = System.currentTimeMillis() - started,
                            mode = GenerationMode.NON_STREAMING,
                        ),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("image question failed", e)
                val index = replyIndex
                if (index != null) {
                    updateReply(request, index) { it.copy(text = "Error: ${e.message}", thinking = null) }
                } else if (generationOwnership.owns(request)) {
                    messages += ChatMessage("Error: ${e.message}", isUser = false)
                }
            } finally {
                finishGeneration(request, replyIndex)
            }
        }
        attachGenerationJob(request, launched)
    }

    fun sendDocument(uri: Uri, embeddingModel: RAModelInfo?, answerModel: RAModelInfo?) {
        val request = beginGeneration() ?: return
        val prompt = input.trim().ifBlank { "Summarize this document." }
        input = ""

        val titleToStop = cancelSmartTitle()
        val launched = viewModelScope.launch {
            var replyIndex: Int? = null
            try {
                awaitSmartTitleStopped(titleToStop)
                ensureOwns(request)
                val name = withContext(Dispatchers.IO) {
                    runCatching { displayName(uri) }.getOrNull()
                } ?: "Selected document"
                val answerModelName = answerModel?.name
                val doc = withContext(Dispatchers.IO) { DocumentExtractor.extract(getApplication(), uri) }
                val file = withContext(Dispatchers.IO) {
                    writeAttachmentTextFile(name, doc.text)
                }
                ensureOwns(request)
                messages += ChatMessage(
                    text = prompt,
                    isUser = true,
                    attachment = ChatAttachment(
                        kind = ChatAttachmentKind.DOCUMENT,
                        name = name,
                        detail = answerModelName?.let { "Answer model: $it" },
                        localPath = file.absolutePath,
                        previewText = doc.text.take(4_000),
                    ),
                )
                val documentReplyIndex = messages.size
                replyIndex = documentReplyIndex
                messages += ChatMessage("", isUser = false)
                activeReplyIndex = documentReplyIndex
                val embedding = embeddingModel ?: error("Choose or download a document index model first.")
                val answer = answerModel ?: error("Choose or download a document answer model first.")
                // One question, one attachment: the session's corpus is replaced
                // per document so an old attachment can never ground a new answer.
                val session = ragSessionFor(embedding.id, answer.id)
                session.clear()
                session.ingest(RagDocument(text = doc.text, metadata = doc.metadata))
                val startedAt = System.currentTimeMillis()
                val result = session.query(prompt)
                ensureOwns(request)
                val sources = result.sources.map {
                    ChatSource(
                        text = it.text.trim(),
                        score = it.score,
                        document = it.metadata["source"].orEmpty(),
                    )
                }
                updateReply(request, documentReplyIndex) { reply ->
                    reply.copy(
                        text = result.answer.ifBlank { "I could not find an answer in that document." },
                        sources = sources,
                        stats = GenerationStats(
                            tokens = result.outputTokens,
                            tokensPerSecond = result.tokensPerSecond.toDouble(),
                            timeToFirstTokenMs = null,
                            totalTimeMs = System.currentTimeMillis() - startedAt,
                            inputTokens = result.inputTokens,
                            modelName = answer.name,
                            mode = GenerationMode.NON_STREAMING,
                        ),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("document question failed", e)
                val index = replyIndex
                if (index != null) {
                    updateReply(request, index) { it.copy(text = "Error: ${e.message}", thinking = null) }
                } else if (generationOwnership.owns(request)) {
                    messages += ChatMessage("Error: ${e.message}", isUser = false)
                }
            } finally {
                finishGeneration(request, replyIndex)
            }
        }
        attachGenerationJob(request, launched)
    }

    private fun generationOptions(activeModel: RuntimeModelSnapshot): LlmOptions {
        val s = SettingsRepository.settings
        val budget = ChatGenerationBudgetPolicy.resolve(
            requestedMaxTokens = s.maxTokens,
            modelContextTokens = activeModel.model.context_length,
        )
        if (budget.isCapped) {
            RACLog.i(
                "chat output budget capped from ${budget.requestedMaxTokens} to " +
                    "${budget.effectiveMaxTokens} for ${activeModel.model.id}",
            )
        }
        // NPU (QHexRT) W8 reasoning bundles — e.g. Cosmos3-Edge Text — put too little probability
        // mass on their end-of-turn token for temperature sampling to reliably select it, so at
        // temperature > 0 they skip it and ramble past the answer (unrelated text / emoji lists).
        // Greedy (temperature 0) picks the end token deterministically, giving clean, self-terminating
        // answers. Well-behaved (non-NPU / non-reasoning) models keep the user's temperature setting.
        val forceGreedy = activeModel.framework ==
            ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT
        // Only apply the "disable thinking" preference to models that actually think — on a
        // non-thinking model the runtime's no-think prefill leaks as literal text ("no think")
        // and corrupts the prompt (e.g. Llama). Bug 5 follow-up. Thought tokens are only
        // emitted when include_in_output is set, so the "show thinking" toggle maps to it.
        val reasoning = when {
            !activeModel.model.supports_thinking -> null
            s.disableThinking -> ReasoningOptions(mode = ReasoningMode.OFF)
            else -> ReasoningOptions(includeInOutput = true)
        }
        return LlmOptions(
            maxOutputTokens = budget.effectiveMaxTokens,
            temperature = if (forceGreedy) 0f else s.temperature,
            systemPrompt = s.systemPrompt.ifBlank { null },
            reasoning = reasoning,
        )
    }

    private suspend fun generateReply(
        request: ChatGenerationRequest,
        messages: List<SdkChatMessage>,
        options: LlmOptions,
        index: Int,
        activeModel: RuntimeModelSnapshot,
    ) {
        val started = System.currentTimeMillis()
        val result = RunAnywhere.llm.generate(messages, options)
        ensureOwns(request)
        updateReply(request, index) { reply ->
            reply.copy(
                text = result.text,
                thinking = result.thinkingText?.takeIf { it.isNotBlank() },
                stats = result.toStats(
                    activeModel = activeModel,
                    totalTimeMs = System.currentTimeMillis() - started,
                    mode = GenerationMode.NON_STREAMING,
                ),
            )
        }
    }

    private suspend fun streamReply(
        request: ChatGenerationRequest,
        messages: List<SdkChatMessage>,
        options: LlmOptions,
        index: Int,
        activeModel: RuntimeModelSnapshot,
    ) {
        if (options.reasoning?.includeInOutput == true) {
            updateReply(request, index) { it.copy(thinking = "") }
        }
        val started = System.currentTimeMillis()
        val answer = StringBuilder()
        val thinking = StringBuilder()
        var completed: GenerationResult? = null

        RunAnywhere.llm.generateStream(messages, options).collect { event ->
            when (event) {
                is GenerationEvent.Token ->
                    if (event.kind == TokenKind.THOUGHT) {
                        thinking.append(event.text)
                        updateReply(request, index) { it.copy(thinking = thinking.toString()) }
                    } else {
                        answer.append(event.text)
                        updateReply(request, index) { it.copy(text = answer.toString()) }
                    }
                is GenerationEvent.Completed -> completed = event.result
                is GenerationEvent.Started, is GenerationEvent.ToolCallRequested -> Unit
            }
        }

        ensureOwns(request)
        val result = completed ?: return
        updateReply(request, index) { reply ->
            reply.copy(
                text = result.text.ifBlank { answer.toString() },
                thinking = result.thinkingText?.takeIf { it.isNotBlank() },
                stats = result.toStats(
                    activeModel = activeModel,
                    totalTimeMs = System.currentTimeMillis() - started,
                    mode = GenerationMode.STREAMING,
                ),
            )
        }
    }

    private suspend fun generateWithTools(
        request: ChatGenerationRequest,
        messages: List<SdkChatMessage>,
        index: Int,
        activeModel: RuntimeModelSnapshot,
        registeredTools: List<ToolDefinition>,
    ) {
        updateReply(request, index) { it.copy(text = ToolCallingExecutionPolicy.PROGRESS_MESSAGE) }
        val execution = ToolCallingExecutionPolicy.plan(
            base = generationOptions(activeModel),
            registeredTools = registeredTools,
        )
        val result = try {
            withTimeout(ToolCallingExecutionPolicy.TIMEOUT_MILLIS) {
                RunAnywhere.llm.generate(messages, execution.generationOptions)
            }
        } catch (_: TimeoutCancellationException) {
            val timeoutSeconds = ToolCallingExecutionPolicy.TIMEOUT_MILLIS / 1_000
            updateReply(request, index) { reply ->
                reply.copy(
                    text = "${activeModel.model.name} did not finish the Web & tools request " +
                        "within $timeoutSeconds seconds. Try a shorter request or another model.",
                    thinking = null,
                )
            }
            return
        }
        ensureOwns(request)
        val toolInfo = result.toolCalls.firstOrNull()?.let { call ->
            val toolResult = result.toolResults.firstOrNull { it.name == call.name }
            ToolCallInfo(
                name = call.name,
                arguments = prettyJson(call.arguments_json),
                result = toolResult?.result_json?.let(::prettyJson),
                success = toolResult != null && toolResult.error.isNullOrBlank(),
                error = toolResult?.error,
            )
        }
        val normalized = ChatToolResultNormalizer.normalize(result)
        updateReply(request, index) { reply ->
            reply.copy(
                text = normalized.text,
                thinking = normalized.thinking,
                tool = toolInfo,
            )
        }
    }

    fun stop() {
        requestGenerationCancellation(
            finalizeVisibleReply = true,
            persistTerminalReply = true,
        )
    }

    fun clearChat() {
        val revision = beginContentTransition()
        val cancellation = requestGenerationCancellation(
            finalizeVisibleReply = false,
            persistTerminalReply = false,
        )
        messages.clear()
        activeReplyIndex = null
        input = ""
        conversationId = null
        createdAt = 0L
        conversationModelName = null
        startConversationTransition(revision) {
            cancellation?.join()
            closeRagSession()
        }
    }

    fun loadConversation(id: String) {
        val revision = beginContentTransition()
        val cancellation = requestGenerationCancellation(
            finalizeVisibleReply = true,
            persistTerminalReply = false,
        )
        startConversationTransition(revision) transition@{
            cancellation?.join()
            // A stored conversation does not rehydrate document bytes, so its
            // questions must never inherit the previous conversation's corpus.
            closeRagSession()
            val stored = ConversationRepository.get(id) ?: return@transition
            if (contentRevision != revision) return@transition
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

    private fun beginGeneration(): ChatGenerationRequest? {
        if (isBusy) return null
        val request = generationOwnership.tryStart() ?: return null
        isGenerating = true
        return request
    }

    private fun attachGenerationJob(request: ChatGenerationRequest, launched: Job) {
        // invokeOnCompletion also covers cancellation before the coroutine ever
        // enters its try/finally body.
        launched.invokeOnCompletion { generationOwnership.finishWorker(request) }
        if (generationOwnership.isBusy()) job = launched
    }

    private fun bindActiveModel(request: ChatGenerationRequest, model: RuntimeModelSnapshot) {
        ensureOwns(request)
        activeGenerationModel = request to model.id
    }

    private fun ensureOwns(request: ChatGenerationRequest) {
        if (!generationOwnership.owns(request)) {
            throw CancellationException("Chat generation no longer owns this conversation")
        }
    }

    private inline fun updateReply(
        request: ChatGenerationRequest,
        index: Int,
        transform: (ChatMessage) -> ChatMessage,
    ): Boolean {
        if (!generationOwnership.owns(request) || index !in messages.indices) return false
        messages[index] = transform(messages[index])
        return true
    }

    private fun finishGeneration(request: ChatGenerationRequest, replyIndex: Int?) {
        val finish = generationOwnership.finishWorker(request)
        if (!finish.ownedAtFinish) return

        if (activeGenerationModel?.first == request) activeGenerationModel = null
        replyIndex?.let { if (activeReplyIndex == it) activeReplyIndex = null }
        job = null
        isGenerating = false
        persist()
    }

    /**
     * Revoke the current request synchronously, then cancel JNI work and wait
     * for its worker on a background barrier. UI animations stop immediately;
     * [canSend] remains false until both terminal conditions are proven.
     */
    private fun requestGenerationCancellation(
        finalizeVisibleReply: Boolean,
        persistTerminalReply: Boolean,
    ): Job? {
        cancellationJob?.takeIf { it.isActive }?.let { return it }

        val request = generationOwnership.requestCancellation()
        val worker = job?.takeIf { !it.isCompleted }
        val titleToStop = cancelSmartTitle()
        if (request == null && titleToStop == null) return null
        val cancellationContentRevision = contentRevision

        if (request != null) {
            if (finalizeVisibleReply) {
                activeReplyIndex?.takeIf { it in messages.indices }?.let { index ->
                    messages[index] = ChatGenerationCleanupPolicy.afterStop(messages[index])
                }
            }
            activeReplyIndex = null
            if (activeGenerationModel?.first == request) activeGenerationModel = null
            isGenerating = false
            worker?.cancel()
        }

        isStopping = true
        lateinit var barrier: Job
        barrier = viewModelScope.launch(start = CoroutineStart.LAZY) {
            var canPersistTerminalReply = false
            try {
                // Cancelling the worker is the whole cancellation contract: the
                // SDK routes it into the native cancel before joining its
                // blocking JNI call.
                request?.let(generationOwnership::markNativeCancellationIssued)
                worker?.join()
                titleToStop?.join()
                if (request != null) {
                    if (generationOwnership.completeCancellation(request)) {
                        canPersistTerminalReply = persistTerminalReply
                    } else {
                        RACLog.e("generation cancellation did not reach a safe terminal state")
                    }
                }
            } finally {
                if (job === worker) job = null
                if (cancellationJob === barrier) cancellationJob = null
                if (!generationOwnership.isBusy()) isStopping = false
            }
            if (canPersistTerminalReply &&
                contentRevision == cancellationContentRevision &&
                !isTransitioning
            ) {
                persist()
            }
        }
        cancellationJob = barrier
        barrier.start()
        return barrier
    }

    private suspend fun awaitReadyForLlmModelChange() {
        withContext(Dispatchers.Main.immediate) {
            conversationTransitionJob?.takeIf { it.isActive }?.join()
            requestGenerationCancellation(
                finalizeVisibleReply = true,
                persistTerminalReply = true,
            )?.join()
            check(!generationOwnership.isBusy()) { "The previous response is still stopping." }
        }
    }

    private fun beginContentTransition(): Long {
        conversationTransitionJob?.cancel()
        contentRevision += 1
        isTransitioning = true
        return contentRevision
    }

    private fun startConversationTransition(revision: Long, block: suspend () -> Unit) {
        lateinit var transition: Job
        transition = viewModelScope.launch(start = CoroutineStart.LAZY) {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("conversation transition failed", e)
            } finally {
                if (contentRevision == revision) {
                    isTransitioning = false
                    if (conversationTransitionJob === transition) conversationTransitionJob = null
                }
            }
        }
        conversationTransitionJob = transition
        transition.start()
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
        val activeModelName = RuntimeModelSelection.cached(ModelSelectionContext.LLM)?.model?.name
        val shouldGenerateSmartTitle = messages.size >= 2 &&
            RuntimeModelSelection.cached(ModelSelectionContext.LLM) != null
        val previousSave = persistJob?.takeIf { it.isActive }
        lateinit var saveJob: Job
        saveJob = viewModelScope.launch(start = CoroutineStart.LAZY) {
            try {
                // One writer per ChatViewModel: an older snapshot can never win
                // a shared temp-file race after a newer response has completed.
                previousSave?.join()
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
                        smartTitleAttempted = existing?.smartTitleAttempted ?: false,
                    ),
                )
                // Mirrors iOS ConversationStore.addMessage: try a smart title after
                // an assistant reply lands (skipped while another generation runs).
                if (shouldGenerateSmartTitle &&
                    !isBusy &&
                    !generationOwnership.isBusy() &&
                    conversationId == id
                ) {
                    scheduleSmartTitle(id)
                }
            } finally {
                if (persistJob === saveJob) persistJob = null
            }
        }
        persistJob = saveJob
        saveJob.start()
        conversationModelName = activeModelName ?: conversationModelName
    }

    private fun scheduleSmartTitle(conversationId: String) {
        if (this.conversationId != conversationId) return
        if (!smartTitleLifecycle.tryStart(conversationId)) return

        lateinit var titleJob: Job
        titleJob = viewModelScope.launch(start = CoroutineStart.LAZY) {
            try {
                withTimeout(SmartTitlePolicy.TIMEOUT_MILLIS) {
                    withContext(Dispatchers.Default) {
                        ConversationRepository.generateSmartTitleIfNeeded(conversationId)
                    }
                }
            } catch (_: TimeoutCancellationException) {
                RACLog.w("smart title generation timed out")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.w("smart title generation failed: ${e.message}")
            } finally {
                smartTitleLifecycle.finish(conversationId)
                if (smartTitleJob === titleJob) smartTitleJob = null
            }
        }
        smartTitleJob = titleJob
        titleJob.start()
    }

    private fun cancelSmartTitle(): Job? = smartTitleJob?.takeIf { it.isActive }?.also { it.cancel() }

    private suspend fun awaitSmartTitleStopped(titleJob: Job?) {
        if (titleJob == null) return
        titleJob.cancel()
        val stopped = withTimeoutOrNull(SmartTitlePolicy.CANCEL_WAIT_MILLIS) {
            titleJob.join()
            true
        } == true
        check(stopped) { "Background title generation is still stopping. Please try again." }
    }

    private suspend fun closeRagSession() {
        val open = ragSession ?: return
        ragSession = null
        ragSessionKey = null
        runCatching { open.close() }.onFailure { RACLog.w("rag session close failed: ${it.message}") }
    }

    /** One session per (index, answer) model pair; a change re-opens it. */
    private suspend fun ragSessionFor(embeddingId: String, answerId: String): RagSession {
        val key = embeddingId to answerId
        ragSession?.let { existing ->
            if (ragSessionKey == key) return existing
            ragSession = null
            ragSessionKey = null
            runCatching { existing.close() }
        }
        val opened = RunAnywhere.rag.open(
            embeddingModel = ModelRef(embeddingId),
            llmModel = ModelRef(answerId),
        )
        ragSession = opened
        ragSessionKey = key
        return opened
    }
}

private fun GenerationResult.toStats(
    activeModel: RuntimeModelSnapshot,
    totalTimeMs: Long,
    mode: GenerationMode,
): GenerationStats =
    GenerationStats(
        tokens = outputTokens,
        tokensPerSecond = tokensPerSecond.toDouble(),
        timeToFirstTokenMs = timeToFirstTokenMs.takeIf { it > 0 },
        totalTimeMs = totalTimeMs,
        inputTokens = inputTokens,
        modelName = activeModel.model.name,
        framework = activeModel.framework.analyticsKey,
        mode = mode,
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
            localPath = it.localPath,
            previewText = it.previewText,
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
            localPath = it.localPath,
            previewText = it.previewText,
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

private fun ChatViewModel.copyUriToAttachmentFile(uri: Uri, prefix: String, suffix: String): File {
    val app = getApplication<Application>()
    val file = File.createTempFile(prefix, suffix, attachmentDirectory())
    try {
        val input = app.contentResolver.openInputStream(uri) ?: error("Could not open the selected file.")
        input.use { source ->
            FileOutputStream(file).use { destination -> source.copyTo(destination) }
        }
        return file
    } catch (e: Exception) {
        file.delete()
        throw e
    }
}

private fun ChatViewModel.writeAttachmentTextFile(filename: String, text: String): File {
    val safeName = filename.replace(Regex("""[/:\\?%*|"<>]"""), "-").ifBlank { "document" }
    val file = File(attachmentDirectory(), "${UUID.randomUUID()}-$safeName.txt")
    file.writeText(text)
    return file
}

private fun ChatViewModel.attachmentDirectory(): File {
    val app = getApplication<Application>()
    return File(app.filesDir, "conversation_attachments").also { it.mkdirs() }
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
