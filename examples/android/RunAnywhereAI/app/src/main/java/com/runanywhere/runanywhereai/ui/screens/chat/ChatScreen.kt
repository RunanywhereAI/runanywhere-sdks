package com.runanywhere.runanywhereai.ui.screens.chat

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.rag.DocumentExtractor
import com.runanywhere.runanywhereai.ui.components.WebSearchDisclosureDialog
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ChatScreen(
    viewModel: ChatViewModel,
    onOpenModels: () -> Unit,
    onOpenVision: () -> Unit,
    onOpenVoice: () -> Unit,
    onOpenAdvanced: () -> Unit,
) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val messages = viewModel.messages
    val imageModelVm: ModelSelectionViewModel =
        viewModel(key = "chat-vlm-model", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.VLM))
    val documentIndexVm: ModelSelectionViewModel =
        viewModel(key = "chat-rag-index-model", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.RAG_EMBEDDING))
    val documentAnswerVm: ModelSelectionViewModel =
        viewModel(key = "chat-rag-answer-model", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.RAG_LLM))
    val composerFocus = remember { FocusRequester() }
    var pendingAttachment by remember { mutableStateOf<StagedAttachment?>(null) }
    // Why the last file was refused. Held next to the composer rather than raised as a dialog: the
    // user is mid-compose, and the fix is to pick a different file, not to acknowledge an error.
    var attachmentRejection by remember { mutableStateOf<String?>(null) }
    var showImageModelSheet by remember { mutableStateOf(false) }
    var showDocumentIndexSheet by remember { mutableStateOf(false) }
    var showDocumentAnswerSheet by remember { mutableStateOf(false) }

    // The single funnel for every way a file can arrive, so a picker that was told to return one
    // type is checked exactly as strictly as one that was not.
    fun stageAttachment(kind: ComposerAttachmentKind, uri: Uri) {
        val rejection = ComposerAttachmentPolicy.reasonToReject(context, kind, uri)
        if (rejection != null) {
            attachmentRejection = rejection
            return
        }
        attachmentRejection = null
        pendingAttachment = StagedAttachment(
            kind = kind,
            uri = uri,
            name = ComposerAttachmentPolicy.displayName(context, kind, uri),
        )
    }

    // The Android photo picker, not ACTION_GET_CONTENT: it needs no storage permission, shows only
    // images, and on devices without the system picker the Compat contract falls back on its own.
    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        uri?.let { stageAttachment(ComposerAttachmentKind.IMAGE, it) }
    }
    val documentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { stageAttachment(ComposerAttachmentKind.DOCUMENT, it) }
    }

    fun sendPendingAttachment(attachment: StagedAttachment) {
        if (viewModel.isBusy) return
        when (attachment.kind) {
            ComposerAttachmentKind.IMAGE -> {
                val imageModel = imageModelVm.readySelectedModel()
                if (imageModel == null) {
                    showImageModelSheet = true
                    return
                }
                scope.launch {
                    if (imageModelVm.state.currentModelId != imageModel.id) {
                        val loaded = imageModelVm.select(imageModel)
                        if (!loaded) {
                            showImageModelSheet = true
                            return@launch
                        }
                    }
                    pendingAttachment = null
                    viewModel.sendImage(attachment.uri, loadedModel = imageModel)
                }
            }
            ComposerAttachmentKind.DOCUMENT -> {
                val indexModel = documentIndexVm.readySelectedModel()
                val answerModel = documentAnswerVm.readySelectedModel()
                when {
                    indexModel == null -> showDocumentIndexSheet = true
                    answerModel == null -> showDocumentAnswerSheet = true
                    else -> {
                        pendingAttachment = null
                        viewModel.sendDocument(
                            uri = attachment.uri,
                            embeddingModel = indexModel,
                            answerModel = answerModel,
                        )
                    }
                }
            }
        }
    }

    fun submitComposer() {
        val attachment = pendingAttachment
        if (attachment == null) {
            viewModel.send()
        } else if (!viewModel.isBusy) {
            sendPendingAttachment(attachment)
        }
    }

    // A suggestion chip is the launch screen's most prominent affordance, so it
    // cannot fail quietly. If nothing can answer it yet, the prompt still lands
    // in the composer (nothing typed is lost) and the model picker opens — the
    // one action that unblocks it. Mirrors iOS `sendImageQuestion`, which opens
    // the vision picker rather than returning when no model is ready.
    fun submitSuggestion(prompt: String) {
        if (!viewModel.sendPrompt(prompt)) onOpenModels()
    }

    var autoFollow by remember { mutableStateOf(true) }

    val atBottom by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull()
            last == null || (
                last.index == info.totalItemsCount - 1 &&
                    last.offset + last.size <= info.viewportEndOffset - info.afterContentPadding + 2
            )
        }
    }

    val scrollConnection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (available.y > 0.5f) autoFollow = false
                return Offset.Zero
            }
        }
    }

    LaunchedEffect(atBottom) {
        if (atBottom) autoFollow = true
    }

    LaunchedEffect(messages.size, messages.lastOrNull()?.text) {
        if (autoFollow && messages.isNotEmpty()) {
            listState.scrollToItem(messages.lastIndex, Int.MAX_VALUE)
        }
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val imeBottom = WindowInsets.ime.getBottom(density)
        val imeIntersectsWindow = WindowInsets.isImeVisible && imeBottom > 0
        val visibleChatHeight = (maxHeight - with(density) { imeBottom.toDp() }).coerceAtLeast(0.dp)
        // A short landscape viewport cannot fit status rows plus the editor above the IME.
        // Compact only when the measured IME-safe height is below three touch targets.
        val useCompactComposer =
            imeIntersectsWindow && visibleChatHeight < dimens.inputBarMinHeight * 3

        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            bottomBar = {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .imePadding()
                        .padding(bottom = if (useCompactComposer) dimens.spacingLg else 0.dp),
                ) {
                    if (!imeIntersectsWindow) {
                        AnimatedVisibility(
                            visible = messages.isEmpty(),
                            enter = fadeIn() + expandVertically(),
                            exit = fadeOut() + shrinkVertically(),
                        ) {
                            PromptSuggestions(
                                toolsEnabled = viewModel.toolsEnabled,
                                loraActive = GlobalState.lora.isActive,
                                onSelect = ::submitSuggestion,
                                modifier = Modifier.padding(bottom = dimens.spacingSm),
                            )
                        }
                    }
                    Box(
                        modifier = Modifier.fillMaxWidth(),
                        contentAlignment = Alignment.BottomCenter,
                    ) {
                        ChatInputBar(
                            input = viewModel.input,
                            onInputChange = viewModel::onInputChange,
                            onSend = ::submitComposer,
                            canSend = viewModel.canSend || (pendingAttachment != null && !viewModel.isBusy),
                            blockedReason = viewModel.sendBlockedReason,
                            onResolveBlocked = onOpenModels,
                            isGenerating = viewModel.isGenerating,
                            isStopping = viewModel.isStopping,
                            onStop = viewModel::stop,
                            toolsEnabled = viewModel.toolsEnabled,
                            toolsUnavailableMessage = viewModel.toolsUnavailableMessage,
                            onToggleTools = viewModel::toggleTools,
                            onAttachDocument = { documentPicker.launch(DocumentExtractor.acceptedMimeTypes) },
                            onAttachImage = {
                                imagePicker.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                                )
                            },
                            onOpenLive = onOpenVision,
                            onOpenTalk = onOpenVoice,
                            onOpenAdvanced = onOpenAdvanced,
                            onToggleThinking = viewModel::toggleThinking,
                            thinkingEnabled = viewModel.thinkingEnabled,
                            thinkingSupported = viewModel.thinkingSupported,
                            modifier = Modifier.widthIn(max = dimens.contentMaxWidth),
                            pendingAttachment = pendingAttachment?.toComposerAttachment(),
                            onClearAttachment = {
                                pendingAttachment = null
                                attachmentRejection = null
                            },
                            attachmentRejection = attachmentRejection,
                            onDismissAttachmentRejection = { attachmentRejection = null },
                            compact = useCompactComposer,
                            focusRequester = composerFocus,
                        )
                    }
                }
            },
        ) { innerPadding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .nestedScroll(scrollConnection),
                contentAlignment = Alignment.TopCenter,
            ) {
                ChatMessageList(
                    messages = messages,
                    listState = listState,
                    modifier = Modifier
                        .fillMaxSize()
                        .widthIn(max = dimens.contentMaxWidth),
                    isGenerating = viewModel.isGenerating,
                    // The empty transcript is the app's first screen, so it carries
                    // the one action that unblocks everything else when no model is
                    // resident yet.
                    hasModel = viewModel.hasUsableModel,
                    onChooseModel = onOpenModels,
                    // Withheld while a turn is in flight, mirroring iOS
                    // `ChatMessageListView.actions(for:)`: every one of these
                    // renumbers the transcript the running stream is indexed
                    // against. Copy stays, since the row owns it and it mutates
                    // nothing.
                    actions = if (viewModel.isBusy) {
                        ChatMessageActions()
                    } else {
                        ChatMessageActions(
                            onRegenerate = viewModel::regenerateReply,
                            onEdit = { index ->
                                viewModel.editQuestion(index)
                                // The question lands in the composer; taking focus
                                // with it is what makes this an edit rather than a
                                // puzzle.
                                composerFocus.requestFocus()
                            },
                            onDelete = viewModel::deleteMessage,
                        )
                    },
                )
                ScrollToBottomButton(
                    visible = !autoFollow && messages.isNotEmpty(),
                    onClick = {
                        autoFollow = true
                        scope.launch { listState.animateScrollToItem(messages.lastIndex, Int.MAX_VALUE) }
                    },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = dimens.spacingMd),
                )
            }
        }
    }

    if (showImageModelSheet) {
        ModelSelectionSheet(viewModel = imageModelVm, onDismiss = { showImageModelSheet = false })
    }
    if (showDocumentIndexSheet) {
        ModelSelectionSheet(viewModel = documentIndexVm, onDismiss = { showDocumentIndexSheet = false })
    }
    if (showDocumentAnswerSheet) {
        ModelSelectionSheet(viewModel = documentAnswerVm, onDismiss = { showDocumentAnswerSheet = false })
    }
    if (viewModel.showWebSearchDisclosure) {
        WebSearchDisclosureDialog(
            onAllow = viewModel::acceptWebSearchDisclosure,
            onDismiss = viewModel::dismissWebSearchDisclosure,
        )
    }
}

private fun ModelSelectionViewModel.readySelectedModel(): RAModelInfo? {
    val selected = state.currentModelId
        ?.let { id -> state.models.firstOrNull { it.id == id && isReady(it) } }
    return selected ?: state.models.firstOrNull { isReady(it) }
}

private fun StagedAttachment.toComposerAttachment(): ComposerAttachment =
    when (kind) {
        ComposerAttachmentKind.IMAGE -> ComposerAttachment(
            name = name,
            description = "Ask about this image",
            icon = RACIcons.Outline.Image,
        )
        ComposerAttachmentKind.DOCUMENT -> ComposerAttachment(
            name = name,
            description = "Ask with sources from this document",
            icon = RACIcons.Outline.FileText,
        )
    }
