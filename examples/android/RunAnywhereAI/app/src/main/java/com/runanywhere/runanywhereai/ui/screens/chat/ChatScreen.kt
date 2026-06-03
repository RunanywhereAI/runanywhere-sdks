package com.runanywhere.runanywhereai.ui.screens.chat

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
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import kotlinx.coroutines.launch

@Composable
fun ChatScreen(viewModel: ChatViewModel) {
    val dimens = LocalDimens.current
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val messages = viewModel.messages

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
                        onSend = viewModel::send,
                        canSend = viewModel.canSend,
                        isGenerating = viewModel.isGenerating,
                        onStop = viewModel::stop,
                        toolsEnabled = viewModel.toolsEnabled,
                        onToggleTools = viewModel::toggleTools,
                        modifier = Modifier.widthIn(max = dimens.contentMaxWidth),
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
