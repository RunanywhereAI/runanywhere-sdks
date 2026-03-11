package com.runanywhere.runanywhereai.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.ChatEvent
import com.runanywhere.runanywhereai.models.ChatUiState
import com.runanywhere.runanywhereai.ui.components.ChatEmptyState
import com.runanywhere.runanywhereai.ui.components.ChatInputBar
import com.runanywhere.runanywhereai.ui.components.ChatMessageList
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.viewmodels.ChatViewModel
import kotlinx.coroutines.launch

@Composable
fun ChatScreen(
    chatViewModel: ChatViewModel = viewModel(),
) {
    val uiState by chatViewModel.uiState.collectAsStateWithLifecycle()
    var input by rememberSaveable { mutableStateOf("") }
    val listState = rememberLazyListState()

    val canSend by remember {
        derivedStateOf {
            input.isNotBlank() &&
                uiState is ChatUiState.Ready &&
                (uiState as? ChatUiState.Ready)?.isGenerating != true
        }
    }

    // Collect one-shot events
    LaunchedEffect(Unit) {
        chatViewModel.events.collect { event ->
            when (event) {
                is ChatEvent.ShowSnackbar -> {
                    // TODO: integrate with SnackbarHostState
                }
                is ChatEvent.ScrollToBottom -> {
                    val readyState = uiState as? ChatUiState.Ready
                    val messageCount = readyState?.messages?.size ?: 0
                    if (messageCount > 0) {
                        listState.animateScrollToItem(messageCount - 1)
                    }
                }
            }
        }
    }

    when (val state = uiState) {
        is ChatUiState.Loading -> {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }

        is ChatUiState.Ready -> {
            ChatReadyContent(
                state = state,
                input = input,
                onInputChange = { input = it },
                canSend = canSend,
                listState = listState,
                onSend = {
                    val text = input.trim()
                    if (text.isNotBlank()) {
                        chatViewModel.sendMessage(text)
                        input = ""
                    }
                },
                onCancel = { chatViewModel.cancelGeneration() },
                onPromptClick = { prompt -> input = prompt },
            )
        }

        is ChatUiState.Error -> {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "Something went wrong",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = state.message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun ChatReadyContent(
    state: ChatUiState.Ready,
    input: String,
    onInputChange: (String) -> Unit,
    canSend: Boolean,
    listState: LazyListState,
    onSend: () -> Unit,
    onCancel: () -> Unit,
    onPromptClick: (String) -> Unit,
) {
    val density = LocalDensity.current
    var inputBarHeightPx by remember { mutableIntStateOf(0) }
    val inputBarHeightDp = remember(inputBarHeightPx) {
        with(density) { inputBarHeightPx.toDp() }
    }

    val coroutineScope = rememberCoroutineScope()

    // Detect whether the user has scrolled away from the bottom
    val isAtBottom by remember {
        derivedStateOf {
            val layoutInfo = listState.layoutInfo
            val lastVisibleItem = layoutInfo.visibleItemsInfo.lastOrNull()
            lastVisibleItem == null || lastVisibleItem.index >= layoutInfo.totalItemsCount - 1
        }
    }

    // Auto-scroll to bottom during streaming
    LaunchedEffect(state.messages.size, state.isGenerating) {
        if (state.isGenerating && state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.size - 1)
        }
    }

    // Auto-scroll to bottom when keyboard opens so latest messages stay visible
    @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
    val isImeVisible = WindowInsets.isImeVisible
    LaunchedEffect(isImeVisible) {
        if (isImeVisible && isAtBottom && state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.size - 1)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // Content area — fills entire Box, padded at bottom so it doesn't sit behind input bar
        if (state.messages.isEmpty()) {
            ChatEmptyState(
                onPromptClick = onPromptClick,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = inputBarHeightDp),
            )
        } else {
            ChatMessageList(
                messages = state.messages,
                listState = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = inputBarHeightDp),
            )
        }

        // Scroll-to-bottom FAB — appears when user scrolls away from the bottom
        AnimatedVisibility(
            visible = !isAtBottom && state.messages.isNotEmpty(),
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 16.dp, bottom = inputBarHeightDp + 12.dp),
        ) {
            SmallFloatingActionButton(
                onClick = {
                    coroutineScope.launch {
                        if (state.messages.isNotEmpty()) {
                            listState.animateScrollToItem(state.messages.size - 1)
                        }
                    }
                },
                shape = CircleShape,
                containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                contentColor = MaterialTheme.colorScheme.onSurface,
            ) {
                Icon(
                    imageVector = RAIcons.ChevronDown,
                    contentDescription = "Scroll to bottom",
                    modifier = Modifier.size(20.dp),
                )
            }
        }

        // Input bar — pinned to bottom, moves up with keyboard via imePadding
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .imePadding(),
        ) {
            // Measure only the actual input bar height, not the IME padding
            Column(modifier = Modifier.onSizeChanged { inputBarHeightPx = it.height }) {
                HorizontalDivider(
                    thickness = 0.5.dp,
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                )

                ChatInputBar(
                    input = input,
                    onInputChange = onInputChange,
                    onSend = onSend,
                    canSend = canSend,
                    isGenerating = state.isGenerating,
                    onCancel = onCancel,
                )
            }
        }
    }
}
