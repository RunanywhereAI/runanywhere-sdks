package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.GenerationEventKind
import ai.runanywhere.proto.v1.RAGDocument
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.ReasoningMode
import ai.runanywhere.proto.v1.ReasoningOptions
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
import com.runanywhere.runanywhereai.ui.screens.rag.RagPipelineCoordinator
import com.runanywhere.runanywhereai.ui.screens.rag.RagPipelineIdentity
import com.runanywhere.runanywhereai.ui.screens.rag.replaceRagCorpus
import com.runanywhere.runanywhereai.ui.screens.vision.DEFAULT_VISION_PROMPT
import com.runanywhere.runanywhereai.ui.screens.vision.VisionAnswerMode
import com.runanywhere.runanywhereai.ui.screens.vision.VisionGenerationPolicy
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.connect.ConnectModel
import com.runanywhere.sdk.public.connect.ConnectSession
import com.runanywhere.sdk.public.connect.ConnectState
import com.runanywhere.sdk.public.connect.ConnectStatus
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.SDKEvent
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
import com.runanywhere.sdk.public.extensions.ragClearDocuments
import com.runanywhere.sdk.public.extensions.ragGetStatistics
import com.runanywhere.sdk.public.extensions.ragIngest
import com.runanywhere.sdk.public.extensions.ragQuery
import com.runanywhere.sdk.public.api.ImageInput
import com.runanywhere.sdk.public.api.vlm
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAToolDefinition
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
        get() = !isUsingConnect && toolsRequested &&
            ToolCallingModelPolicy.evaluate(GlobalState.model.loaded).isAvailable

    val toolsUnavailableMessage: String?
        get() {
            if (isUsingConnect && toolsRequested) {
                return "Web & tools are unavailable while using a hosted model."
            }
            val availability = ToolCallingModelPolicy.evaluate(GlobalState.model.loaded)
            return availability.message.takeIf {
                !availability.isAvailable && (toolsRequested || showToolGateNotice)
            }
        }

    val thinkingSupported: Boolean
        get() {
            val loaded = GlobalState.model.loaded ?: return false
            // NPU batch backends cannot stream thinking live; hide the capability.
            val framework = loaded.framework
            if (framework == ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT) {
                return false
            }
            return loaded.supports_thinking
        }

    val thinkingEnabled: Boolean
        get() = thinkingSupported && !SettingsRepository.settings.disableThinking

    fun toggleThinking() {
        SettingsRepository.setDisableThinking(!SettingsRepository.settings.disableThinking)
    }

    val canSend: Boolean
        get() = input.isNotBlank() && !isBusy && !generationOwnership.isBusy() && hasUsableModel

    /** A local model is resident, or a hosted one is reachable. */
    val hasUsableModel: Boolean
        get() = GlobalState.model.isLoaded || isUsingConnect

    /**
     * Why a written message cannot be sent, or null when nothing is in the way.
     *
     * Only about the *model*, never about a transient busy state: "sending" and
     * "stopping" already have their own visible affordances (the spinner, the
     * stop button, the stopping pill), and repeating them here would make the
     * composer shout during every normal turn. A missing model is different —
     * it is the one blocker the user has to act on, and without this the send
     * button is simply grey for no stated reason.
     */
    val sendBlockedReason: String?
        get() = if (hasUsableModel) null else "No model is loaded yet."

    val isUsingConnect: Boolean
        get() = connectState.status == ConnectStatus.CONNECTED && connectState.activeModel != null

    private var job: Job? = null
    private var cancellationJob: Job? = null
    private var conversationTransitionJob: Job? = null
    private var persistJob: Job? = null
    private var smartTitleJob: Job? = null
    private var connectStateJob: Job? = null
    private var connectSession: ConnectSession? = null
    private var connectState by mutableStateOf(ConnectState())
    /// In-flight hosted request id for Connect cancel-by-id (Stop keeps session).
    private var activeHostedRequestId: String? = null
    /// Invalidates late hosted stream writes after Stop or conversation swap.
    private var hostedConversationToken: Long = 0
    private val smartTitleLifecycle = SmartTitleLifecycle()
    private val generationOwnership = ChatGenerationOwnership()
    private var activeReplyIndex: Int? = null
    private var activeGenerationModel: Pair<ChatGenerationRequest, String>? = null
    private var conversationId: String? = null
    private var createdAt: Long = 0L
    private var contentRevision: Long = 0L
    private val ragPipelineOwner = "chat-${UUID.randomUUID()}"

    // TTFT/completion metrics from the SDK event bus, keyed like iOS
    // LLMViewModel.firstTokenLatencies. The chat runs one generation at a time,
    // so the latest values are merged into the message stats (mirrors iOS
    // activeGenerationTTFTMs).
    private val firstTokenLatencies = mutableMapOf<String, Long>()
    private var activeGenerationTTFTMs: Long? = null
    private var activeGenerationMetrics: SdkGenerationMetrics? = null

    init {
        LlmModelChangeInterlock.install(this, ::awaitReadyForLlmModelChange)

        // Mirrors iOS LLMViewModel+Events.subscribeToModelLifecycle: generation
        // analytics (TTFT, completion metrics) come from the raw SDK event bus.
        viewModelScope.launch {
            EventBus.events.collect { event ->
                if (event.category == EventCategory.EVENT_CATEGORY_LLM ||
                    event.component == SDKComponent.SDK_COMPONENT_LLM
                ) {
                    handleGenerationEvent(event)
                }
            }
        }
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
        // Cancelling the worker coroutine only unwinds the suspend surface; the
        // one-shot/VLM JNI call keeps decoding on its native thread. Mirror stop()
        // and issue the native cancel, but on GlobalScope because viewModelScope is
        // already being torn down. Guarded so it is a no-op when nothing is running.
        if (generationOwnership.isBusy()) {
            GlobalScope.launch(Dispatchers.Default) {
                runCatching { RunAnywhere.cancelGeneration() }
                runCatching { RunAnywhere.cancelVLMGeneration() }
            }
        }
        conversationTransitionJob?.cancel()
        cancellationJob?.cancel()
        job?.cancel()
        persistJob?.cancel()
        smartTitleJob?.cancel()
        connectStateJob?.cancel()
        super.onCleared()
    }

    fun bindConnectSession(session: ConnectSession) {
        if (connectSession === session) return
        connectStateJob?.cancel()
        connectSession = session
        connectState = session.state.value
        connectStateJob = viewModelScope.launch {
            session.state.collect { connectState = it }
        }
    }

    fun onInputChange(value: String) {
        input = value
    }

    /**
     * Put a suggested prompt in the composer and send it if that is possible.
     *
     * Returns false when the prompt was staged but not sent, so the caller can
     * take the user to whatever is missing. It used to return silently in that
     * case, which made the launch screen's most prominent affordance a dead tap:
     * no message, no keyboard, no explanation.
     */
    fun sendPrompt(prompt: String): Boolean {
        if (isBusy) return false
        input = prompt
        if (!canSend) return false
        send()
        return true
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
        input = ""
        messages += ChatMessage(text = turn.prompt, isUser = true)
        val replyIndex = messages.size
        messages += ChatMessage("", isUser = false)
        activeReplyIndex = replyIndex
        launchTextGeneration(request, turn, replyIndex)
    }

    /**
     * Run one text turn against the loaded (or hosted) model and stream it into
     * `messages[replyIndex]`.
     *
     * Extracted from [send] so [regenerateReply] reaches inference through the
     * exact same path. A second launch site would be a second place for the
     * `generationOwnership` bookkeeping to drift, and that bookkeeping is the
     * only thing stopping a superseded stream from writing into a conversation
     * the user has since replaced.
     */
    private fun launchTextGeneration(
        request: ChatGenerationRequest,
        turn: ChatTurnSnapshot,
        replyIndex: Int,
    ) {
        val prompt = turn.prompt
        val titleToStop = cancelSmartTitle()
        val launched = viewModelScope.launch {
            try {
                awaitSmartTitleStopped(titleToStop)
                ensureOwns(request)
                val hostedModel = connectState.activeModel
                val hostedSession = connectSession
                if (isUsingConnect && hostedModel != null && hostedSession != null) {
                    val streaming = SettingsRepository.settings.streaming && hostedModel.supportsStreaming
                    val effectiveTurn = ChatRequestPolicy.windowHistory(
                        turn = turn,
                        contextTokens = hostedModel.contextWindow,
                        outputTokens = ChatGenerationBudgetPolicy.resolve(
                            requestedMaxTokens = SettingsRepository.settings.maxTokens,
                            modelContextTokens = hostedModel.contextWindow,
                        ).effectiveMaxTokens,
                        systemPrompt = SettingsRepository.settings.systemPrompt.ifBlank { null },
                    )
                    val llmRequest = ChatRequestPolicy.buildRequest(
                        turn = effectiveTurn,
                        // Hosted models do not expose supports_thinking; match iOS
                        // Connect (loadedModelSupportsThinking = false).
                        options = generationOptions(
                            contextTokens = hostedModel.contextWindow,
                            modelName = hostedModel.displayName,
                        ).copy(reasoning = null),
                        conversationId = ensureConversationId(),
                        streaming = streaming,
                    )
                    val hostedRequestId = UUID.randomUUID().toString()
                    activeHostedRequestId = hostedRequestId
                    val hostedToken = ++hostedConversationToken
                    generateHostedReply(
                        request = request,
                        llmRequest = llmRequest.copy(request_id = hostedRequestId),
                        index = replyIndex,
                        model = hostedModel,
                        session = hostedSession,
                        streamUpdates = streaming,
                        hostedToken = hostedToken,
                    )
                } else {
                    val activeModel = RuntimeModelSelection.requireCurrent(ModelSelectionContext.LLM)
                    bindActiveModel(request, activeModel)
                    // Trim old turns to the model's context window so small-context models do not overflow.
                    val effectiveTurn = ChatRequestPolicy.windowHistory(
                        turn = turn,
                        contextTokens = activeModel.model.context_length,
                        outputTokens = ChatGenerationBudgetPolicy.resolve(
                            requestedMaxTokens = SettingsRepository.settings.maxTokens,
                            modelContextTokens = activeModel.model.context_length,
                        ).effectiveMaxTokens,
                        systemPrompt = SettingsRepository.settings.systemPrompt.ifBlank { null },
                    )
                    val registeredTools = if (toolsRequested) RunAnywhere.getRegisteredTools() else emptyList()
                    val toolPreflight = ToolCallingModelPolicy.preflight(
                        toolsRequested = toolsRequested,
                        registeredToolCount = registeredTools.size,
                        model = activeModel.model,
                    )
                    when (toolPreflight.route) {
                        ToolCallingRoute.TOOL_GENERATION ->
                            generateWithTools(
                                request,
                                prompt,
                                replyIndex,
                                activeModel,
                                registeredTools,
                                history = ChatRequestPolicy.toToolCallingHistory(effectiveTurn.history),
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
                            val streaming = SettingsRepository.settings.streaming
                            val llmRequest = ChatRequestPolicy.buildRequest(
                                turn = effectiveTurn,
                                options = generationOptions(activeModel),
                                conversationId = ensureConversationId(),
                                streaming = streaming,
                            )
                            if (streaming) {
                                streamReply(request, llmRequest, replyIndex, activeModel)
                            } else {
                                generateReply(request, llmRequest, replyIndex, activeModel)
                            }
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("generation failed", e)
                updateReply(request, replyIndex) {
                    it.copy(text = errorReplyText(e.message), thinking = null, isError = true)
                }
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
                val startedAt = System.currentTimeMillis()
                val result = withContext(Dispatchers.Default) {
                    RunAnywhere.vlm.generate(ImageInput.file(file.absolutePath), prompt, options)
                }
                updateReply(request, imageReplyIndex) { reply ->
                    reply.copy(
                        text = result.text.ifBlank { "I could not read that image." },
                        stats = GenerationStats(
                            tokens = result.outputTokens,
                            tokensPerSecond = result.tokensPerSecond.toDouble(),
                            timeToFirstTokenMs = result.timeToFirstTokenMs.takeIf { it > 0 },
                            totalTimeMs = System.currentTimeMillis() - startedAt,
                            inputTokens = result.inputTokens,
                            modelName = activeModel.model.name,
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
                    updateReply(request, index) {
                        it.copy(text = errorReplyText(e.message), thinking = null, isError = true)
                    }
                } else if (generationOwnership.owns(request)) {
                    messages += ChatMessage(errorReplyText(e.message), isUser = false, isError = true)
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
                val pipeline = RagPipelineIdentity(
                    embeddingModelId = embedding.id,
                    llmModelId = answer.id,
                    rerankEnabled = false,
                )
                val result = RagPipelineCoordinator.withPipeline(
                    requestedOwner = ragPipelineOwner,
                    requestedIdentity = pipeline,
                    create = {
                        RunAnywhere.ragCreatePipeline(embeddingModel = embedding, llmModel = answer)
                    },
                ) {
                    replaceRagCorpus(
                        clear = { RunAnywhere.ragClearDocuments() },
                        ingest = {
                            RunAnywhere.ragIngest(
                                RAGDocument(text = doc.text, metadata = doc.metadata),
                            )
                        },
                    )
                    runCatching { RunAnywhere.ragGetStatistics() }
                    // The coordinator lease prevents another screen from
                    // swapping the singleton pipeline before the native query.
                    RunAnywhere.ragQuery(prompt, RAGQueryOptions.defaults(question = prompt))
                }
                ensureOwns(request)
                val sources = result.retrieved_chunks.map {
                    ChatSource(
                        text = it.text.trim(),
                        score = it.score,
                        document = it.source_document.orEmpty(),
                    )
                }
                updateReply(request, documentReplyIndex) { reply ->
                    reply.copy(
                        text = result.answer.ifBlank { "I could not find an answer in that document." },
                        sources = sources,
                        stats = GenerationStats(
                            tokens = 0,
                            tokensPerSecond = 0.0,
                            timeToFirstTokenMs = null,
                            // RAGResult.total_time_ms was deleted outright; generation_time_ms is the
                            // remaining canonical duration field.
                            totalTimeMs = result.generation_time_ms,
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
                    updateReply(request, index) {
                        it.copy(text = errorReplyText(e.message), thinking = null, isError = true)
                    }
                } else if (generationOwnership.owns(request)) {
                    messages += ChatMessage(errorReplyText(e.message), isUser = false, isError = true)
                }
            } finally {
                finishGeneration(request, replyIndex)
            }
        }
        attachGenerationJob(request, launched)
    }

    // Mirrors iOS LLMViewModel+Events.handleGenerationEvent: record TTFT on
    // FIRST_TOKEN_GENERATED and completion metrics on COMPLETED (both unary and
    // streaming terminate on COMPLETED now -- STREAM_COMPLETED was retired,
    // "read is_streaming" per idl/sdk_events.proto).
    private fun handleGenerationEvent(event: SDKEvent) {
        val generation = event.generation ?: return
        val generationId = generation.session_id.ifEmpty { event.operation_id }
        when (generation.kind) {
            GenerationEventKind.GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED -> {
                firstTokenLatencies[generationId] = generation.time_to_first_token_ms
                activeGenerationTTFTMs = generation.time_to_first_token_ms
            }
            GenerationEventKind.GENERATION_EVENT_KIND_COMPLETED -> {
                // Only token counts are read from sdkMetrics (when the result
                // proto reports 0). Duration / tok/s / TTFT were write-only and
                // duplicated GenerationEvent.tokens_per_second / result usage.
                activeGenerationMetrics = SdkGenerationMetrics(
                    inputTokens = generation.input_tokens,
                    outputTokens = generation.output_tokens,
                )
                if (firstTokenLatencies.size > MAX_TRACKED_GENERATIONS) firstTokenLatencies.clear()
            }
            else -> Unit
        }
    }

    private fun generationOptions(activeModel: RuntimeModelSnapshot): RALLMGenerationOptions {
        // NPU (QHexRT) W8 reasoning bundles — e.g. Cosmos3-Edge Text — put too little probability
        // mass on their end-of-turn token for temperature sampling to reliably select it, so at
        // temperature > 0 they skip it and ramble past the answer (unrelated text / emoji lists).
        // Greedy (temperature 0) picks the end token deterministically, giving clean, self-terminating
        // answers. Well-behaved (non-NPU / non-reasoning) models keep the user's temperature setting.
        val forceGreedy = activeModel.framework ==
            ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT
        val options = generationOptions(
            contextTokens = activeModel.model.context_length,
            modelName = activeModel.model.name,
            forceGreedy = forceGreedy,
        )
        val s = SettingsRepository.settings
        // QHexRT Maple/Bonsai finishes the whole decode before streaming. With
        // thinking on, "TTFT" becomes the full generate (reasoning + answer) and
        // the chat burns tokens on chain-of-thought the UI can't stream live.
        // Keep reasoning off for NPU until token-level streaming exists.
        val reasoning = when {
            activeModel.framework ==
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT ->
                ReasoningOptions(mode = ReasoningMode.REASONING_MODE_OFF)
            !activeModel.model.supports_thinking -> null
            s.disableThinking -> ReasoningOptions(mode = ReasoningMode.REASONING_MODE_OFF)
            else -> ReasoningOptions(
                mode = ReasoningMode.REASONING_MODE_ON,
                include_in_output = true,
                pattern = activeModel.model.thinking_pattern,
            )
        }
        return options.copy(reasoning = reasoning)
    }

    private fun generationOptions(
        contextTokens: Int,
        modelName: String,
        forceGreedy: Boolean = false,
    ): RALLMGenerationOptions {
        val s = SettingsRepository.settings
        val budget = ChatGenerationBudgetPolicy.resolve(
            requestedMaxTokens = s.maxTokens,
            modelContextTokens = contextTokens,
        )
        if (budget.isCapped) {
            RACLog.i(
                "chat output budget capped from ${budget.requestedMaxTokens} to " +
                    "${budget.effectiveMaxTokens} for $modelName",
            )
        }
        return RALLMGenerationOptions(
            max_output_tokens = budget.effectiveMaxTokens,
            temperature = if (forceGreedy) 0f else s.temperature,
            system_prompt = s.systemPrompt.ifBlank { null },
            reasoning = if (s.disableThinking) {
                ReasoningOptions(mode = ReasoningMode.REASONING_MODE_OFF)
            } else {
                null
            },
        )
    }

    private fun generationStats(
        tokens: Int,
        reportedTps: Double?,
        reportedTtftMs: Long?,
        batchBuffered: Boolean,
        totalMs: Long,
        inputTokens: Int,
        modelName: String,
        framework: String?,
        mode: GenerationMode,
    ): GenerationStats {
        // TokenUsage owns decode rate + TTFT + batch_buffered. Do not invent
        // wall tok/s or re-derive the flush heuristic — AnalyticsFooter must
        // match BenchmarkRunner / commons for the same turn.
        return GenerationStats(
            tokens = tokens,
            tokensPerSecond = reportedTps?.takeIf { it > 0.0 } ?: 0.0,
            timeToFirstTokenMs = if (batchBuffered) null else reportedTtftMs?.takeIf { it > 0 },
            totalTimeMs = totalMs,
            inputTokens = inputTokens,
            modelName = modelName,
            framework = framework,
            mode = mode,
        )
    }

    private suspend fun generateHostedReply(
        request: ChatGenerationRequest,
        llmRequest: RALLMGenerateRequest,
        index: Int,
        model: ConnectModel,
        session: ConnectSession,
        streamUpdates: Boolean,
        hostedToken: Long,
    ) {
        val events = session.generateStream(llmRequest)
        val prompt = llmRequest.messages.lastOrNull()?.content.orEmpty()
        val result = RunAnywhere.aggregateStream(prompt, events) { accumulated ->
            if (hostedToken != hostedConversationToken) return@aggregateStream
            if (streamUpdates) updateReply(request, index) { it.copy(text = accumulated) }
        }

        if (hostedToken != hostedConversationToken) return
        ensureOwns(request)
        if (!result.error?.message.isNullOrBlank()) {
            updateReply(request, index) {
                it.copy(text = errorReplyText(result.error?.message), thinking = null, isError = true)
            }
            return
        }
        val totalMs = result.generation_time_ms.toLong()
        val tokens = result.usage?.output_tokens ?: 0
        updateReply(request, index) { reply ->
            reply.copy(
                text = result.text,
                thinking = result.thinking_content?.takeIf { it.isNotBlank() },
                stats = generationStats(
                    tokens = tokens,
                    reportedTps = result.usage?.decode_tokens_per_second,
                    reportedTtftMs = result.usage?.ttft_ms,
                    batchBuffered = result.usage?.batch_buffered == true,
                    totalMs = totalMs,
                    inputTokens = result.usage?.input_tokens ?: 0,
                    modelName = model.displayName,
                    framework = model.framework,
                    mode = if (streamUpdates) GenerationMode.STREAMING else GenerationMode.NON_STREAMING,
                ),
            )
        }
        conversationModelName = model.displayName
        if (activeHostedRequestId == llmRequest.request_id) {
            activeHostedRequestId = null
        }
    }

    private suspend fun generateReply(
        request: ChatGenerationRequest,
        llmRequest: RALLMGenerateRequest,
        index: Int,
        activeModel: RuntimeModelSnapshot,
    ) {
        // The SDK one-shot bridge is synchronous JNI underneath its suspend
        // surface. Never let it occupy Android's main dispatcher.
        val result = withContext(Dispatchers.Default) {
            RunAnywhere.generate(llmRequest)
        }
        ensureOwns(request)
        if (!result.error?.message.isNullOrBlank()) {
            updateReply(request, index) {
                it.copy(text = errorReplyText(result.error?.message), thinking = null, isError = true)
            }
            return
        }
        val sdkMetrics = activeGenerationMetrics
        val totalMs = result.generation_time_ms.toLong()
        val outputTokens = result.usage?.output_tokens ?: 0
        updateReply(request, index) { reply ->
            reply.copy(
                text = ChatToolResultNormalizer.stripStrayToolCall(result.text),
                thinking = result.thinking_content?.takeIf { it.isNotBlank() },
                stats = generationStats(
                    tokens = outputTokens,
                    reportedTps = result.usage?.decode_tokens_per_second,
                    reportedTtftMs = result.usage?.ttft_ms,
                    batchBuffered = result.usage?.batch_buffered == true,
                    totalMs = totalMs,
                    inputTokens = result.usage?.input_tokens?.takeIf { it > 0 } ?: sdkMetrics?.inputTokens ?: 0,
                    modelName = activeModel.model.name,
                    framework = result.framework?.takeIf { it.isNotBlank() }
                        ?: activeModel.framework.analyticsKey,
                    mode = GenerationMode.NON_STREAMING,
                ),
            )
        }
    }

    private suspend fun streamReply(
        request: ChatGenerationRequest,
        llmRequest: RALLMGenerateRequest,
        index: Int,
        activeModel: RuntimeModelSnapshot,
    ) {
        if (llmRequest.options?.reasoning?.include_in_output == true) {
            updateReply(request, index) { it.copy(thinking = "") }
        }
        val events = RunAnywhere.generateStream(llmRequest)
        val result =
            RunAnywhere.aggregateStream(
                prompt = llmRequest.messages.lastOrNull()?.content.orEmpty(),
                events = events,
                onThinking = { accumulated ->
                    updateReply(request, index) { it.copy(thinking = accumulated) }
                },
                onToken = { accumulated ->
                    // Tool-trained models emit call syntax unprompted even with no tools registered; on the
                    // standard route those markers are noise, so never let them reach the bubble.
                    updateReply(request, index) {
                        it.copy(text = ChatToolResultNormalizer.stripStrayToolCall(accumulated))
                    }
                },
            )

        ensureOwns(request)
        if (!result.error?.message.isNullOrBlank()) {
            updateReply(request, index) {
                it.copy(text = errorReplyText(result.error?.message), thinking = null, isError = true)
            }
            return
        }

        val sdkMetrics = activeGenerationMetrics
        val totalMs = result.generation_time_ms.toLong()
        val tokens = result.usage?.output_tokens?.takeIf { it > 0 } ?: sdkMetrics?.outputTokens ?: 0
        updateReply(request, index) { reply ->
            reply.copy(
                text = ChatToolResultNormalizer.stripStrayToolCall(result.text),
                thinking = result.thinking_content?.takeIf { it.isNotBlank() },
                stats = generationStats(
                    tokens = tokens,
                    reportedTps = result.usage?.decode_tokens_per_second,
                    reportedTtftMs = result.usage?.ttft_ms,
                    batchBuffered = result.usage?.batch_buffered == true,
                    totalMs = totalMs,
                    inputTokens = result.usage?.input_tokens?.takeIf { it > 0 } ?: sdkMetrics?.inputTokens ?: 0,
                    modelName = activeModel.model.name,
                    framework = result.framework?.takeIf { it.isNotBlank() }
                        ?: activeModel.framework.analyticsKey,
                    mode = GenerationMode.STREAMING,
                ),
            )
        }
    }

    private suspend fun generateWithTools(
        request: ChatGenerationRequest,
        prompt: String,
        index: Int,
        activeModel: RuntimeModelSnapshot,
        registeredTools: List<RAToolDefinition>,
        history: List<String> = emptyList(),
    ) {
        updateReply(request, index) { it.copy(text = ToolCallingExecutionPolicy.PROGRESS_MESSAGE) }
        val execution = ToolCallingExecutionPolicy.plan(
            base = generationOptions(activeModel),
            registeredTools = registeredTools,
        )
        val result = try {
            withTimeout(ToolCallingExecutionPolicy.TIMEOUT_MILLIS) {
                withContext(Dispatchers.Default) {
                    RunAnywhere.generateWithTools(
                        prompt = prompt,
                        options = execution.generationOptions,
                        toolOptions = execution.toolOptions,
                        toolChoice = execution.toolChoice,
                        forcedToolName = execution.forcedToolName,
                        history = history,
                    )
                }
            }
        } catch (_: TimeoutCancellationException) {
            withContext(Dispatchers.Default) { runCatching { RunAnywhere.cancelGeneration() } }
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

    /**
     * Replace an assistant reply by re-asking the question above it.
     *
     * The reply and everything after it are dropped first, so the model sees a
     * history ending at the question exactly as a fresh turn does — leaving the
     * old answer in place would condition the retry on the answer it is meant to
     * replace. Mirrors iOS `LLMViewModel.regenerateReply`.
     */
    fun regenerateReply(index: Int) {
        if (isBusy) return
        if (index !in messages.indices || messages[index].isUser) return
        val questionIndex = (index - 1 downTo 0).firstOrNull { messages[it].isUser } ?: return
        val prompt = messages[questionIndex].text.trim()
        if (prompt.isEmpty()) return

        val request = beginGeneration() ?: return
        // Persist the trimmed transcript before regenerating so a force-quit
        // mid-retry reopens the chat at the question rather than at an answer the
        // user already rejected.
        messages.removeRange(questionIndex + 1, messages.size)
        persist()

        // History stops *before* the question, because the question is the prompt. Snapshotting the
        // whole trimmed transcript would hand the model the question twice — once as the last
        // history turn and again as the prompt — which is not the conversation the original turn
        // saw, and the duplicate spends context budget in windowHistory. send() gets this for free
        // by snapshotting before it appends the user message; here the question is already in place.
        val turn = ChatRequestPolicy.snapshot(prompt, messages.take(questionIndex))
        val replyIndex = messages.size
        messages += ChatMessage("", isUser = false)
        activeReplyIndex = replyIndex
        launchTextGeneration(request, turn, replyIndex)
    }

    /**
     * Put a question back in the composer and rewind the transcript to just
     * before it, so sending again continues from that point.
     *
     * Deliberately does not auto-send: the reason to edit is to change the
     * wording, and an edit that fires immediately leaves nowhere to do that.
     */
    fun editQuestion(index: Int) {
        if (isBusy) return
        if (index !in messages.indices || !messages[index].isUser) return
        input = messages[index].text
        messages.removeRange(index, messages.size)
        persistTrimmedTranscript()
    }

    /**
     * Delete a message. Deleting a question also deletes the reply it produced.
     *
     * A question and its answer are one exchange: keeping the answer would leave
     * a reply with nothing to reply to, and [ChatRequestPolicy.snapshot] would
     * then hand the model an unanchored assistant turn. Deleting an answer alone
     * is fine — the question stands and Retry is right there.
     */
    fun deleteMessage(index: Int) {
        if (isBusy) return
        if (index !in messages.indices) return
        val last = if (messages[index].isUser && messages.getOrNull(index + 1)?.isUser == false) {
            index + 1
        } else {
            index
        }
        messages.removeRange(index, last + 1)
        persistTrimmedTranscript()
    }

    /**
     * Write a transcript that just got shorter.
     *
     * [persist] rewrites the whole message list, so it expresses a deletion fine —
     * except that it declines outright when no question remains. Removing the last
     * exchange would therefore leave the old messages on disk and the chat would
     * reappear in History with exactly what the user just deleted, so an emptied
     * transcript drops the conversation instead of saving it.
     */
    private fun persistTrimmedTranscript() {
        if (messages.any { it.isUser }) persist() else discardEmptyConversation()
    }

    /**
     * Forget a conversation the user just emptied, without touching the composer.
     *
     * Deliberately not [clearChat]: that clears `input`, and editing the *first*
     * question empties the transcript at the exact moment the question is sitting
     * in the composer waiting to be reworded — so routing this through
     * `clearChat` silently ate the text the edit had just placed there.
     *
     * There is no generation to cancel: both callers refuse to run while
     * [isBusy]. The RAG corpus goes with the messages, since no remaining
     * question is anchored to it.
     */
    private fun discardEmptyConversation() {
        val discarded = conversationId
        conversationId = null
        createdAt = 0L
        conversationModelName = null
        activeReplyIndex = null
        viewModelScope.launch {
            discarded?.let { ConversationRepository.delete(it) }
            RagPipelineCoordinator.release(ragPipelineOwner)
        }
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
            RagPipelineCoordinator.release(ragPipelineOwner)
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
            RagPipelineCoordinator.release(ragPipelineOwner)
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
        activeGenerationTTFTMs = null
        activeGenerationMetrics = null
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
                // Both APIs are safe to call when their modality is inactive.
                // Running them off Main keeps Stop/New Chat/model selection responsive.
                withContext(Dispatchers.Default) {
                    if (isUsingConnect) {
                        activeHostedRequestId?.let { requestId ->
                            connectSession?.cancelGeneration(requestId)
                        }
                        hostedConversationToken += 1
                        activeHostedRequestId = null
                    }
                    // Local modalities still need native cancel; safe when inactive.
                    runCatching { RunAnywhere.cancelGeneration() }
                    runCatching { RunAnywhere.cancelVLMGeneration() }
                }
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
        val activeModelName = when {
            isUsingConnect -> connectState.activeModel?.displayName
            else -> RuntimeModelSelection.cached(ModelSelectionContext.LLM)?.model?.name
        }
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
            // withTimeout cancels the coroutine; this sibling watchdog also
            // reaches the blocking JNI call through the native cancel API.
            val watchdog = launch {
                delay(SmartTitlePolicy.TIMEOUT_MILLIS)
                withContext(Dispatchers.Default) { RunAnywhere.cancelGeneration() }
            }
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
                watchdog.cancel()
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
        withContext(Dispatchers.Default) { RunAnywhere.cancelGeneration() }
        val stopped = withTimeoutOrNull(SmartTitlePolicy.CANCEL_WAIT_MILLIS) {
            titleJob.join()
            true
        } == true
        check(stopped) { "Background title generation is still stopping. Please try again." }
    }

    private companion object {
        const val MAX_TRACKED_GENERATIONS = 10
    }
}

// Token counts from the SDK event bus when the result proto omits them.
private data class SdkGenerationMetrics(
    val inputTokens: Int,
    val outputTokens: Int,
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
