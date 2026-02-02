package com.runanywhere.runanywhereai.presentation.diffusion

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.R
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.theme.AppColors

/**
 * Diffusion Screen - Image Generation
 *
 * iOS Reference: ImageGenerationView in ImageGenerationView.swift
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiffusionScreen(
    viewModel: DiffusionViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showModelPicker by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Image Generation") },
            )
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Model Status Section
            ModelStatusCard(
                isModelLoaded = uiState.isModelLoaded,
                modelName = uiState.selectedModelName,
                backendType = uiState.backendType,
                onLoadModelClick = { showModelPicker = true },
                onChangeModelClick = { showModelPicker = true },
            )

            // Image Display Section
            ImageDisplayCard(
                isGenerating = uiState.isGenerating,
                progress = uiState.progress,
                currentStep = uiState.currentStep,
                totalSteps = uiState.totalSteps,
                statusMessage = uiState.statusMessage,
                imageData = uiState.generatedImageData,
                imageWidth = uiState.imageWidth,
                imageHeight = uiState.imageHeight,
            )

            // Prompt Input Section
            PromptInputSection(
                prompt = uiState.prompt,
                onPromptChange = viewModel::updatePrompt,
            )

            // Quick Prompts
            QuickPromptsSection(
                onPromptSelected = viewModel::updatePrompt,
            )

            // Generate Button Section
            GenerateButtonSection(
                isGenerating = uiState.isGenerating,
                canGenerate = uiState.isModelLoaded && uiState.prompt.isNotBlank() && !uiState.isGenerating,
                onGenerateClick = viewModel::generateImage,
                onCancelClick = viewModel::cancelGeneration,
            )

            // Error Message
            uiState.errorMessage?.let { error ->
                Text(
                    text = error,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Generation Info
            if (uiState.generatedImageData != null) {
                GenerationInfoCard(
                    seedUsed = uiState.seedUsed,
                    generationTimeMs = uiState.generationTimeMs,
                    width = uiState.imageWidth,
                    height = uiState.imageHeight,
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }

        // Model Selection Bottom Sheet
        if (showModelPicker) {
            ModelSelectionBottomSheet(
                context = ModelSelectionContext.DIFFUSION,
                onDismiss = { showModelPicker = false },
                onModelSelected = { model ->
                    viewModel.onModelLoaded(
                        modelName = model.name,
                        modelId = model.id,
                        framework = model.framework,
                    )
                    showModelPicker = false
                },
            )
        }
    }
}

@Composable
private fun ModelStatusCard(
    isModelLoaded: Boolean,
    modelName: String?,
    backendType: String,
    onLoadModelClick: () -> Unit,
    onChangeModelClick: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Status indicator
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(if (isModelLoaded) Color.Green else Color(0xFFFF9800)),
                )

                Spacer(modifier = Modifier.width(12.dp))

                Column {
                    Text(
                        text = if (isModelLoaded) modelName ?: "Model loaded" else "No model loaded",
                        style = MaterialTheme.typography.bodyMedium,
                    )

                    if (isModelLoaded && backendType.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(4.dp))
                        BackendBadge(backendType = backendType)
                    }
                }
            }

            Button(
                onClick = if (isModelLoaded) onChangeModelClick else onLoadModelClick,
                colors = ButtonDefaults.buttonColors(
                    containerColor = AppColors.primaryAccent,
                ),
            ) {
                Text(if (isModelLoaded) "Change" else "Load Model")
            }
        }
    }
}

@Composable
private fun BackendBadge(backendType: String) {
    val (backgroundColor, textColor) = when {
        backendType.contains("CoreML", ignoreCase = true) -> Color(0xFF2196F3).copy(alpha = 0.15f) to Color(0xFF1976D2)
        backendType.contains("ONNX", ignoreCase = true) -> Color(0xFF9C27B0).copy(alpha = 0.15f) to Color(0xFF7B1FA2)
        else -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.15f) to MaterialTheme.colorScheme.onSecondary
    }

    Row(
        modifier = Modifier
            .background(backgroundColor, RoundedCornerShape(4.dp))
            .padding(horizontal = 8.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.Memory,
            contentDescription = null,
            modifier = Modifier.size(12.dp),
            tint = textColor,
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = backendType,
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
        )
    }
}

@Composable
private fun ImageDisplayCard(
    isGenerating: Boolean,
    progress: Float,
    currentStep: Int,
    totalSteps: Int,
    statusMessage: String,
    imageData: ByteArray?,
    imageWidth: Int,
    imageHeight: Int,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            when {
                imageData != null && imageData.isNotEmpty() -> {
                    // Display generated image
                    val bitmap = remember(imageData) {
                        BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                            ?: createBitmapFromRGBA(imageData, imageWidth, imageHeight)
                    }
                    bitmap?.let {
                        Image(
                            bitmap = it.asImageBitmap(),
                            contentDescription = "Generated image",
                            modifier = Modifier
                                .fillMaxSize()
                                .clip(RoundedCornerShape(12.dp)),
                            contentScale = ContentScale.Fit,
                        )
                    }
                }
                isGenerating -> {
                    // Show progress
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(48.dp),
                            color = AppColors.primaryAccent,
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            text = statusMessage,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (totalSteps > 0) {
                            Spacer(modifier = Modifier.height(8.dp))
                            LinearProgressIndicator(
                                progress = { progress },
                                modifier = Modifier
                                    .width(150.dp)
                                    .height(4.dp),
                                color = AppColors.primaryAccent,
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = "Step $currentStep / $totalSteps",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                else -> {
                    // Placeholder
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_image_placeholder),
                            contentDescription = null,
                            modifier = Modifier.size(64.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "Enter a prompt to generate",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                        )
                    }
                }
            }
        }
    }
}

/**
 * Create bitmap from raw RGBA data
 */
private fun createBitmapFromRGBA(data: ByteArray, width: Int, height: Int): Bitmap? {
    if (width <= 0 || height <= 0 || data.size < width * height * 4) return null
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val pixels = IntArray(width * height)
    for (i in pixels.indices) {
        val offset = i * 4
        if (offset + 3 < data.size) {
            val r = data[offset].toInt() and 0xFF
            val g = data[offset + 1].toInt() and 0xFF
            val b = data[offset + 2].toInt() and 0xFF
            val a = data[offset + 3].toInt() and 0xFF
            pixels[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
        }
    }
    bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    return bitmap
}

@Composable
private fun PromptInputSection(
    prompt: String,
    onPromptChange: (String) -> Unit,
) {
    Column {
        Text(
            text = "Prompt",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedTextField(
            value = prompt,
            onValueChange = onPromptChange,
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp),
            placeholder = { Text("Describe the image you want to generate...") },
        )
    }
}

@Composable
private fun QuickPromptsSection(
    onPromptSelected: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        DiffusionViewModel.SAMPLE_PROMPTS.forEach { prompt ->
            FilterChip(
                selected = false,
                onClick = { onPromptSelected(prompt) },
                label = {
                    Text(
                        text = prompt.take(30) + if (prompt.length > 30) "..." else "",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
            )
        }
    }
}

@Composable
private fun GenerateButtonSection(
    isGenerating: Boolean,
    canGenerate: Boolean,
    onGenerateClick: () -> Unit,
    onCancelClick: () -> Unit,
) {
    if (isGenerating) {
        OutlinedButton(
            onClick = onCancelClick,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(
                contentColor = MaterialTheme.colorScheme.error,
            ),
        ) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Cancel")
        }
    } else {
        Button(
            onClick = onGenerateClick,
            modifier = Modifier.fillMaxWidth(),
            enabled = canGenerate,
            colors = ButtonDefaults.buttonColors(
                containerColor = AppColors.primaryAccent,
            ),
        ) {
            Icon(
                painter = painterResource(id = R.drawable.ic_magic_wand),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Generate")
        }
    }
}

@Composable
private fun GenerationInfoCard(
    seedUsed: Long,
    generationTimeMs: Long,
    width: Int,
    height: Int,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            InfoItem(label = "Size", value = "${width}x$height")
            InfoItem(label = "Seed", value = seedUsed.toString())
            InfoItem(label = "Time", value = "${generationTimeMs}ms")
        }
    }
}

@Composable
private fun InfoItem(label: String, value: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
        )
    }
}
