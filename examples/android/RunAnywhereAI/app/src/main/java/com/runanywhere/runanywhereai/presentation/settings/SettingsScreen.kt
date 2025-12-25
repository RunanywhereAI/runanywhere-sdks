@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.runanywhere.runanywhereai.presentation.settings

import android.content.Intent
import android.net.Uri
import android.text.format.Formatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.AppColors

/**
 * Settings & Storage Screen
 *
 * Sections:
 * 1. Storage Overview
 * 2. Downloaded Models
 * 3. Storage Management
 * 4. About
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(viewModel: SettingsViewModel = viewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showDeleteConfirmDialog by remember { mutableStateOf<StoredModelInfo?>(null) }

    Column(
        modifier =
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
    ) {
        // Header
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
        }

        // Storage Overview Section
        SettingsSection(
            title = "Storage Overview",
            trailing = {
                TextButton(onClick = { viewModel.refreshStorage() }) {
                    Text("Refresh", style = MaterialTheme.typography.labelMedium)
                }
            },
        ) {
            StorageOverviewRow(
                icon = Icons.Outlined.Storage,
                label = "Total Usage",
                value = Formatter.formatFileSize(context, uiState.totalStorageSize),
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.CloudQueue,
                label = "Available Space",
                value = Formatter.formatFileSize(context, uiState.availableSpace),
                valueColor = AppColors.primaryGreen,
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.Memory,
                label = "Models Storage",
                value = Formatter.formatFileSize(context, uiState.modelStorageSize),
                valueColor = AppColors.primaryAccent,
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.Numbers,
                label = "Downloaded Models",
                value = uiState.downloadedModels.size.toString(),
            )
        }

        // Downloaded Models Section
        SettingsSection(title = "Downloaded Models") {
            if (uiState.downloadedModels.isEmpty()) {
                Text(
                    text = "No models downloaded yet",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            } else {
                uiState.downloadedModels.forEachIndexed { index, model ->
                    StoredModelRow(
                        model = model,
                        onDelete = { showDeleteConfirmDialog = model },
                    )
                    if (index < uiState.downloadedModels.lastIndex) {
                        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    }
                }
            }
        }

        // Storage Management Section
        SettingsSection(title = "Storage Management") {
            StorageManagementButton(
                title = "Clear Cache",
                icon = Icons.Outlined.DeleteSweep,
                color = AppColors.primaryRed,
                onClick = { viewModel.clearCache() },
            )
            Spacer(modifier = Modifier.height(8.dp))
            StorageManagementButton(
                title = "Clean Temporary Files",
                icon = Icons.Outlined.CleaningServices,
                color = AppColors.primaryOrange,
                onClick = { viewModel.cleanTempFiles() },
            )
        }

        // About Section
        SettingsSection(title = "About") {
            Row(
                modifier = Modifier.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Outlined.Widgets,
                    contentDescription = null,
                    tint = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "RunAnywhere SDK",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "Version 0.1",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .clickable {
                            val intent = Intent(
                                Intent.ACTION_VIEW,
                                Uri.parse("https://github.com/RunanywhereAI/runanywhere-sdks/")
                            )
                            context.startActivity(intent)
                        }
                        .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Outlined.MenuBook,
                    contentDescription = null,
                    tint = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "SDK Documentation",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.weight(1f))
                Icon(
                    Icons.Default.OpenInNew,
                    contentDescription = "Open link",
                    modifier = Modifier.size(16.dp),
                    tint = AppColors.primaryAccent,
                )
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
    }

    // Delete Confirmation Dialog
    showDeleteConfirmDialog?.let { model ->
        AlertDialog(
            onDismissRequest = { showDeleteConfirmDialog = null },
            title = { Text("Delete Model") },
            text = {
                Text("Are you sure you want to delete ${model.name}? This action cannot be undone.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteModelById(model.id)
                        showDeleteConfirmDialog = null
                    },
                    colors =
                        ButtonDefaults.textButtonColors(
                            contentColor = MaterialTheme.colorScheme.error,
                        ),
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmDialog = null }) {
                    Text("Cancel")
                }
            },
        )
    }
}

/**
 * Settings Section wrapper
 */
@Composable
private fun SettingsSection(
    title: String,
    trailing: @Composable (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            trailing?.invoke()
        }
        Spacer(modifier = Modifier.height(8.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surfaceVariant,
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                content = content,
            )
        }
    }
}

/**
 * Storage Overview Row
 */
@Composable
private fun StorageOverviewRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    valueColor: Color = MaterialTheme.colorScheme.onSurfaceVariant,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = valueColor,
        )
    }
}

/**
 * Stored Model Row
 */
@Composable
private fun StoredModelRow(
    model: StoredModelInfo,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current

    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Left: Model name
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = model.name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Text(
                text = "ID: ${model.id}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // Right: Size and delete button
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = Formatter.formatFileSize(context, model.size),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
            )
            // Delete button
            OutlinedButton(
                onClick = onDelete,
                modifier = Modifier.size(28.dp),
                contentPadding = PaddingValues(0.dp),
                colors =
                    ButtonDefaults.outlinedButtonColors(
                        contentColor = AppColors.primaryRed,
                    ),
            ) {
                Icon(
                    Icons.Outlined.Delete,
                    contentDescription = "Delete",
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

/**
 * Storage Management Button
 */
@Composable
private fun StorageManagementButton(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    onClick: () -> Unit,
) {
    Surface(
        modifier =
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp),
        color = color.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                color = color,
            )
        }
    }
}
