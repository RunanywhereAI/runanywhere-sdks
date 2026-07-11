package com.runanywhere.runanywhereai.ui.screens.chat

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.rag.DocumentExtractor
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.launch

private enum class PendingAttachmentKind { IMAGE, DOCUMENT }

private data class PendingAttachment(
    val kind: PendingAttachmentKind,
    val uri: Uri,
    val name: String,
)

@Composable
fun ChatScreen(
    viewModel: ChatViewModel,
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
    var pendingAttachment by remember { mutableStateOf<PendingAttachment?>(null) }
    var showImageModelSheet by remember { mutableStateOf(false) }
    var showDocumentIndexSheet by remember { mutableStateOf(false) }
    var showDocumentAnswerSheet by remember { mutableStateOf(false) }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        pendingAttachment = PendingAttachment(
            kind = PendingAttachmentKind.IMAGE,
            uri = uri,
            name = displayName(context, uri) ?: "Selected image",
        )
    }
    val documentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        pendingAttachment = PendingAttachment(
            kind = PendingAttachmentKind.DOCUMENT,
            uri = uri,
            name = displayName(context, uri) ?: "Selected document",
        )
    }

    fun sendPendingAttachment(attachment: PendingAttachment) {
        if (viewModel.isBusy) return
        when (attachment.kind) {
            PendingAttachmentKind.IMAGE -> {
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
            PendingAttachmentKind.DOCUMENT -> {
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

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .imePadding(),
            ) {
                AnimatedVisibility(
                    visible = messages.isEmpty(),
                    enter = fadeIn() + expandVertically(),
                    exit = fadeOut() + shrinkVertically(),
                ) {
                    PromptSuggestions(
                        toolsEnabled = viewModel.toolsEnabled,
                        loraActive = GlobalState.lora.isActive,
                        onSelect = viewModel::sendPrompt,
                        modifier = Modifier.padding(bottom = dimens.spacingSm),
                    )
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
                        isGenerating = viewModel.isGenerating,
                        isStopping = viewModel.isStopping,
                        onStop = viewModel::stop,
                        toolsEnabled = viewModel.toolsEnabled,
                        toolsUnavailableMessage = viewModel.toolsUnavailableMessage,
                        onToggleTools = viewModel::toggleTools,
                        onAttachDocument = { documentPicker.launch(DocumentExtractor.acceptedMimeTypes) },
                        onAttachImage = { imagePicker.launch("image/*") },
                        onOpenLive = onOpenVision,
                        onOpenTalk = onOpenVoice,
                        onOpenAdvanced = onOpenAdvanced,
                        modifier = Modifier.widthIn(max = dimens.contentMaxWidth),
                        pendingAttachment = pendingAttachment?.toComposerAttachment(),
                        onClearAttachment = { pendingAttachment = null },
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

    if (showImageModelSheet) {
        ModelSelectionSheet(viewModel = imageModelVm, onDismiss = { showImageModelSheet = false })
    }
    if (showDocumentIndexSheet) {
        ModelSelectionSheet(viewModel = documentIndexVm, onDismiss = { showDocumentIndexSheet = false })
    }
    if (showDocumentAnswerSheet) {
        ModelSelectionSheet(viewModel = documentAnswerVm, onDismiss = { showDocumentAnswerSheet = false })
    }
}

private fun ModelSelectionViewModel.readySelectedModel(): RAModelInfo? {
    val selected = state.currentModelId
        ?.let { id -> state.models.firstOrNull { it.id == id && isReady(it) } }
    return selected ?: state.models.firstOrNull { isReady(it) }
}

private fun PendingAttachment.toComposerAttachment(): ComposerAttachment =
    when (kind) {
        PendingAttachmentKind.IMAGE -> ComposerAttachment(
            name = name,
            description = "Ask about this image",
            icon = RACIcons.Outline.Eye,
        )
        PendingAttachmentKind.DOCUMENT -> ComposerAttachment(
            name = name,
            description = "Ask with sources from this document",
            icon = RACIcons.Outline.FileText,
        )
    }

private fun displayName(context: Context, uri: Uri): String? =
    context.contentResolver
        .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (cursor.moveToFirst() && index >= 0) cursor.getString(index)?.takeIf { it.isNotBlank() } else null
        }
