package com.runanywhere.run_anywhere_lora

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.sdk.temp.LoraAdapterEntry

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LoraScreen(viewModel: LoraViewModel = viewModel()) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scrollState = rememberScrollState()

    // Track pending LoRA file path for scale dialog
    var pendingLoraPath by remember { mutableStateOf<String?>(null) }
    var loraScale by remember { mutableFloatStateOf(1.0f) }

    // Download dialog visibility
    var showDownloadDialog by remember { mutableStateOf(false) }

    // My LoRAs dialog visibility
    var showMyLorasDialog by remember { mutableStateOf(false) }

    // Storage permission state
    var hasStoragePermission by remember {
        mutableStateOf(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Environment.isExternalStorageManager()
            } else {
                true
            }
        )
    }

    // Permission launcher for Android 11+
    val storagePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult(),
    ) {
        hasStoragePermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
    }

    // Legacy permission launcher for Android < 11
    val legacyPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted ->
        hasStoragePermission = granted
    }

    // File picker for model
    val modelFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        uri?.let { resolveFilePath(context, it) }?.let { path ->
            viewModel.loadModel(path)
        }
    }

    // File picker for LoRA adapter
    val loraFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        uri?.let { resolveFilePath(context, it) }?.let { path ->
            pendingLoraPath = path
        }
    }

    // Show errors as snackbar
    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    // Auto-scroll when answer updates
    LaunchedEffect(state.answer) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    // When download completes, show scale dialog
    LaunchedEffect(state.loraDownload.downloadedPath) {
        val path = state.loraDownload.downloadedPath
        if (path != null) {
            pendingLoraPath = path
            viewModel.clearDownloadState()
            showDownloadDialog = false
        }
    }

    // LoRA scale dialog
    if (pendingLoraPath != null) {
        LoraScaleDialog(
            filename = pendingLoraPath!!.substringAfterLast('/'),
            scale = loraScale,
            onScaleChange = { loraScale = it },
            onConfirm = {
                viewModel.loadLoraAdapter(pendingLoraPath!!, loraScale)
                pendingLoraPath = null
                loraScale = 1.0f
            },
            onDismiss = {
                pendingLoraPath = null
                loraScale = 1.0f
            },
        )
    }

    // Download dialog
    if (showDownloadDialog) {
        LoraDownloadDialog(
            catalogAdapters = state.catalogAdapters,
            loraDownloadState = state.loraDownload,
            modelDownloadState = state.modelDownload,
            modelLoaded = state.modelLoaded,
            onDownloadModel = { viewModel.downloadBaseModel() },
            onDownloadFromUrl = { url, name -> viewModel.downloadLoraFromUrl(url, name) },
            onDownloadFromCatalog = { entry -> viewModel.downloadLoraFromCatalog(entry) },
            onDismiss = {
                showDownloadDialog = false
                viewModel.clearDownloadState()
            },
        )
    }

    // My LoRAs dialog
    if (showMyLorasDialog) {
        DownloadedLorasDialog(
            downloadedAdapters = state.downloadedAdapters,
            modelLoaded = state.modelLoaded,
            onLoadAdapter = { adapter ->
                pendingLoraPath = adapter.localPath
                showMyLorasDialog = false
            },
            onDismiss = { showMyLorasDialog = false },
        )
    }

    fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:${context.packageName}")
            }
            storagePermissionLauncher.launch(intent)
        } else {
            legacyPermissionLauncher.launch(android.Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("RunAnywhere LoRA") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
                actions = {
                    IconButton(onClick = { showMyLorasDialog = true }) {
                        BadgedBox(
                            badge = {
                                if (state.downloadedAdapters.isNotEmpty()) {
                                    Badge { Text("${state.downloadedAdapters.size}") }
                                }
                            },
                        ) {
                            Icon(
                                Icons.Default.Inventory2,
                                contentDescription = "My LoRAs",
                                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        }
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .imePadding(),
        ) {
            // Status section
            StatusSection(state)

            // Response card (fills available space)
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(horizontal = 12.dp, vertical = 4.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                ),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(12.dp),
                ) {
                    if (state.answer.isEmpty() && !state.isGenerating) {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = if (state.modelLoaded) {
                                    "Ask a question below"
                                } else {
                                    "Load a model to get started"
                                },
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                            )
                        }
                    } else {
                        SelectionContainer(
                            modifier = Modifier
                                .weight(1f)
                                .verticalScroll(scrollState),
                        ) {
                            Text(
                                text = state.answer,
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        // Metrics row
                        state.metrics?.let { metrics ->
                            HorizontalDivider(
                                modifier = Modifier.padding(vertical = 6.dp),
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Text(
                                    text = "%.1f tok/s".format(metrics.tokensPerSecond),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                )
                                Text(
                                    text = "${metrics.totalTokens} tokens",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                )
                                Text(
                                    text = "%.1fs".format(metrics.latencyMs / 1000.0),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                )
                            }
                        }

                        // Loading indicator
                        if (state.isGenerating && state.answer.isEmpty()) {
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxWidth(),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator(modifier = Modifier.size(32.dp))
                            }
                        }
                    }
                }
            }

            // Bottom section: action chips + input
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                // Action chips row
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    AssistChip(
                        onClick = {
                            if (!hasStoragePermission) {
                                requestStoragePermission()
                            } else {
                                modelFilePicker.launch(arrayOf("*/*"))
                            }
                        },
                        label = { Text("Model", maxLines = 1) },
                        leadingIcon = {
                            if (state.modelLoading) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(AssistChipDefaults.IconSize),
                                    strokeWidth = 2.dp,
                                )
                            } else {
                                Icon(
                                    Icons.Default.FolderOpen,
                                    contentDescription = "Load model",
                                    modifier = Modifier.size(AssistChipDefaults.IconSize),
                                )
                            }
                        },
                        enabled = !state.modelLoading,
                    )

                    AssistChip(
                        onClick = {
                            if (!hasStoragePermission) {
                                requestStoragePermission()
                            } else {
                                loraFilePicker.launch(arrayOf("*/*"))
                            }
                        },
                        label = { Text("LoRA", maxLines = 1) },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Add,
                                contentDescription = "Load LoRA",
                                modifier = Modifier.size(AssistChipDefaults.IconSize),
                            )
                        },
                        enabled = state.modelLoaded && !state.isGenerating,
                    )

                    AssistChip(
                        onClick = { showDownloadDialog = true },
                        label = { Text("Download", maxLines = 1) },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Download,
                                contentDescription = "Download LoRA",
                                modifier = Modifier.size(AssistChipDefaults.IconSize),
                            )
                        },
                        enabled = !state.isGenerating,
                    )

                    AnimatedVisibility(visible = state.loraAdapters.isNotEmpty()) {
                        AssistChip(
                            onClick = { viewModel.clearLoraAdapters() },
                            label = { Text("Clear", maxLines = 1) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Clear,
                                    contentDescription = "Clear LoRA",
                                    modifier = Modifier.size(AssistChipDefaults.IconSize),
                                )
                            },
                            enabled = !state.isGenerating,
                        )
                    }
                }

                // Sample prompt chips
                if (state.samplePrompts.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        for (prompt in state.samplePrompts) {
                            SuggestionChip(
                                onClick = { viewModel.selectSamplePrompt(prompt) },
                                label = {
                                    Text(
                                        text = prompt,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                },
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(4.dp))

                // Input row
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Bottom,
                ) {
                    OutlinedTextField(
                        value = state.question,
                        onValueChange = { viewModel.updateQuestion(it) },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("Ask a question...") },
                        maxLines = 3,
                        shape = MaterialTheme.shapes.medium,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    IconButton(
                        onClick = {
                            if (state.isGenerating) {
                                viewModel.cancelGeneration()
                            } else {
                                viewModel.askQuestion()
                            }
                        },
                        enabled = state.modelLoaded,
                    ) {
                        Icon(
                            imageVector = if (state.isGenerating) Icons.Default.Stop else Icons.AutoMirrored.Filled.Send,
                            contentDescription = if (state.isGenerating) "Stop" else "Send",
                            tint = if (state.modelLoaded) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StatusSection(state: LoraUiState) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
    ) {
        // Model status
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "Model: ",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (state.modelLoading) {
                Text(
                    text = "Loading...",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            } else if (state.modelPath != null) {
                Text(
                    text = state.modelPath.substringAfterLast('/'),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            } else {
                Text(
                    text = "None",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                )
            }
        }

        // LoRA adapters status
        if (state.loraAdapters.isNotEmpty()) {
            for (adapter in state.loraAdapters) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "LoRA: ",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = "${adapter.path.substringAfterLast('/')} x${adapter.scale}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.secondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun LoraScaleDialog(
    filename: String,
    scale: Float,
    onScaleChange: (Float) -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Load LoRA Adapter") },
        text = {
            Column {
                Text(
                    text = filename,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Scale: %.2f".format(scale),
                    style = MaterialTheme.typography.labelMedium,
                )
                Slider(
                    value = scale,
                    onValueChange = onScaleChange,
                    valueRange = 0f..2f,
                    steps = 19,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text("Load") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

@Composable
private fun LoraDownloadDialog(
    catalogAdapters: List<LoraAdapterEntry>,
    loraDownloadState: LoraDownloadUiState,
    modelDownloadState: ModelDownloadUiState,
    modelLoaded: Boolean,
    onDownloadModel: () -> Unit,
    onDownloadFromUrl: (String, String) -> Unit,
    onDownloadFromCatalog: (LoraAdapterEntry) -> Unit,
    onDismiss: () -> Unit,
) {
    var selectedLoraTab by remember { mutableIntStateOf(0) }
    var urlInput by remember { mutableStateOf("") }
    var nameInput by remember { mutableStateOf("") }

    val isAnyDownloading = loraDownloadState.isDownloading || modelDownloadState.isDownloading

    AlertDialog(
        onDismissRequest = { if (!isAnyDownloading) onDismiss() },
        title = { Text("Downloads") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
            ) {
                // --- Section 1: Model ---
                Text(
                    text = "Model",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.height(8.dp))

                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    ),
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                    ) {
                        Text(
                            text = BASE_MODEL.name,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = BASE_MODEL.description,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        )
                        Spacer(modifier = Modifier.height(8.dp))

                        when {
                            modelDownloadState.isDownloading -> {
                                Text(
                                    text = "Downloading... ${(modelDownloadState.progress * 100).toInt()}%",
                                    style = MaterialTheme.typography.bodySmall,
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                LinearProgressIndicator(
                                    progress = { modelDownloadState.progress },
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                            modelDownloadState.error != null -> {
                                Text(
                                    text = modelDownloadState.error,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.error,
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                TextButton(onClick = onDownloadModel) {
                                    Text("Retry")
                                }
                            }
                            modelLoaded || modelDownloadState.isDownloaded -> {
                                Text(
                                    text = if (modelLoaded) "Model loaded" else "Downloaded",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                            else -> {
                                TextButton(onClick = onDownloadModel) {
                                    Icon(
                                        Icons.Default.Download,
                                        contentDescription = null,
                                        modifier = Modifier.size(18.dp),
                                    )
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("Download")
                                }
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))
                HorizontalDivider()
                Spacer(modifier = Modifier.height(12.dp))

                // --- Section 2: LoRA Adapter ---
                Text(
                    text = "LoRA Adapter",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.height(8.dp))

                TabRow(selectedTabIndex = selectedLoraTab) {
                    Tab(
                        selected = selectedLoraTab == 0,
                        onClick = { selectedLoraTab = 0 },
                        text = { Text("Catalog") },
                    )
                    Tab(
                        selected = selectedLoraTab == 1,
                        onClick = { selectedLoraTab = 1 },
                        text = { Text("URL") },
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                // LoRA download progress
                if (loraDownloadState.isDownloading) {
                    Column {
                        Text(
                            text = "Downloading... ${(loraDownloadState.progress * 100).toInt()}%",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        LinearProgressIndicator(
                            progress = { loraDownloadState.progress },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                } else if (loraDownloadState.error != null) {
                    Text(
                        text = loraDownloadState.error,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                }

                if (!loraDownloadState.isDownloading) {
                    when (selectedLoraTab) {
                        0 -> {
                            if (catalogAdapters.isEmpty()) {
                                Text(
                                    text = "No catalog adapters available",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                                )
                            } else {
                                Column(
                                    verticalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    for (entry in catalogAdapters) {
                                        CatalogAdapterRow(
                                            entry = entry,
                                            onDownload = { onDownloadFromCatalog(entry) },
                                        )
                                    }
                                }
                            }
                        }
                        1 -> {
                            OutlinedTextField(
                                value = urlInput,
                                onValueChange = { urlInput = it },
                                label = { Text("LoRA URL") },
                                placeholder = { Text("https://.../.gguf") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            OutlinedTextField(
                                value = nameInput,
                                onValueChange = { nameInput = it },
                                label = { Text("Filename") },
                                placeholder = { Text("my-lora") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            TextButton(
                                onClick = {
                                    if (urlInput.isNotBlank() && nameInput.isNotBlank()) {
                                        onDownloadFromUrl(urlInput.trim(), nameInput.trim())
                                    }
                                },
                                enabled = urlInput.isNotBlank() && nameInput.isNotBlank(),
                            ) {
                                Text("Download")
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            if (!isAnyDownloading) {
                TextButton(onClick = onDismiss) { Text("Close") }
            }
        },
    )
}

@Composable
private fun DownloadedLorasDialog(
    downloadedAdapters: List<DownloadedLoraAdapter>,
    modelLoaded: Boolean,
    onLoadAdapter: (DownloadedLoraAdapter) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("My LoRAs") },
        text = {
            if (downloadedAdapters.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No downloaded adapters yet.\nUse the Download button to get started.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                    )
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (adapter in downloadedAdapters) {
                        DownloadedAdapterRow(
                            adapter = adapter,
                            modelLoaded = modelLoaded,
                            onLoad = { onLoadAdapter(adapter) },
                        )
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DownloadedAdapterRow(
    adapter: DownloadedLoraAdapter,
    modelLoaded: Boolean,
    onLoad: () -> Unit,
) {
    val template = loraPromptTemplates[adapter.id]
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = adapter.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.weight(1f),
                )
                TextButton(
                    onClick = onLoad,
                    enabled = modelLoaded,
                ) {
                    Text("Load")
                }
            }

            if (template != null) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    for (prompt in template.samplePrompts) {
                        SuggestionChip(
                            onClick = { },
                            label = {
                                Text(
                                    text = prompt,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CatalogAdapterRow(
    entry: LoraAdapterEntry,
    onDownload: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onDownload),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = entry.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    text = entry.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
            }
            Icon(
                Icons.Default.Download,
                contentDescription = "Download",
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

/**
 * Resolve a content URI to a real file path.
 * With MANAGE_EXTERNAL_STORAGE, we can access files directly.
 */
private fun resolveFilePath(context: android.content.Context, uri: Uri): String? {
    // Try to get the file path from the URI directly
    if (uri.scheme == "file") {
        return uri.path
    }

    // For content:// URIs, try to resolve via cursor
    try {
        context.contentResolver.query(uri, arrayOf("_data"), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex("_data")
                if (idx >= 0) {
                    val path = cursor.getString(idx)
                    if (path != null) return path
                }
            }
        }
    } catch (_: Exception) {
        // Fall through to copy approach
    }

    // Fallback: copy to app cache and return that path
    try {
        val filename = uri.lastPathSegment?.substringAfterLast('/') ?: "model.gguf"
        val cacheFile = java.io.File(context.cacheDir, filename)
        context.contentResolver.openInputStream(uri)?.use { input ->
            cacheFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return cacheFile.absolutePath
    } catch (e: Exception) {
        android.util.Log.e("LoraScreen", "Failed to resolve file path: ${e.message}", e)
        return null
    }
}
