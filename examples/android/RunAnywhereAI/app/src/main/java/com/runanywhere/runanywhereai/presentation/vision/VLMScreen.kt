package com.runanywhere.runanywhereai.presentation.vision

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
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
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.components.ConfigureCustomTopBar
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.extensions.isVLMModelLoaded
import kotlinx.coroutines.launch

/**
 * VLM Screen — Vision Language Model interface with live camera.
 * Mirrors iOS VLMCameraView.swift exactly.
 *
 * Features:
 * - Live camera preview via CameraX (top 45%)
 * - Gallery image selection (photo picker)
 * - Single-shot frame analysis (sparkles button)
 * - Auto-streaming mode (live button, every 2.5s)
 * - VLM model selection via bottom sheet
 * - Streaming text generation with real-time display
 * - Copy description to clipboard
 * - Cancel ongoing generation
 * - Camera permission handling with "Open Settings" fallback
 *
 * iOS Reference: examples/ios/RunAnywhereAI/.../Features/Vision/VLMCameraView.swift
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VLMScreen(
    onBack: () -> Unit = {},
    viewModel: VLMViewModel = viewModel(
        factory = androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.getInstance(
            LocalContext.current.applicationContext as android.app.Application,
        ),
    ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboard.current
    val context = LocalContext.current

    // Photo picker launcher
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent(),
    ) { uri: Uri? ->
        viewModel.setSelectedImage(uri)
        if (uri != null) {
            viewModel.processSelectedImage()
        }
    }

    // Camera permission launcher
    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted ->
        viewModel.onCameraPermissionResult(granted)
    }

    // Stop auto-streaming and camera when leaving screen
    DisposableEffect(Unit) {
        onDispose {
            viewModel.stopAutoStreaming()
            viewModel.unbindCamera()
        }
    }

    ConfigureCustomTopBar {
        TopAppBar(
            title = { Text("Vision AI") },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = Color.White,
                    )
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = Color.Black,
                titleContentColor = Color.White,
            ),
            actions = {
                uiState.loadedModelName?.let { name ->
                    Text(
                        text = name,
                        color = Color.Gray,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(end = 8.dp),
                    )
                }
            },
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
            if (!uiState.isModelLoaded) {
                ModelRequiredContent(
                    onSelectModel = { viewModel.setShowModelSelection(true) },
                )
            } else {
                // Camera preview (top 45%) — mirrors iOS cameraPreview
                CameraPreviewSection(
                    viewModel = viewModel,
                    uiState = uiState,
                    onRequestPermission = {
                        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(0.45f),
                )

                // Description panel — mirrors iOS descriptionPanel
                DescriptionPanel(
                    description = uiState.currentDescription,
                    error = uiState.error,
                    isAutoStreaming = uiState.isAutoStreamingEnabled,
                    onCopy = {
                        if (uiState.currentDescription.isNotEmpty()) {
                            scope.launch {
                                clipboard.setClipEntry(
                                    ClipEntry(
                                        android.content.ClipData.newPlainText(
                                            "description",
                                            uiState.currentDescription,
                                        ),
                                    ),
                                )
                            }
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(0.45f),
                )

                // Control bar (4 buttons) — mirrors iOS controlBar
                ControlBar(
                    isProcessing = uiState.isProcessing,
                    isAutoStreaming = uiState.isAutoStreamingEnabled,
                    onPickPhoto = { photoPickerLauncher.launch("image/*") },
                    onDescribeFrame = { viewModel.describeCurrentFrame() },
                    onStopAutoStream = { viewModel.stopAutoStreaming() },
                    onToggleLive = { viewModel.toggleAutoStreaming() },
                    onSelectModel = { viewModel.setShowModelSelection(true) },
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
                    viewModel.checkModelStatus()
                    if (RunAnywhere.isVLMModelLoaded) {
                        viewModel.onModelLoaded(modelName = model.name)
                    }
                }
            },
        )
    }
}

// Camera Preview Section — mirrors iOS cameraPreview

@Composable
private fun CameraPreviewSection(
    viewModel: VLMViewModel,
    uiState: VLMUiState,
    onRequestPermission: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        if (uiState.isCameraAuthorized) {
            // Live camera preview via CameraX PreviewView
            val context = LocalContext.current
            val lifecycleOwner = LocalLifecycleOwner.current
            val previewView = remember {
                PreviewView(context).apply {
                    scaleType = PreviewView.ScaleType.FILL_CENTER
                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                }
            }

            AndroidView(
                factory = {
                    previewView.also { viewModel.bindCamera(it, lifecycleOwner) }
                },
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            // Camera permission view — mirrors iOS cameraPermissionView
            CameraPermissionView(onRequestPermission = onRequestPermission)
        }

        // Processing overlay — mirrors iOS processing overlay
        if (uiState.isProcessing) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.BottomCenter,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier
                        .padding(bottom = 16.dp)
                        .background(
                            Color.Black.copy(alpha = 0.6f),
                            shape = CircleShape,
                        )
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    CircularProgressIndicator(
                        color = Color.White,
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                    )
                    Text(
                        "Analyzing...",
                        color = Color.White,
                        fontSize = 12.sp,
                    )
                }
            }
        }
    }
}

// Camera Permission View — mirrors iOS cameraPermissionView

@Composable
private fun CameraPermissionView(onRequestPermission: () -> Unit) {
    val context = LocalContext.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.CameraAlt,
            contentDescription = null,
            tint = Color.Gray,
            modifier = Modifier.size(48.dp),
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            "Camera Access Required",
            color = Color.White,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Button(
            onClick = onRequestPermission,
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF3A3A3C)),
        ) {
            Text("Grant Permission", color = Color.White)
        }
        Spacer(modifier = Modifier.height(8.dp))
        Button(
            onClick = {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", context.packageName, null)
                }
                context.startActivity(intent)
            },
            colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
        ) {
            Text("Open Settings", color = Color(0xFF0A84FF), fontSize = 14.sp)
        }
    }
}

// Description Panel — mirrors iOS descriptionPanel exactly

@Composable
private fun DescriptionPanel(
    description: String,
    error: String?,
    isAutoStreaming: Boolean,
    onCopy: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .background(Color(0xFF1C1C1E))
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        // Header row — "Description" + optional LIVE badge + copy button
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    "Description",
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                // LIVE badge — mirrors iOS HStack with green Circle + "LIVE" text
                if (isAutoStreaming) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Filled.FiberManualRecord,
                            contentDescription = null,
                            tint = Color.Green,
                            modifier = Modifier.size(8.dp),
                        )
                        Text(
                            "LIVE",
                            color = Color.Green,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            }

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

        // Description text (scrollable, max height ~150dp) — mirrors iOS ScrollView
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
        ) {
            when {
                error != null -> {
                    Text(error, color = Color(0xFFFF453A), fontSize = 14.sp)
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
                        "Tap the button to describe what your camera sees",
                        color = Color.Gray,
                        fontSize = 14.sp,
                    )
                }
            }
        }
    }
}

// Control Bar (4 buttons) — mirrors iOS controlBar exactly

@Composable
private fun ControlBar(
    isProcessing: Boolean,
    isAutoStreaming: Boolean,
    onPickPhoto: () -> Unit,
    onDescribeFrame: () -> Unit,
    onStopAutoStream: () -> Unit,
    onToggleLive: () -> Unit,
    onSelectModel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .background(Color.Black)
            .padding(vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Photos button — mirrors iOS Photos button
        IconButton(onClick = onPickPhoto, enabled = !isProcessing) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = Icons.Filled.Image,
                    contentDescription = "Photos",
                    tint = if (!isProcessing) Color.White else Color.Gray,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "Photos",
                    color = if (!isProcessing) Color.White else Color.Gray,
                    fontSize = 10.sp,
                )
            }
        }

        // Main action button (64dp circle) — mirrors iOS main action button
        val buttonColor = when {
            isAutoStreaming -> Color(0xFFFF453A) // Red when auto-streaming
            isProcessing -> Color.Gray
            else -> Color(0xFFFF9500) // Orange
        }

        IconButton(
            onClick = {
                if (isAutoStreaming) {
                    onStopAutoStream()
                } else {
                    onDescribeFrame()
                }
            },
            enabled = !isProcessing || isAutoStreaming,
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape)
                .background(buttonColor),
        ) {
            when {
                isProcessing && !isAutoStreaming -> {
                    CircularProgressIndicator(
                        color = Color.White,
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp,
                    )
                }
                isAutoStreaming -> {
                    Icon(
                        imageVector = Icons.Filled.Stop,
                        contentDescription = "Stop",
                        tint = Color.White,
                        modifier = Modifier.size(28.dp),
                    )
                }
                else -> {
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = "Analyze",
                        tint = Color.White,
                        modifier = Modifier.size(28.dp),
                    )
                }
            }
        }

        // Live toggle — mirrors iOS auto-stream toggle
        IconButton(onClick = onToggleLive) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = if (isAutoStreaming) Icons.Filled.LiveTv else Icons.Outlined.LiveTv,
                    contentDescription = "Live",
                    tint = if (isAutoStreaming) Color.Green else Color.White,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "Live",
                    color = if (isAutoStreaming) Color.Green else Color.White,
                    fontSize = 10.sp,
                )
            }
        }

        // Model button — mirrors iOS Model button
        IconButton(onClick = onSelectModel) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = Icons.Outlined.ViewInAr,
                    contentDescription = "Model",
                    tint = Color.White,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "Model",
                    color = Color.White,
                    fontSize = 10.sp,
                )
            }
        }
    }
}

// Model Required Content — mirrors iOS modelRequiredContent

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
                imageVector = Icons.Filled.CameraAlt,
                contentDescription = null,
                tint = Color(0xFFFF9500),
                modifier = Modifier.size(64.dp),
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                "Vision AI",
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "Select a vision model to describe images",
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
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(18.dp),
                    )
                    Text("Select Model", color = Color.White, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}
