package com.runanywhere.ai.models.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.runanywhere.ai.models.data.*
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlin.collections.isNotEmpty

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelDetailsDialog(
    model: ModelInfo,
    onDismiss: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth(0.95f)
                .fillMaxHeight(0.8f)
        ) {
            Column(
                modifier = Modifier.fillMaxSize()
            ) {
                // Header
                TopAppBar(
                    title = { Text(model.name) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Close, contentDescription = "Close")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    )
                )

                // Content
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    // Basic Information
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant
                        )
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(
                                text = "Basic Information",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold
                            )

                            DetailRow("Model ID", model.id)
                            DetailRow("Category", model.category.displayName)
                            DetailRow("Format", model.format.displayName)
                            DetailRow("State", model.state.name)

                            if (model.downloadSize != null) {
                                DetailRow("Download Size", model.displaySize)
                            }

                            if (model.memoryRequired != null) {
                                DetailRow("Memory Required", model.displayMemory)
                            }

                            if (model.contextLength != null) {
                                DetailRow("Context Length", "${model.contextLength} tokens")
                            }
                        }
                    }

                    // Capabilities
                    if (model.supportsThinking || model.metadata?.tags?.isNotEmpty() == true) {
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                            )
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = "Capabilities",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold
                                )

                                if (model.supportsThinking) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Icon(
                                            Icons.Default.Psychology,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.tertiary
                                        )
                                        Text("Supports Advanced Thinking")
                                    }

                                    if (model.thinkingTags.isNotEmpty()) {
                                        Row(
                                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                                            modifier = Modifier.padding(top = 4.dp)
                                        ) {
                                            model.thinkingTags.forEach { tag ->
                                                AssistChip(
                                                    onClick = { },
                                                    label = { Text(tag) },
                                                    modifier = Modifier.height(24.dp)
                                                )
                                            }
                                        }
                                    }
                                }

                                // Show metadata tags as capabilities
                                model.metadata?.tags?.forEach { tag ->
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Icon(
                                            Icons.Default.CheckCircle,
                                            contentDescription = null,
                                            modifier = Modifier.size(16.dp),
                                            tint = MaterialTheme.colorScheme.primary
                                        )
                                        Text(tag, style = MaterialTheme.typography.bodyMedium)
                                    }
                                }
                            }
                        }
                    }

                    // Compatible Frameworks
                    if (model.compatibleFrameworks.isNotEmpty()) {
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                            )
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = "Compatible Frameworks",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold
                                )

                                model.compatibleFrameworks.forEach { framework ->
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Icon(
                                            framework.getIcon(),
                                            contentDescription = null,
                                            modifier = Modifier.size(20.dp)
                                        )
                                        Column {
                                            Text(
                                                text = framework.displayName,
                                                style = MaterialTheme.typography.bodyMedium,
                                                fontWeight = if (framework == model.preferredFramework) {
                                                    FontWeight.Bold
                                                } else {
                                                    FontWeight.Normal
                                                }
                                            )
                                            if (framework == model.preferredFramework) {
                                                Text(
                                                    text = "Preferred",
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = MaterialTheme.colorScheme.primary
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Metadata
                    model.metadata?.let { metadata ->
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                            )
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = "Additional Information",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold
                                )

                                metadata.description?.let {
                                    DetailRow("Description", it)
                                }
                                metadata.author?.let {
                                    DetailRow("Author", it)
                                }
                                metadata.version?.let {
                                    DetailRow("Version", it)
                                }
                                metadata.license?.let {
                                    DetailRow("License", it)
                                }
                                metadata.baseModel?.let {
                                    DetailRow("Base Model", it)
                                }
                                metadata.quantizationLevel?.let {
                                    DetailRow("Quantization", it.value)
                                }
                            }
                        }
                    }

                    // URLs
                    if (model.downloadURL != null || model.localPath != null) {
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                            )
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = "File Information",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold
                                )

                                model.downloadURL?.let {
                                    DetailRow("Download URL", it)
                                }
                                model.localPath?.let {
                                    DetailRow("Local Path", it)
                                }
                                model.downloadedAt?.let {
                                    DetailRow("Downloaded", it.toString())
                                }
                                model.lastUsed?.let {
                                    DetailRow("Last Used", it.toString())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun DetailRow(
    label: String,
    value: String
) {
    Column {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddModelDialog(
    onDismiss: () -> Unit,
    onAddModel: (modelName: String, modelUrl: String, framework: LLMFramework, supportsThinking: Boolean) -> Unit
) {
    var modelName by remember { mutableStateOf("") }
    var modelUrl by remember { mutableStateOf("") }
    var selectedFramework by remember { mutableStateOf(LLMFramework.LLAMACPP) }
    var supportsThinking by remember { mutableStateOf(false) }
    var expandedFramework by remember { mutableStateOf(false) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth(0.95f)
                .wrapContentHeight()
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = "Add Model from URL",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )

                // Model Name
                OutlinedTextField(
                    value = modelName,
                    onValueChange = { modelName = it },
                    label = { Text("Model Name") },
                    placeholder = { Text("e.g., Llama 3.2 3B") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                // Model URL
                OutlinedTextField(
                    value = modelUrl,
                    onValueChange = { modelUrl = it },
                    label = { Text("Download URL") },
                    placeholder = { Text("https://...") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
                )

                // Framework Selection
                ExposedDropdownMenuBox(
                    expanded = expandedFramework,
                    onExpandedChange = { expandedFramework = it }
                ) {
                    OutlinedTextField(
                        value = selectedFramework.displayName,
                        onValueChange = { },
                        readOnly = true,
                        label = { Text("Target Framework") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expandedFramework) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor()
                    )

                    ExposedDropdownMenu(
                        expanded = expandedFramework,
                        onDismissRequest = { expandedFramework = false }
                    ) {
                        LLMFramework.values().forEach { framework ->
                            DropdownMenuItem(
                                text = {
                                    Column {
                                        Text(framework.displayName)
                                        Text(
                                            framework.description,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                                        )
                                    }
                                },
                                onClick = {
                                    selectedFramework = framework
                                    expandedFramework = false
                                },
                                leadingIcon = {
                                    Icon(
                                        framework.getIcon(),
                                        contentDescription = null
                                    )
                                }
                            )
                        }
                    }
                }

                // Thinking Support
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    )
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
                                Icons.Default.Psychology,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.tertiary
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Column {
                                Text(
                                    text = "Model Supports Thinking",
                                    style = MaterialTheme.typography.bodyLarge
                                )
                                Text(
                                    text = "Enable for models with reasoning capabilities",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                                )
                            }
                        }
                        Switch(
                            checked = supportsThinking,
                            onCheckedChange = { supportsThinking = it }
                        )
                    }
                }

                // Action Buttons
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("Cancel")
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Button(
                        onClick = {
                            if (modelName.isNotBlank() && modelUrl.isNotBlank()) {
                                onAddModel(modelName, modelUrl, selectedFramework, supportsThinking)
                                onDismiss()
                            }
                        },
                        enabled = modelName.isNotBlank() && modelUrl.isNotBlank()
                    ) {
                        Text("Add Model")
                    }
                }
            }
        }
    }
}
