package com.runanywhere.runanywhereai.ui.screens

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.runanywhere.runanywhereai.data.models.Message
import com.runanywhere.runanywhereai.llm.ModelInfo
import com.runanywhere.runanywhereai.viewmodels.ChatViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EnhancedChatScreen(
    conversationId: String? = null,
    viewModel: ChatViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val messages by viewModel.messages.collectAsState()
    val listState = rememberLazyListState()
    
    LaunchedEffect(conversationId) {
        conversationId?.let {
            viewModel.loadConversation(it)
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { 
                    Text(uiState.conversation?.title ?: "New Conversation")
                },
                actions = {
                    // Conversation actions
                    IconButton(onClick = { viewModel.showConversationInfo() }) {
                        Icon(Icons.Default.Info, "Conversation Info")
                    }
                    
                    IconButton(onClick = { viewModel.exportConversation() }) {
                        Icon(Icons.Default.Share, "Export")
                    }
                    
                    var showMenu by remember { mutableStateOf(false) }
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Default.MoreVert, "More")
                    }
                    
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Clear Conversation") },
                            onClick = {
                                viewModel.clearConversation()
                                showMenu = false
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Conversation Settings") },
                            onClick = {
                                viewModel.showSettings()
                                showMenu = false
                            }
                        )
                    }
                }
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
                state = listState,
                modifier = Modifier.weight(1f),
                reverseLayout = false,
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(
                    items = messages,
                    key = { it.id }
                ) { message ->
                    MessageBubble(
                        message = message,
                        onEdit = if (message.role == "user") {
                            { viewModel.editMessage(message.id) }
                        } else null,
                        onRegenerate = if (message.role == "assistant") {
                            { viewModel.regenerateResponse(message.id) }
                        } else null,
                        onBranch = { viewModel.branchConversation(message.id) }
                    )
                }
                
                // Typing indicator
                if (uiState.isGenerating) {
                    item {
                        TypingIndicator()
                    }
                }
            }
            
            // Input area
            ChatInputArea(
                value = uiState.currentInput,
                onValueChange = viewModel::updateInput,
                onSend = viewModel::sendMessage,
                isEnabled = !uiState.isGenerating,
                onImageAttach = viewModel::attachImage,
                supportsImages = uiState.currentModel?.framework?.name?.contains("GEMINI") ?: false
            )
            
            // Model selector chip
            if (uiState.showModelSelector) {
                ModelSelectorChip(
                    currentModel = uiState.currentModel,
                    onModelSelected = { framework, path -> 
                        viewModel.selectModel(framework, path)
                    }
                )
            }
        }
    }
}

@Composable
fun MessageBubble(
    message: Message,
    onEdit: (() -> Unit)? = null,
    onRegenerate: (() -> Unit)? = null,
    onBranch: () -> Unit
) {
    val isUser = message.role == "user"
    
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        Card(
            modifier = Modifier
                .widthIn(max = 320.dp)
                .animateContentSize(),
            colors = CardDefaults.cardColors(
                containerColor = if (isUser) 
                    MaterialTheme.colorScheme.primaryContainer
                else 
                    MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Column(
                modifier = Modifier.padding(12.dp)
            ) {
                // Message content
                Text(
                    text = message.content,
                    style = MaterialTheme.typography.bodyMedium
                )
                
                // Message metadata and actions
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = message.timestamp.toString(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    
                    Row {
                        if (onEdit != null) {
                            IconButton(
                                onClick = onEdit,
                                modifier = Modifier.size(20.dp)
                            ) {
                                Icon(
                                    Icons.Default.Edit,
                                    contentDescription = "Edit",
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                        
                        if (onRegenerate != null) {
                            IconButton(
                                onClick = onRegenerate,
                                modifier = Modifier.size(20.dp)
                            ) {
                                Icon(
                                    Icons.Default.Refresh,
                                    contentDescription = "Regenerate",
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                        
                        IconButton(
                            onClick = onBranch,
                            modifier = Modifier.size(20.dp)
                        ) {
                            Icon(
                                Icons.Default.Build, // Using Build as placeholder for CallSplit
                                contentDescription = "Branch",
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                }
                
                // Token count and generation time
                if (message.tokenCount > 0) {
                    Text(
                        text = "${message.tokenCount} tokens" + 
                               if (message.generationTimeMs != null) 
                                   " • ${message.generationTimeMs}ms" 
                               else "",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
fun TypingIndicator() {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.padding(16.dp)
    ) {
        repeat(3) { index ->
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .animateContentSize()
                    .background(
                        MaterialTheme.colorScheme.onSurfaceVariant,
                        CircleShape
                    )
            )
        }
    }
}

@Composable
fun ChatInputArea(
    value: String,
    onValueChange: (String) -> Unit,
    onSend: () -> Unit,
    isEnabled: Boolean,
    onImageAttach: (() -> Unit)? = null,
    supportsImages: Boolean = false
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        tonalElevation = 3.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            verticalAlignment = Alignment.Bottom
        ) {
            // Attachment button
            if (supportsImages && onImageAttach != null) {
                IconButton(onClick = onImageAttach) {
                    Icon(Icons.Default.Add, "Attach Image") // Using Add as placeholder for AttachFile
                }
            }
            
            // Text input
            OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text("Type a message...") },
                enabled = isEnabled,
                maxLines = 5,
                keyboardOptions = KeyboardOptions(
                    imeAction = ImeAction.Send
                ),
                keyboardActions = KeyboardActions(
                    onSend = { onSend() }
                )
            )
            
            // Send button
            IconButton(
                onClick = onSend,
                enabled = isEnabled && value.isNotBlank()
            ) {
                Icon(
                    Icons.Default.Send,
                    contentDescription = "Send",
                    tint = if (isEnabled && value.isNotBlank())
                        MaterialTheme.colorScheme.primary
                    else
                        MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
fun ModelSelectorChip(
    currentModel: ModelInfo?,
    onModelSelected: (framework: com.runanywhere.runanywhereai.llm.LLMFramework, path: String) -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp),
        tonalElevation = 1.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            horizontalArrangement = Arrangement.Center
        ) {
            if (currentModel != null) {
                AssistChip(
                    onClick = { /* TODO: Show model selector */ },
                    label = { 
                        Text("${currentModel.framework}: ${currentModel.name}")
                    },
                    leadingIcon = {
                        Icon(Icons.Default.Build, "Model") // Using Build as placeholder
                    }
                )
            } else {
                OutlinedButton(
                    onClick = { /* TODO: Show model selector */ }
                ) {
                    Text("Select a Model")
                }
            }
        }
    }
}