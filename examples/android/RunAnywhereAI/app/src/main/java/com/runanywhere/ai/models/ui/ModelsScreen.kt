package com.runanywhere.ai.models.ui

import android.os.Build
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.ai.models.data.*
import com.runanywhere.ai.models.repository.ModelRepository
import com.runanywhere.ai.models.viewmodel.ModelManagementViewModel
import com.runanywhere.sdk.models.enums.LLMFramework
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelsScreen() {
    val context = LocalContext.current
    val viewModel: ModelManagementViewModel = viewModel {
        val appContext = context.applicationContext
        ModelManagementViewModel(ModelRepository(appContext))
    }
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val modelsByFramework by viewModel.modelsByFramework.collectAsStateWithLifecycle()
    val currentModel by viewModel.currentModel.collectAsStateWithLifecycle()
    val downloadProgress by viewModel.downloadProgress.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()

    val scrollState = rememberLazyListState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // Handle messages and errors
    LaunchedEffect(uiState.message) {
        uiState.message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearMessage()
        }
    }

    LaunchedEffect(uiState.error) {
        uiState.error?.let {
            snackbarHostState.showSnackbar(it, duration = SnackbarDuration.Long)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Model Management") },
                actions = {
                    // TODO: Implement custom model addition feature
                    // IconButton(onClick = { viewModel.showAddModelDialog() }) {
                    //     Icon(Icons.Default.Add, contentDescription = "Add Model")
                    // }
                    IconButton(onClick = { viewModel.refreshModels() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { /* Navigate to storage management */ },
                icon = { Icon(Icons.Default.Storage, contentDescription = null) },
                text = { Text("Storage") }
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            LazyColumn(
                state = scrollState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Device Information Section
                item {
                    DeviceInfoCard()
                }

                // Current Model Section
                currentModel?.let { model ->
                    item {
                        CurrentModelCard(
                            model = model,
                            onManage = { /* Navigate to model details */ }
                        )
                    }
                }

                // Frameworks and Models Section
                item {
                    Text(
                        text = "Available Frameworks",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }

                modelsByFramework.forEach { (framework, models) ->
                    item(key = framework) {
                        FrameworkSection(
                            framework = framework,
                            models = models,
                            isExpanded = uiState.expandedFramework == framework,
                            currentModel = currentModel,
                            downloadProgress = downloadProgress,
                            downloadingModels = uiState.downloadingModels,
                            loadingModel = uiState.loadingModel,
                            onToggleExpand = { viewModel.toggleFrameworkExpansion(framework) },
                            onDownloadModel = { viewModel.downloadModel(it) },
                            onLoadModel = { viewModel.loadModel(it) },
                            onDeleteModel = { viewModel.deleteModel(it) },
                            onShowDetails = { viewModel.showModelDetails(it) }
                        )
                    }
                }
            }

            // Loading overlay
            if (isLoading || uiState.isRefreshing) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.5f)),
                    contentAlignment = Alignment.Center
                ) {
                    Card {
                        Column(
                            modifier = Modifier.padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            CircularProgressIndicator()
                            Spacer(modifier = Modifier.height(16.dp))
                            Text("Loading models...")
                        }
                    }
                }
            }
        }
    }

    // Model Details Dialog
    uiState.selectedModelForDetails?.let { model ->
        ModelDetailsDialog(
            model = model,
            onDismiss = { viewModel.hideModelDetails() }
        )
    }

    // Add Model Dialog - Disabled until custom model addition is implemented
    // TODO: Implement custom model addition feature (repository + viewModel methods)
    // if (uiState.showAddModelDialog) {
    //     AddModelDialog(
    //         onDismiss = { viewModel.hideAddModelDialog() },
    //         onAddModel = { modelName: String, modelUrl: String, framework: LLMFramework, supportsThinking: Boolean ->
    //             viewModel.addCustomModel(modelName, modelUrl, framework, supportsThinking)
    //             viewModel.hideAddModelDialog()
    //         }
    //     )
    // }
}

@Composable
fun DeviceInfoCard() {
    val context = LocalContext.current

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Device Information",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    InfoRow(
                        icon = Icons.Default.PhoneAndroid,
                        label = "Device",
                        value = "${Build.MANUFACTURER} ${Build.MODEL}"
                    )
                    InfoRow(
                        icon = Icons.Default.Memory,
                        label = "Android",
                        value = "API ${Build.VERSION.SDK_INT}"
                    )
                }
                Column {
                    InfoRow(
                        icon = Icons.Default.Computer,
                        label = "Processor",
                        value = Build.HARDWARE
                    )
                    InfoRow(
                        icon = Icons.Default.Speed,
                        label = "Cores",
                        value = "${Runtime.getRuntime().availableProcessors()}"
                    )
                }
            }
        }
    }
}

@Composable
fun InfoRow(
    icon: ImageVector,
    label: String,
    value: String
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(vertical = 4.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(16.dp),
            tint = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = "$label: ",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onPrimaryContainer
        )
    }
}

@Composable
fun CurrentModelCard(
    model: ModelInfo,
    onManage: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Current Model",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f)
                )
                Text(
                    text = model.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(top = 4.dp)
                ) {
                    AssistChip(
                        onClick = { },
                        label = { Text(model.format.displayName) },
                        modifier = Modifier.height(24.dp)
                    )
                    if (model.supportsThinking) {
                        AssistChip(
                            onClick = { },
                            label = {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        Icons.Default.Psychology,
                                        contentDescription = null,
                                        modifier = Modifier.size(16.dp)
                                    )
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("Thinking")
                                }
                            },
                            modifier = Modifier.height(24.dp),
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.2f)
                            )
                        )
                    }
                }
            }
            Button(
                onClick = onManage,
                modifier = Modifier.padding(start = 16.dp)
            ) {
                Text("Manage")
            }
        }
    }
}

@OptIn(ExperimentalAnimationApi::class)
@Composable
fun FrameworkSection(
    framework: LLMFramework,
    models: List<ModelInfo>,
    isExpanded: Boolean,
    currentModel: ModelInfo?,
    downloadProgress: Map<String, Float>,
    downloadingModels: Set<String>,
    loadingModel: String?,
    onToggleExpand: () -> Unit,
    onDownloadModel: (String) -> Unit,
    onLoadModel: (String) -> Unit,
    onDeleteModel: (String) -> Unit,
    onShowDetails: (ModelInfo) -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column {
            // Framework Header
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onToggleExpand() },
                color = MaterialTheme.colorScheme.surface
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(
                            imageVector = framework.getIcon(),
                            contentDescription = null,
                            modifier = Modifier.size(24.dp),
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text(
                                text = framework.displayName,
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                text = framework.description,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                            )
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Badge {
                            Text(models.size.toString())
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Icon(
                            imageVector = if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                            contentDescription = if (isExpanded) "Collapse" else "Expand",
                            modifier = Modifier.size(24.dp)
                        )
                    }
                }
            }

            // Models List
            AnimatedVisibility(
                visible = isExpanded,
                enter = expandVertically() + fadeIn(),
                exit = shrinkVertically() + fadeOut()
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    models.forEach { model ->
                        ModelRow(
                            model = model,
                            isSelected = currentModel?.id == model.id,
                            downloadProgress = downloadProgress[model.id],
                            isDownloading = model.id in downloadingModels,
                            isLoading = loadingModel == model.id,
                            onDownload = { onDownloadModel(model.id) },
                            onLoad = { onLoadModel(model.id) },
                            onDelete = { onDeleteModel(model.id) },
                            onShowDetails = { onShowDetails(model) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun ModelRow(
    model: ModelInfo,
    isSelected: Boolean,
    downloadProgress: Float?,
    isDownloading: Boolean,
    isLoading: Boolean,
    onDownload: () -> Unit,
    onLoad: () -> Unit,
    onDelete: () -> Unit,
    onShowDetails: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onShowDetails() },
        colors = if (isSelected) {
            CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer
            )
        } else {
            CardDefaults.cardColors()
        },
        border = if (isSelected) {
            BorderStroke(2.dp, MaterialTheme.colorScheme.primary)
        } else null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp)
        ) {
            // Model Info Row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = model.name,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium
                    )

                    // Model badges
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier.padding(top = 4.dp)
                    ) {
                        // Size badge
                        if (model.downloadSize != null) {
                            AssistChip(
                                onClick = { },
                                label = {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(
                                            Icons.Default.Memory,
                                            contentDescription = null,
                                            modifier = Modifier.size(12.dp)
                                        )
                                        Spacer(modifier = Modifier.width(4.dp))
                                        Text(
                                            model.displaySize,
                                            style = MaterialTheme.typography.labelSmall
                                        )
                                    }
                                },
                                modifier = Modifier.height(20.dp),
                                border = null
                            )
                        }

                        // Format badge
                        AssistChip(
                            onClick = { },
                            label = {
                                Text(
                                    model.format.displayName,
                                    style = MaterialTheme.typography.labelSmall
                                )
                            },
                            modifier = Modifier.height(20.dp),
                            border = null
                        )

                        // Thinking badge
                        if (model.supportsThinking) {
                            AssistChip(
                                onClick = { },
                                label = {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(
                                            Icons.Default.Psychology,
                                            contentDescription = null,
                                            modifier = Modifier.size(12.dp)
                                        )
                                        Spacer(modifier = Modifier.width(2.dp))
                                        Text(
                                            "THINKING",
                                            style = MaterialTheme.typography.labelSmall
                                        )
                                    }
                                },
                                modifier = Modifier.height(20.dp),
                                colors = AssistChipDefaults.assistChipColors(
                                    containerColor = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.2f)
                                ),
                                border = null
                            )
                        }
                    }
                }

                // Action button
                ModelActionButton(
                    model = model,
                    isSelected = isSelected,
                    isDownloading = isDownloading,
                    isLoading = isLoading,
                    onDownload = onDownload,
                    onLoad = onLoad,
                    onDelete = onDelete
                )
            }

            // Download progress
            if (isDownloading && downloadProgress != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Column {
                    LinearProgressIndicator(
                        progress = { downloadProgress },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        text = "${(downloadProgress * 100).toInt()}%",
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun ModelActionButton(
    model: ModelInfo,
    isSelected: Boolean,
    isDownloading: Boolean,
    isLoading: Boolean,
    onDownload: () -> Unit,
    onLoad: () -> Unit,
    onDelete: () -> Unit
) {
    when {
        isLoading -> {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp
            )
        }
        isDownloading -> {
            // Show progress indicator during download
            // TODO: Add cancel button when download cancellation is implemented
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp
            )
        }
        model.state == ModelState.BUILT_IN || isSelected -> {
            if (isSelected) {
                AssistChip(
                    onClick = { },
                    label = { Text("Loaded") },
                    leadingIcon = {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                    },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
                    )
                )
            } else {
                Button(
                    onClick = onLoad,
                    modifier = Modifier.height(32.dp)
                ) {
                    Text("Select", style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        model.canDownload -> {
            Button(
                onClick = onDownload,
                modifier = Modifier.height(32.dp)
            ) {
                Icon(
                    Icons.Default.Download,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Download", style = MaterialTheme.typography.labelMedium)
            }
        }
        model.isDownloaded -> {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = onLoad,
                    modifier = Modifier.height(32.dp)
                ) {
                    Text("Load", style = MaterialTheme.typography.labelMedium)
                }
                IconButton(
                    onClick = onDelete,
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = "Delete",
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }
        else -> {
            Text(
                text = "Not Available",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
            )
        }
    }
}
