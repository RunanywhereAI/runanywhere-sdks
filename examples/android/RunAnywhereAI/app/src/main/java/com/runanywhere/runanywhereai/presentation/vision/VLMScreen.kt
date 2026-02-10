package com.runanywhere.runanywhereai.presentation.vision

import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import kotlinx.coroutines.launch

/**
 * VLM Screen — Vision Language Model interface.
 * Mirrors iOS VLMCameraView.swift.
 *
 * Features:
 * - Image selection from gallery (photos picker)
 * - VLM model selection via bottom sheet
 * - Streaming text generation with real-time display
 * - Copy description to clipboard
 * - Cancel ongoing generation
 *
 * iOS Reference: examples/ios/RunAnywhereAI/.../Features/Vision/VLMCameraView.swift
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VLMScreen(
    viewModel: VLMViewModel = viewModel(
        factory = androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.getInstance(
            LocalContext.current.applicationContext as android.app.Application,
        ),
    ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val clipboardManager = LocalClipboardManager.current
    val context = LocalContext.current

    // Photo picker launcher
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent(),
    ) { uri: Uri? ->
        viewModel.setSelectedImage(uri)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Vision Chat") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Black,
                    titleContentColor = Color.White,
                ),
                actions = {
                    // Model selection button
                    IconButton(onClick = { viewModel.setShowModelSelection(true) }) {
                        Icon(
                            imageVector = Icons.Outlined.ViewInAr,
                            contentDescription = "Select Model",
                            tint = Color.White,
                        )
                    }
                },
            )
        },
        containerColor = Color.Black,
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            if (!uiState.isModelLoaded) {
                // Model required content — matches iOS modelRequiredContent
                ModelRequiredContent(
                    onSelectModel = { viewModel.setShowModelSelection(true) },
                )
            } else {
                // Image preview area (top 40%)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(0.4f)
                        .background(Color(0xFF1A1A1A)),
                    contentAlignment = Alignment.Center,
                ) {
                    val imageUri = uiState.selectedImageUri
                    if (imageUri != null) {
                        // Load bitmap from URI
                        val bitmap = remember(imageUri) {
                            try {
                                context.contentResolver.openInputStream(imageUri)?.use { stream ->
                                    BitmapFactory.decodeStream(stream)
                                }
                            } catch (e: Exception) {
                                null
                            }
                        }

                        if (bitmap != null) {
                            Image(
                                bitmap = bitmap.asImageBitmap(),
                                contentDescription = "Selected image",
                                modifier = Modifier.fillMaxSize(),
                                contentScale = ContentScale.Fit,
                            )
                        }

                        // Processing overlay
                        if (uiState.isProcessing) {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(Color.Black.copy(alpha = 0.5f)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    CircularProgressIndicator(
                                        color = Color(0xFFFF9500),
                                        modifier = Modifier.size(32.dp),
                                    )
                                    Spacer(modifier = Modifier.height(8.dp))
                                    Text(
                                        "Analyzing...",
                                        color = Color.White,
                                        fontSize = 14.sp,
                                    )
                                }
                            }
                        }
                    } else {
                        // Placeholder
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Image,
                                contentDescription = null,
                                tint = Color.Gray,
                                modifier = Modifier.size(64.dp),
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "Select a photo to analyze",
                                color = Color.Gray,
                                fontSize = 16.sp,
                            )
                        }
                    }
                }

                // Description panel (bottom 50%)
                DescriptionPanel(
                    description = uiState.currentDescription,
                    error = uiState.error,
                    isProcessing = uiState.isProcessing,
                    onCopy = {
                        if (uiState.currentDescription.isNotEmpty()) {
                            clipboardManager.setText(AnnotatedString(uiState.currentDescription))
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(0.5f),
                )

                // Control bar (bottom)
                ControlBar(
                    isProcessing = uiState.isProcessing,
                    hasImage = uiState.selectedImageUri != null,
                    onPickPhoto = { photoPickerLauncher.launch("image/*") },
                    onProcess = { viewModel.processSelectedImage() },
                    onCancel = { viewModel.cancelGeneration() },
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(0.1f),
                )
            }
        }

        // Model selection bottom sheet
        if (uiState.showModelSelection) {
            ModelSelectionBottomSheet(
                context = ModelSelectionContext.VLM,
                onDismiss = { viewModel.setShowModelSelection(false) },
                onModelSelected = { model ->
                    scope.launch {
                        viewModel.onModelLoaded(modelName = model.name)
                    }
                },
            )
        }
    }
}

/**
 * Content shown when no VLM model is loaded.
 * Matches iOS modelRequiredContent.
 */
@Composable
private fun ModelRequiredContent(onSelectModel: () -> Unit) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.padding(32.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.ViewInAr,
                contentDescription = null,
                tint = Color.Gray,
                modifier = Modifier.size(64.dp),
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                "Vision Model Required",
                color = Color.White,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "Select a vision language model to start analyzing images.",
                color = Color.Gray,
                fontSize = 14.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(24.dp))
            Button(
                onClick = onSelectModel,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFFFF9500),
                ),
            ) {
                Text("Select Model", color = Color.White)
            }
        }
    }
}

/**
 * Description panel showing VLM output text.
 * Matches iOS descriptionPanel.
 */
@Composable
private fun DescriptionPanel(
    description: String,
    error: String?,
    isProcessing: Boolean,
    onCopy: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .background(Color(0xFF1C1C1E))
            .padding(16.dp),
    ) {
        // Header row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Description",
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )

            if (description.isNotEmpty()) {
                IconButton(onClick = onCopy, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = Icons.Filled.ContentCopy,
                        contentDescription = "Copy",
                        tint = Color.Gray,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Description text (scrollable)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            when {
                error != null -> {
                    Text(
                        error,
                        color = Color(0xFFFF453A),
                        fontSize = 14.sp,
                    )
                }
                description.isNotEmpty() -> {
                    Text(
                        description,
                        color = Color.White.copy(alpha = 0.9f),
                        fontSize = 14.sp,
                        lineHeight = 20.sp,
                    )
                }
                else -> {
                    Text(
                        "Select an image and tap the analyze button to get a description.",
                        color = Color.Gray,
                        fontSize = 14.sp,
                    )
                }
            }
        }
    }
}

/**
 * Bottom control bar with photo picker and process buttons.
 * Matches iOS controlBar (simplified for photo-only — no camera on emulator).
 */
@Composable
private fun ControlBar(
    isProcessing: Boolean,
    hasImage: Boolean,
    onPickPhoto: () -> Unit,
    onProcess: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .background(Color(0xFF1C1C1E))
            .padding(horizontal = 24.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Photo picker button
        IconButton(
            onClick = onPickPhoto,
            enabled = !isProcessing,
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(Color(0xFF2C2C2E)),
        ) {
            Icon(
                imageVector = Icons.Filled.Image,
                contentDescription = "Pick Photo",
                tint = if (!isProcessing) Color.White else Color.Gray,
            )
        }

        Spacer(modifier = Modifier.width(24.dp))

        // Main action button (process / cancel)
        IconButton(
            onClick = if (isProcessing) onCancel else onProcess,
            enabled = hasImage || isProcessing,
            modifier = Modifier
                .size(56.dp)
                .clip(CircleShape)
                .background(
                    when {
                        isProcessing -> Color(0xFFFF453A) // Red when streaming
                        hasImage -> Color(0xFFFF9500) // Orange when ready
                        else -> Color(0xFF3A3A3C) // Gray when disabled
                    },
                ),
        ) {
            Icon(
                imageVector = if (isProcessing) Icons.Filled.Stop else Icons.Filled.AutoAwesome,
                contentDescription = if (isProcessing) "Stop" else "Analyze",
                tint = Color.White,
                modifier = Modifier.size(28.dp),
            )
        }
    }
}
