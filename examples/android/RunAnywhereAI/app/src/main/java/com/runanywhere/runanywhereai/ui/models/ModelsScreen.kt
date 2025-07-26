package com.runanywhere.runanywhereai.ui.models

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.repository.DownloadProgress
import com.runanywhere.runanywhereai.data.repository.ModelInfo
import com.runanywhere.runanywhereai.utils.formatBytes

/**
 * Models management screen
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelsScreen(
    viewModel: ModelsViewModel = viewModel(),
    onNavigateBack: () -> Unit
) {
    val availableModels by viewModel.availableModels.collectAsState()
    val downloadedModels by viewModel.downloadedModels.collectAsState()
    val downloadProgress by viewModel.downloadProgress.collectAsState()
    val selectedModel by viewModel.selectedModel.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    
    LaunchedEffect(Unit) {
        viewModel.refreshModels()
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Model Management") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refreshModels() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                }
            )
        }
    ) { paddingValues ->
        if (isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Downloaded models section
                if (downloadedModels.isNotEmpty()) {
                    item {
                        Text(
                            text = "Downloaded Models",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(vertical = 8.dp)
                        )
                    }
                    
                    items(downloadedModels) { model ->
                        ModelCard(
                            model = model,
                            isSelected = selectedModel?.id == model.id,
                            downloadProgress = if (downloadProgress?.modelId == model.id) {
                                downloadProgress
                            } else null,
                            onSelect = { viewModel.selectModel(model) },
                            onDownload = { /* Already downloaded */ },
                            onDelete = { viewModel.deleteModel(model) }
                        )
                    }
                }
                
                // Available models section
                item {
                    Text(
                        text = "Available Models",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(vertical = 8.dp)
                    )
                }
                
                items(availableModels.filter { available ->
                    downloadedModels.none { it.id == available.id }
                }) { model ->
                    ModelCard(
                        model = model,
                        isSelected = false,
                        downloadProgress = if (downloadProgress?.modelId == model.id) {
                            downloadProgress
                        } else null,
                        onSelect = { /* Can't select undownloaded model */ },
                        onDownload = { viewModel.downloadModel(model) },
                        onDelete = { /* Can't delete undownloaded model */ }
                    )
                }
            }
        }
    }
}

/**
 * Individual model card
 */
@Composable
fun ModelCard(
    model: ModelInfo,
    isSelected: Boolean,
    downloadProgress: ModelDownloadProgress?,
    onSelect: () -> Unit,
    onDownload: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surface
            }
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = model.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    
                    Text(
                        text = model.description,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    
                    Spacer(modifier = Modifier.height(4.dp))
                    
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssistChip(
                            onClick = { },
                            label = { Text(model.framework.name) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Build,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        )
                        
                        AssistChip(
                            onClick = { },
                            label = { Text(formatBytes(model.sizeBytes)) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.AccountBox,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        )
                        
                        AssistChip(
                            onClick = { },
                            label = { Text(model.quantization) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Settings,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        )
                    }
                }
                
                // Action buttons
                if (model.isDownloaded) {
                    Row {
                        if (!isSelected) {
                            IconButton(onClick = onSelect) {
                                Icon(Icons.Default.CheckCircle, contentDescription = "Select")
                            }
                        }
                        IconButton(onClick = onDelete) {
                            Icon(Icons.Default.Delete, contentDescription = "Delete")
                        }
                    }
                } else {
                    IconButton(
                        onClick = onDownload,
                        enabled = downloadProgress == null
                    ) {
                        Icon(Icons.Default.Add, contentDescription = "Download")
                    }
                }
            }
            
            // Download progress
            downloadProgress?.let { progress ->
                Spacer(modifier = Modifier.height(8.dp))
                
                when (val state = progress.progress) {
                    is DownloadProgress.Starting -> {
                        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                        Text(
                            text = "Starting download...",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    is DownloadProgress.InProgress -> {
                        LinearProgressIndicator(
                            progress = { state.progress },
                            modifier = Modifier.fillMaxWidth()
                        )
                        Text(
                            text = "${(state.progress * 100).toInt()}% - ${formatBytes(state.bytesDownloaded)} / ${formatBytes(state.totalBytes)}",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    is DownloadProgress.Completed -> {
                        Text(
                            text = "Download completed!",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                    is DownloadProgress.Failed -> {
                        Text(
                            text = "Download failed: ${state.error}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                    is DownloadProgress.Verifying -> {
                        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                        Text(
                            text = "Verifying download...",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        }
    }
}

/**
 * Model download progress wrapper
 */
data class ModelDownloadProgress(
    val modelId: String,
    val progress: DownloadProgress
)