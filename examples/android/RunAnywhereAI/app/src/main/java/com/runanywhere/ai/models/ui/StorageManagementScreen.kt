package com.runanywhere.ai.models.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.platform.LocalContext
import com.runanywhere.ai.models.data.ModelInfo
import com.runanywhere.ai.models.data.StorageInfo
import com.runanywhere.ai.models.data.StoredModel
import com.runanywhere.ai.models.repository.ModelRepository
import com.runanywhere.ai.models.viewmodel.ModelManagementViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StorageManagementScreen(
    onNavigateBack: () -> Unit = {}
) {
    val context = LocalContext.current
    val viewModel: ModelManagementViewModel = viewModel {
        ModelManagementViewModel(ModelRepository(context))
    }
    var storageInfo by remember { mutableStateOf<StorageInfo?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var showDeleteDialog by remember { mutableStateOf<StoredModel?>(null) }
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    // Load storage info
    LaunchedEffect(Unit) {
        isLoading = true
        try {
            storageInfo = viewModel.getStorageInfo()
        } catch (e: Exception) {
            snackbarHostState.showSnackbar("Failed to load storage info: ${e.message}")
        } finally {
            isLoading = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Storage Management") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(
                        onClick = {
                            scope.launch {
                                isLoading = true
                                try {
                                    storageInfo = viewModel.getStorageInfo()
                                } finally {
                                    isLoading = false
                                }
                            }
                        }
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
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
            storageInfo?.let { info ->
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    // Storage Overview
                    item {
                        StorageOverviewCard(info)
                    }

                    // Storage Breakdown
                    item {
                        StorageBreakdownCard(info)
                    }

                    // Downloaded Models Section
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "Downloaded Models (${info.downloadedModelsCount})",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold
                            )

                            TextButton(
                                onClick = {
                                    scope.launch {
                                        viewModel.clearCache()
                                        snackbarHostState.showSnackbar("Cache cleared")
                                        storageInfo = viewModel.getStorageInfo()
                                    }
                                }
                            ) {
                                Icon(Icons.Default.CleaningServices, contentDescription = null)
                                Spacer(modifier = Modifier.width(4.dp))
                                Text("Clear Cache")
                            }
                        }
                    }

                    // Model List
                    items(info.storedModels) { storedModel ->
                        StoredModelCard(
                            storedModel = storedModel,
                            onDelete = { showDeleteDialog = storedModel }
                        )
                    }

                    // Empty state
                    if (info.storedModels.isEmpty()) {
                        item {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                                )
                            ) {
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(32.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    Icon(
                                        Icons.Default.FolderOff,
                                        contentDescription = null,
                                        modifier = Modifier.size(48.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                                    )
                                    Spacer(modifier = Modifier.height(16.dp))
                                    Text(
                                        text = "No Downloaded Models",
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                                    )
                                    Text(
                                        text = "Download models from the Models tab",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Delete confirmation dialog
    showDeleteDialog?.let { model ->
        AlertDialog(
            onDismissRequest = { showDeleteDialog = null },
            title = { Text("Delete Model") },
            text = {
                Text("Are you sure you want to delete '${model.modelInfo.name}'? This action cannot be undone.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        scope.launch {
                            viewModel.deleteModel(model.modelInfo.id)
                            showDeleteDialog = null
                            snackbarHostState.showSnackbar("Model deleted")
                            storageInfo = viewModel.getStorageInfo()
                        }
                    }
                ) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = null }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
fun StorageOverviewCard(storageInfo: StorageInfo) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Storage Overview",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )

            // App Storage
            StorageProgressRow(
                icon = Icons.Default.Apps,
                label = "App Storage",
                used = storageInfo.usedAppStorage,
                total = storageInfo.totalAppStorage,
                percentage = storageInfo.appStoragePercentage
            )

            // Device Storage
            StorageProgressRow(
                icon = Icons.Default.Storage,
                label = "Device Storage",
                used = storageInfo.totalDeviceStorage - storageInfo.availableDeviceStorage,
                total = storageInfo.totalDeviceStorage,
                percentage = storageInfo.deviceStoragePercentage
            )
        }
    }
}

@Composable
fun StorageProgressRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    used: Long,
    total: Long,
    percentage: Float
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    icon,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Text(
                text = "${ModelInfo.formatBytes(used)} / ${ModelInfo.formatBytes(total)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
            )
        }

        Spacer(modifier = Modifier.height(4.dp))

        LinearProgressIndicator(
            progress = { percentage },
            modifier = Modifier.fillMaxWidth(),
            color = when {
                percentage > 0.9f -> MaterialTheme.colorScheme.error
                percentage > 0.7f -> MaterialTheme.colorScheme.tertiary
                else -> MaterialTheme.colorScheme.primary
            },
        )

        Text(
            text = "${(percentage * 100).toInt()}% used",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
            modifier = Modifier.padding(top = 2.dp)
        )
    }
}

@Composable
fun StorageBreakdownCard(storageInfo: StorageInfo) {
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Storage Breakdown",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )

            StorageItemRow(
                icon = Icons.Default.ModelTraining,
                label = "Models Storage",
                value = ModelInfo.formatBytes(storageInfo.modelsStorage),
                color = MaterialTheme.colorScheme.primary
            )

            StorageItemRow(
                icon = Icons.Default.Cached,
                label = "Cache Size",
                value = ModelInfo.formatBytes(storageInfo.cacheSize),
                color = MaterialTheme.colorScheme.secondary
            )

            StorageItemRow(
                icon = Icons.Default.CloudDownload,
                label = "Downloaded Models",
                value = storageInfo.downloadedModelsCount.toString(),
                color = MaterialTheme.colorScheme.tertiary
            )

            Divider(modifier = Modifier.padding(vertical = 4.dp))

            StorageItemRow(
                icon = Icons.Default.SdStorage,
                label = "Total App Usage",
                value = ModelInfo.formatBytes(storageInfo.usedAppStorage),
                color = MaterialTheme.colorScheme.onSurface,
                isTotal = true
            )
        }
    }
}

@Composable
fun StorageItemRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    color: Color,
    isTotal: Boolean = false
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                icon,
                contentDescription = null,
                modifier = Modifier.size(if (isTotal) 24.dp else 20.dp),
                tint = color
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = label,
                style = if (isTotal) MaterialTheme.typography.bodyLarge else MaterialTheme.typography.bodyMedium,
                fontWeight = if (isTotal) FontWeight.Bold else FontWeight.Normal
            )
        }
        Text(
            text = value,
            style = if (isTotal) MaterialTheme.typography.bodyLarge else MaterialTheme.typography.bodyMedium,
            fontWeight = if (isTotal) FontWeight.Bold else FontWeight.Medium,
            color = color
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoredModelCard(
    storedModel: StoredModel,
    onDelete: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        onClick = { expanded = !expanded }
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
                        text = storedModel.modelInfo.name,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = ModelInfo.formatBytes(storedModel.fileSize),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )

                    if (expanded) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            DetailRow("Path", storedModel.filePath)
                            DetailRow("Last Accessed", java.util.Date(storedModel.lastAccessed).toString())
                            DetailRow("Access Count", storedModel.accessCount.toString())
                            storedModel.modelInfo.format?.let {
                                DetailRow("Format", it.displayName)
                            }
                        }
                    }
                }

                IconButton(onClick = onDelete) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = "Delete",
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            }

            if (!expanded) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.padding(top = 8.dp)
                ) {
                    AssistChip(
                        onClick = { },
                        label = { Text(storedModel.modelInfo.format.displayName) },
                        modifier = Modifier.height(24.dp),
                        border = null
                    )
                    AssistChip(
                        onClick = { },
                        label = {
                            Text(
                                "Accessed ${storedModel.accessCount} times",
                                style = MaterialTheme.typography.labelSmall
                            )
                        },
                        modifier = Modifier.height(24.dp),
                        border = null
                    )
                }
            }
        }
    }
}
