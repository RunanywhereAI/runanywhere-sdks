@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.runanywhere.runanywhereai.presentation.storage

import android.text.format.Formatter
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.sdk.models.storage.StoredModel
import kotlinx.datetime.Instant
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Storage Management Screen
 * Matches iOS StorageView.swift exactly
 *
 * iOS Reference: Features/Storage/StorageView.swift
 *
 * Sections:
 * 1. Storage Overview - Total usage, available space, models storage, model count
 * 2. Downloaded Models - List of stored models with details and delete option
 * 3. Storage Management - Clear cache, clean temp files buttons
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StorageScreen(
    viewModel: StorageViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Storage") },
                actions = {
                    IconButton(onClick = { viewModel.refreshData() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                }
            )
        }
    ) { paddingValues ->
        if (uiState.isLoading) {
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
                    .padding(paddingValues)
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                contentPadding = PaddingValues(vertical = 16.dp)
            ) {
                // Storage Overview Section
                item {
                    StorageOverviewSection(
                        totalStorageSize = uiState.totalStorageSize,
                        availableSpace = uiState.availableSpace,
                        modelStorageSize = uiState.modelStorageSize,
                        storedModelsCount = uiState.storedModelsCount
                    )
                }

                // Downloaded Models Section
                item {
                    Text(
                        text = "Downloaded Models",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                if (uiState.storedModels.isEmpty()) {
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
                                    imageVector = Icons.Outlined.Storage,
                                    contentDescription = null,
                                    modifier = Modifier.size(48.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                                )
                                Spacer(modifier = Modifier.height(16.dp))
                                Text(
                                    text = "No models downloaded yet",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                } else {
                    items(uiState.storedModels) { model ->
                        StoredModelRow(
                            model = model,
                            onDelete = { viewModel.deleteModel(model.id) }
                        )
                    }
                }

                // Storage Management Section
                item {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Storage Management",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                item {
                    StorageManagementSection(
                        onClearCache = { viewModel.clearCache() },
                        onCleanTempFiles = { viewModel.cleanTempFiles() }
                    )
                }
            }
        }

        // Error Snackbar
        uiState.errorMessage?.let { error ->
            LaunchedEffect(error) {
                // Show error briefly then clear
                kotlinx.coroutines.delay(3000)
                viewModel.clearError()
            }
        }
    }
}

/**
 * Storage Overview Section
 * Matches iOS storageOverviewSection
 */
@Composable
private fun StorageOverviewSection(
    totalStorageSize: Long,
    availableSpace: Long,
    modelStorageSize: Long,
    storedModelsCount: Int
) {
    val context = LocalContext.current

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
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
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            // Total Usage
            StorageInfoRow(
                icon = "💾",
                label = "Total Usage",
                value = Formatter.formatFileSize(context, totalStorageSize),
                valueColor = MaterialTheme.colorScheme.onSurface
            )

            // Available Space
            StorageInfoRow(
                icon = "✅",
                label = "Available Space",
                value = Formatter.formatFileSize(context, availableSpace),
                valueColor = Color(0xFF4CAF50) // Green
            )

            // Models Storage
            StorageInfoRow(
                icon = "🧠",
                label = "Models Storage",
                value = Formatter.formatFileSize(context, modelStorageSize),
                valueColor = Color(0xFF2196F3) // Blue
            )

            // Downloaded Models Count
            StorageInfoRow(
                icon = "#️⃣",
                label = "Downloaded Models",
                value = storedModelsCount.toString(),
                valueColor = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Storage Info Row
 */
@Composable
private fun StorageInfoRow(
    icon: String,
    label: String,
    value: String,
    valueColor: Color
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(text = icon, style = MaterialTheme.typography.bodyLarge)
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = valueColor
        )
    }
}

/**
 * Stored Model Row
 * Matches iOS StoredModelRow
 */
@Composable
private fun StoredModelRow(
    model: StoredModel,
    onDelete: () -> Unit
) {
    var showDetails by remember { mutableStateOf(false) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    val context = LocalContext.current

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Main row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                // Model info
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = model.name,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Medium
                    )
                    Spacer(modifier = Modifier.height(4.dp))

                    // Badges row
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        // Format badge
                        Badge(
                            text = model.format.uppercase(),
                            backgroundColor = Color(0xFF2196F3).copy(alpha = 0.15f),
                            textColor = Color(0xFF2196F3)
                        )

                        // Framework badge
                        model.framework?.let { framework ->
                            Badge(
                                text = framework,
                                backgroundColor = Color(0xFF4CAF50).copy(alpha = 0.15f),
                                textColor = Color(0xFF4CAF50)
                            )
                        }
                    }
                }

                // Size and actions
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = Formatter.formatFileSize(context, model.size),
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Medium
                    )
                    Spacer(modifier = Modifier.height(4.dp))

                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        // Details button
                        TextButton(
                            onClick = { showDetails = !showDetails },
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            Text(
                                text = if (showDetails) "Hide" else "Details",
                                style = MaterialTheme.typography.labelSmall
                            )
                            Icon(
                                imageVector = if (showDetails) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                        }

                        // Delete button
                        IconButton(
                            onClick = { showDeleteConfirmation = true },
                            modifier = Modifier.size(32.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.Delete,
                                contentDescription = "Delete",
                                tint = MaterialTheme.colorScheme.error,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }

            // Expandable details
            AnimatedVisibility(
                visible = showDetails,
                enter = expandVertically(),
                exit = shrinkVertically()
            ) {
                StoredModelDetails(model = model)
            }
        }
    }

    // Delete confirmation dialog
    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            title = { Text("Delete Model") },
            text = { Text("Are you sure you want to delete ${model.name}? This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirmation = false
                        onDelete()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmation = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

/**
 * Model Details Section
 * Matches iOS expandable details section
 */
@Composable
private fun StoredModelDetails(model: StoredModel) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp)
            .background(
                MaterialTheme.colorScheme.surface,
                RoundedCornerShape(8.dp)
            )
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Format
        DetailRow(label = "Format:", value = model.format.uppercase())

        // Framework
        model.framework?.let {
            DetailRow(label = "Framework:", value = it)
        }

        // Context Length
        model.contextLength?.let {
            DetailRow(label = "Context Length:", value = "$it tokens")
        }

        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

        // Path
        Column {
            Text(
                text = "Path:",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = model.path,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }

        // Checksum
        model.checksum?.let {
            Column {
                Text(
                    text = "Checksum:",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        // Created date
        DetailRow(
            label = "Created:",
            value = formatInstant(model.createdDate)
        )

        // Last used
        model.lastUsed?.let {
            DetailRow(label = "Last used:", value = formatInstant(it))
        }
    }
}

/**
 * Detail Row
 */
@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium
        )
        Text(
            text = value,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Badge component
 */
@Composable
private fun Badge(
    text: String,
    backgroundColor: Color,
    textColor: Color
) {
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = backgroundColor
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
        )
    }
}

/**
 * Storage Management Section
 * Matches iOS cacheManagementSection
 */
@Composable
private fun StorageManagementSection(
    onClearCache: () -> Unit,
    onCleanTempFiles: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Clear Cache button
            StorageActionButton(
                icon = "🗑️",
                title = "Clear Cache",
                subtitle = "Free up space by clearing cached data",
                accentColor = MaterialTheme.colorScheme.error,
                onClick = onClearCache
            )

            // Clean Temp Files button
            StorageActionButton(
                icon = "🧹",
                title = "Clean Temporary Files",
                subtitle = "Remove temporary files and logs",
                accentColor = Color(0xFFFF9800), // Orange
                onClick = onCleanTempFiles
            )
        }
    }
}

/**
 * Storage Action Button
 */
@Composable
private fun StorageActionButton(
    icon: String,
    title: String,
    subtitle: String,
    accentColor: Color,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(8.dp),
        color = accentColor.copy(alpha = 0.1f),
        border = ButtonDefaults.outlinedButtonBorder.copy(
            brush = androidx.compose.ui.graphics.SolidColor(accentColor.copy(alpha = 0.3f))
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(text = icon, style = MaterialTheme.typography.titleMedium)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = accentColor
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * Format Instant to readable date string
 */
private fun formatInstant(instant: Instant): String {
    return try {
        val date = Date(instant.toEpochMilliseconds())
        val formatter = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault())
        formatter.format(date)
    } catch (e: Exception) {
        "Unknown"
    }
}
