package com.runanywhere.agent.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.runanywhere.agent.AgentViewModel
import com.runanywhere.agent.ui.components.ModelSelector
import com.runanywhere.agent.ui.components.ProviderBadge
import com.runanywhere.agent.ui.components.StatusBadge

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentScreen(viewModel: AgentViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val lifecycleOwner = LocalLifecycleOwner.current
    val context = LocalContext.current

    var hasMicPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED
        )
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        hasMicPermission = isGranted
        if (isGranted) {
            viewModel.loadSTTModelIfNeeded()
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.checkServiceStatus()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("RunAnywhere Agent") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Service Status
            if (!uiState.isServiceEnabled) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Accessibility service not enabled",
                            color = MaterialTheme.colorScheme.onErrorContainer
                        )
                        Button(onClick = { viewModel.openAccessibilitySettings() }) {
                            Text("Enable")
                        }
                    }
                }
            }

            // Model Selector + Voice Mode + VLM Toggle
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                ModelSelector(
                    models = uiState.availableModels.map { it.name },
                    selectedIndex = uiState.selectedModelIndex,
                    onSelect = viewModel::setModel,
                    enabled = uiState.status != AgentViewModel.Status.RUNNING,
                    modifier = Modifier.weight(1f)
                )

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = "Voice",
                        style = MaterialTheme.typography.labelMedium
                    )
                    Switch(
                        checked = uiState.isVoiceMode,
                        onCheckedChange = { viewModel.toggleVoiceMode() },
                        enabled = uiState.status != AgentViewModel.Status.RUNNING
                    )
                }
            }

            // VLM Model Status
            VLMModelCard(
                isVLMLoaded = uiState.isVLMLoaded,
                isVLMDownloading = uiState.isVLMDownloading,
                vlmDownloadProgress = uiState.vlmDownloadProgress,
                isAgentRunning = uiState.status == AgentViewModel.Status.RUNNING,
                onLoadVLM = viewModel::loadVLMModel
            )

            if (uiState.isVoiceMode) {
                // ===== Voice Mode UI =====
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    val voiceStatusText = when {
                        uiState.status == AgentViewModel.Status.RUNNING -> "Working..."
                        uiState.isTranscribing -> "Transcribing..."
                        uiState.isRecording -> "Listening..."
                        uiState.isSTTModelLoading -> "Loading voice model..."
                        uiState.goal.isNotBlank() && uiState.status == AgentViewModel.Status.DONE -> "Done: \"${uiState.goal}\""
                        uiState.goal.isNotBlank() -> "\"${uiState.goal}\""
                        else -> "Tap the mic to speak"
                    }
                    Text(
                        text = voiceStatusText,
                        style = MaterialTheme.typography.bodyLarge,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )

                    val micEnabled = !uiState.isTranscribing &&
                            !uiState.isSTTModelLoading &&
                            uiState.status != AgentViewModel.Status.RUNNING

                    FilledIconButton(
                        onClick = {
                            if (uiState.isRecording) {
                                viewModel.stopRecordingAndTranscribe()
                            } else {
                                if (!hasMicPermission) {
                                    permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                    return@FilledIconButton
                                }
                                if (!uiState.isSTTModelLoaded && !uiState.isSTTModelLoading) {
                                    viewModel.loadSTTModelIfNeeded()
                                }
                                if (uiState.isSTTModelLoaded) {
                                    viewModel.startRecording()
                                }
                            }
                        },
                        enabled = micEnabled,
                        modifier = Modifier.size(80.dp),
                        shape = CircleShape,
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = if (uiState.isRecording)
                                MaterialTheme.colorScheme.error
                            else
                                MaterialTheme.colorScheme.primary
                        )
                    ) {
                        when {
                            uiState.isTranscribing -> CircularProgressIndicator(
                                modifier = Modifier.size(32.dp),
                                strokeWidth = 3.dp,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                            uiState.isRecording -> Icon(
                                imageVector = Icons.Rounded.Stop,
                                contentDescription = "Stop recording",
                                modifier = Modifier.size(36.dp),
                                tint = MaterialTheme.colorScheme.onError
                            )
                            else -> Icon(
                                imageVector = Icons.Rounded.Mic,
                                contentDescription = "Start recording",
                                modifier = Modifier.size(36.dp),
                                tint = MaterialTheme.colorScheme.onPrimary
                            )
                        }
                    }

                    if (uiState.isSTTModelLoading) {
                        LinearProgressIndicator(
                            progress = { uiState.sttDownloadProgress },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 32.dp),
                        )
                    }

                    if (uiState.status == AgentViewModel.Status.RUNNING) {
                        Button(
                            onClick = viewModel::stopAgent,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.error
                            ),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("Stop Agent")
                        }
                    }
                }
            } else {
                // ===== Text Mode UI =====

                OutlinedTextField(
                    value = uiState.goal,
                    onValueChange = viewModel::setGoal,
                    label = { Text("Enter your goal") },
                    placeholder = { Text("e.g., 'Play lofi music on YouTube'") },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = uiState.status != AgentViewModel.Status.RUNNING &&
                            !uiState.isRecording && !uiState.isTranscribing,
                    minLines = 2,
                    maxLines = 4,
                    trailingIcon = {
                        MicButton(
                            isRecording = uiState.isRecording,
                            isTranscribing = uiState.isTranscribing,
                            isSTTModelLoading = uiState.isSTTModelLoading,
                            isAgentRunning = uiState.status == AgentViewModel.Status.RUNNING,
                            onClick = {
                                if (uiState.isRecording) {
                                    viewModel.stopRecordingAndTranscribe()
                                } else {
                                    if (!hasMicPermission) {
                                        permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                        return@MicButton
                                    }
                                    if (!uiState.isSTTModelLoaded && !uiState.isSTTModelLoading) {
                                        viewModel.loadSTTModelIfNeeded()
                                    }
                                    if (uiState.isSTTModelLoaded) {
                                        viewModel.startRecording()
                                    }
                                }
                            }
                        )
                    }
                )

                if (uiState.isSTTModelLoading) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        LinearProgressIndicator(
                            progress = { uiState.sttDownloadProgress },
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = "${(uiState.sttDownloadProgress * 100).toInt()}%",
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(
                        onClick = viewModel::startAgent,
                        modifier = Modifier.weight(1f),
                        enabled = uiState.status != AgentViewModel.Status.RUNNING &&
                                uiState.isServiceEnabled &&
                                uiState.goal.isNotBlank()
                    ) {
                        Text("Start Agent")
                    }

                    if (uiState.status == AgentViewModel.Status.RUNNING) {
                        Button(
                            onClick = viewModel::stopAgent,
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.error
                            )
                        ) {
                            Text("Stop")
                        }
                    }
                }
            }

            // Status + Provider Badges
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    StatusBadge(status = uiState.status)
                    if (uiState.status == AgentViewModel.Status.RUNNING) {
                        ProviderBadge(mode = uiState.providerMode)
                    }
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (uiState.logs.isNotEmpty()) {
                        TextButton(onClick = viewModel::copyLogsToClipboard) {
                            Text(if (uiState.logsCopied) "Copied!" else "Export")
                        }
                        TextButton(onClick = viewModel::clearLogs) {
                            Text("Clear Logs")
                        }
                    }
                }
            }

            // Live Thinking Overlay — shows streaming tokens while LLM is reasoning
            if (uiState.thinkingText.isNotEmpty()) {
                ThinkingPanel(
                    text = uiState.thinkingText,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 120.dp)
                )
            }

            // Log Output
            LogPanel(
                logs = uiState.logs,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            )
        }
    }
}

@Composable
private fun VLMModelCard(
    isVLMLoaded: Boolean,
    isVLMDownloading: Boolean,
    vlmDownloadProgress: Float,
    isAgentRunning: Boolean,
    onLoadVLM: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (isVLMLoaded)
                Color(0xFF198754).copy(alpha = 0.1f)
            else
                MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Visibility,
                    contentDescription = null,
                    tint = if (isVLMLoaded) Color(0xFF198754) else Color.Gray,
                    modifier = Modifier.size(20.dp)
                )
                Column {
                    Text(
                        text = if (isVLMLoaded) "VLM Ready" else "Vision Model",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (isVLMLoaded) Color(0xFF198754) else MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = "LFM2-VL 450M (~323 MB)",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }
            }

            if (!isVLMLoaded && !isVLMDownloading) {
                Button(
                    onClick = onLoadVLM,
                    enabled = !isAgentRunning,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                ) {
                    Text("Load", style = MaterialTheme.typography.labelSmall)
                }
            }

            if (isVLMDownloading) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    CircularProgressIndicator(
                        progress = { vlmDownloadProgress },
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp
                    )
                    Text(
                        text = "${(vlmDownloadProgress * 100).toInt()}%",
                        style = MaterialTheme.typography.labelSmall
                    )
                }
            }
        }
    }
}

@Composable
private fun MicButton(
    isRecording: Boolean,
    isTranscribing: Boolean,
    isSTTModelLoading: Boolean,
    isAgentRunning: Boolean,
    onClick: () -> Unit
) {
    IconButton(
        onClick = onClick,
        enabled = !isTranscribing && !isSTTModelLoading && !isAgentRunning
    ) {
        when {
            isTranscribing -> CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp
            )
            isSTTModelLoading -> CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.tertiary
            )
            isRecording -> Icon(
                imageVector = Icons.Rounded.Stop,
                contentDescription = "Stop recording",
                tint = MaterialTheme.colorScheme.error
            )
            else -> Icon(
                imageVector = Icons.Rounded.Mic,
                contentDescription = "Start recording",
                tint = MaterialTheme.colorScheme.primary
            )
        }
    }
}

/**
 * Shows streaming LLM tokens in real-time while the model is reasoning.
 * Styled in amber/yellow to visually distinguish from the completed log panel.
 */
@Composable
fun ThinkingPanel(
    text: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = Color(0xFF1A1200)),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.Top
        ) {
            Text(
                text = "▶ ",
                color = Color(0xFFFFD43B),
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace
            )
            Text(
                text = text,
                color = Color(0xFFFFD43B),
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                lineHeight = 16.sp,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
fun LogPanel(
    logs: List<String>,
    modifier: Modifier = Modifier
) {
    val listState = rememberLazyListState()

    LaunchedEffect(logs.size) {
        if (logs.isNotEmpty()) {
            listState.animateScrollToItem(logs.size - 1)
        }
    }

    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(
            containerColor = Color(0xFF1E1E1E)
        ),
        shape = RoundedCornerShape(8.dp)
    ) {
        if (logs.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "Agent logs will appear here",
                    color = Color.Gray
                )
            }
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(logs) { log ->
                    val color = when {
                        log.startsWith("ERROR") -> Color(0xFFFF6B6B)
                        log.startsWith("[LOCAL]") -> Color(0xFF69DB7C)
                        log.startsWith("[CLOUD]") -> Color(0xFF74C0FC)
                        log.startsWith("Step") -> Color(0xFF69DB7C)
                        log.contains("Downloading") -> Color(0xFF74C0FC)
                        log.contains("done", ignoreCase = true) -> Color(0xFF69DB7C)
                        else -> Color(0xFFADB5BD)
                    }
                    Text(
                        text = log,
                        color = color,
                        fontSize = 13.sp,
                        fontFamily = FontFamily.Monospace,
                        lineHeight = 18.sp
                    )
                }
            }
        }
    }
}
