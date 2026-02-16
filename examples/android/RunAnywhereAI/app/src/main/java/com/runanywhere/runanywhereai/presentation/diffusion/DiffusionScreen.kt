package com.runanywhere.runanywhereai.presentation.diffusion

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiffusionScreen(viewModel: DiffusionViewModel = viewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Title
        Text(
            text = "Image Generation",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = "Powered by stable-diffusion.cpp",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // Status Card
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = if (uiState.errorMessage != null) {
                    MaterialTheme.colorScheme.errorContainer
                } else {
                    MaterialTheme.colorScheme.surfaceVariant
                },
            ),
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Text(
                    text = uiState.status,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                uiState.errorMessage?.let { error ->
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = error,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }

        // Download progress
        if (uiState.isDownloading) {
            LinearProgressIndicator(
                progress = { uiState.downloadProgress },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // Model Selector Dropdown
        if (uiState.availableModels.isNotEmpty()) {
            var expanded by remember { mutableStateOf(false) }
            val selectedModel = uiState.availableModels.find { it.id == uiState.selectedModelId }

            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it },
            ) {
                OutlinedTextField(
                    value = selectedModel?.name ?: "Select a model",
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Model") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                    modifier = Modifier
                        .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                        .fillMaxWidth(),
                    supportingText = {
                        if (selectedModel != null) {
                            Text(
                                if (selectedModel.isDownloaded) "Downloaded" else "Not downloaded",
                                color = if (selectedModel.isDownloaded) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                },
                            )
                        }
                    },
                )
                ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    uiState.availableModels.forEach { model ->
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(model.name)
                                    Text(
                                        if (model.isDownloaded) "Ready" else "Needs download",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            },
                            onClick = {
                                viewModel.selectModel(model.id)
                                expanded = false
                            },
                        )
                    }
                }
            }
        }

        // Action Buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val selectedModel = uiState.availableModels.find { it.id == uiState.selectedModelId }
            val needsDownload = selectedModel != null && !selectedModel.isDownloaded

            if (needsDownload) {
                // Download button
                Button(
                    onClick = { viewModel.downloadSelectedModel() },
                    enabled = !uiState.isDownloading,
                    modifier = Modifier.weight(1f),
                ) {
                    if (uiState.isDownloading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.size(8.dp))
                        Text("Downloading...")
                    } else {
                        Icon(Icons.Filled.Download, contentDescription = null)
                        Spacer(modifier = Modifier.size(4.dp))
                        Text("Download Model")
                    }
                }
            } else {
                // Load / Unload buttons
                Button(
                    onClick = { viewModel.loadSelectedModel() },
                    enabled = selectedModel?.isDownloaded == true && !uiState.isLoading && !uiState.isModelLoaded,
                    modifier = Modifier.weight(1f),
                ) {
                    if (uiState.isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp,
                        )
                    } else {
                        Text("Load Model")
                    }
                }
                OutlinedButton(
                    onClick = { viewModel.unloadModel() },
                    enabled = uiState.isModelLoaded,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Unload")
                }
            }
        }

        // Prompt Input
        OutlinedTextField(
            value = uiState.prompt,
            onValueChange = { viewModel.updatePrompt(it) },
            label = { Text("Prompt") },
            modifier = Modifier.fillMaxWidth(),
            maxLines = 3,
            enabled = !uiState.isGenerating,
        )

        // Generate Button
        Button(
            onClick = { viewModel.generateImage() },
            enabled = uiState.isModelLoaded && !uiState.isGenerating && uiState.prompt.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (uiState.isGenerating) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                    strokeWidth = 2.dp,
                )
                Spacer(modifier = Modifier.size(8.dp))
                Text("Generating...")
            } else {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Spacer(modifier = Modifier.size(4.dp))
                Text("Generate Image")
            }
        }

        // Image Preview
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                if (uiState.generatedImage != null) {
                    Image(
                        bitmap = uiState.generatedImage!!.asImageBitmap(),
                        contentDescription = "Generated image",
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(RoundedCornerShape(12.dp)),
                        contentScale = ContentScale.Fit,
                    )
                } else if (uiState.isGenerating) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator()
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "This may take 30-60 seconds...",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                } else {
                    Text(
                        text = "Generated image will appear here",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // Generation stats
        if (uiState.generationTimeMs > 0) {
            Text(
                text = "Generation time: ${uiState.generationTimeMs / 1000}.${(uiState.generationTimeMs % 1000) / 100}s",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
