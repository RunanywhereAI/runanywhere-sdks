package com.runanywhere.runanywhereai.presentation.chat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.runanywhere.runanywhereai.presentation.chat.components.MessageBubble
import com.runanywhere.runanywhereai.presentation.chat.components.MessageInput
import kotlinx.coroutines.launch

/**
 * Chat screen for text-based conversation with the AI assistant
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    viewModel: ChatViewModel = hiltViewModel()
) {
    val messages by viewModel.messages.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    var messageText by remember { mutableStateOf("") }

    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // Auto-scroll to bottom when new messages arrive
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            scope.launch {
                listState.animateScrollToItem(messages.size - 1)
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("RunAnywhere Chat") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Messages list
            LazyColumn(
                modifier = Modifier.weight(1f),
                state = listState,
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (messages.isEmpty()) {
                    item {
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                            )
                        ) {
                            Column(
                                modifier = Modifier.padding(16.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    text = "Welcome to RunAnywhere AI!",
                                    style = MaterialTheme.typography.headlineSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    text = "Start a conversation by typing a message below.",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }

                items(
                    items = messages,
                    key = { it.id }
                ) { message ->
                    MessageBubble(
                        message = message,
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                if (isLoading) {
                    item {
                        Card(
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp
                                )
                                Spacer(modifier = Modifier.width(12.dp))
                                Text(\n                                    text = \"AI is thinking...\",\n                                    style = MaterialTheme.typography.bodyMedium\n                                )\n                            }\n                        }\n                    }\n                }\n            }\n            \n            // Error display\n            error?.let { errorMessage ->\n                Card(\n                    modifier = Modifier\n                        .fillMaxWidth()\n                        .padding(horizontal = 16.dp),\n                    colors = CardDefaults.cardColors(\n                        containerColor = MaterialTheme.colorScheme.errorContainer\n                    )\n                ) {\n                    Row(\n                        modifier = Modifier.padding(12.dp),\n                        horizontalArrangement = Arrangement.SpaceBetween,\n                        verticalAlignment = Alignment.CenterVertically\n                    ) {\n                        Text(\n                            text = errorMessage,\n                            style = MaterialTheme.typography.bodySmall,\n                            color = MaterialTheme.colorScheme.onErrorContainer,\n                            modifier = Modifier.weight(1f)\n                        )\n                        TextButton(\n                            onClick = { viewModel.clearError() }\n                        ) {\n                            Text(\"Dismiss\")\n                        }\n                    }\n                }\n            }\n            \n            // Message input\n            MessageInput(\n                text = messageText,\n                onTextChange = { messageText = it },\n                onSendMessage = {\n                    if (messageText.isNotBlank()) {\n                        viewModel.sendMessage(messageText)\n                        messageText = \"\"\n                    }\n                },\n                enabled = !isLoading,\n                modifier = Modifier\n                    .fillMaxWidth()\n                    .padding(16.dp)\n            )\n        }\n    }\n}
