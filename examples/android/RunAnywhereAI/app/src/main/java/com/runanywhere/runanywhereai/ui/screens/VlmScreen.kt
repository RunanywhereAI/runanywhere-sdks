package com.runanywhere.runanywhereai.ui.screens

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.VLMUiState
import com.runanywhere.runanywhereai.ui.components.MarkdownText
import com.runanywhere.runanywhereai.ui.components.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.viewmodels.ModelSelectionViewModel
import com.runanywhere.runanywhereai.viewmodels.VLMViewModel
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.extensions.isVLMModelLoaded
import com.runanywhere.sdk.public.extensions.loadVLMModel
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// -- Panel states for the draggable description panel --

private enum class PanelState { Collapsed, Expanded }

private val PANEL_COLLAPSED_HEIGHT = 140.dp
private val PANEL_EXPANDED_HEIGHT = 380.dp
private val PANEL_CORNER_RADIUS = 24.dp
private val DRAG_THRESHOLD = 60f

@Composable
fun VlmScreen(
    onBack: () -> Unit,
    vlmViewModel: VLMViewModel = viewModel(),
    modelSelectionViewModel: ModelSelectionViewModel = viewModel(),
) {
    val uiState by vlmViewModel.uiState.collectAsStateWithLifecycle()
    val modelState by modelSelectionViewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted ->
        vlmViewModel.onCameraPermissionResult(granted)
    }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent(),
    ) { uri: Uri? ->
        vlmViewModel.setSelectedImage(uri)
        if (uri != null) {
            vlmViewModel.processSelectedImage()
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            vlmViewModel.stopAutoStreaming()
            vlmViewModel.unbindCamera()
        }
    }

    when (val state = uiState) {
        is VLMUiState.Loading -> {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
            }
        }

        is VLMUiState.Ready -> {
            if (!state.isModelLoaded) {
                ModelRequiredFullScreen(
                    onSelectModel = {
                        modelSelectionViewModel.loadModels(ModelSelectionContext.VLM)
                        vlmViewModel.setShowModelSelection(true)
                    },
                )
            } else {
                ImmersiveVlmContent(
                    state = state,
                    onRequestCameraPermission = {
                        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                    },
                    onPickPhoto = { photoPickerLauncher.launch("image/*") },
                    onDescribeFrame = { vlmViewModel.describeCurrentFrame() },
                    onToggleLive = { vlmViewModel.toggleAutoStreaming() },
                    onStopAutoStream = { vlmViewModel.stopAutoStreaming() },
                    onSelectModel = {
                        modelSelectionViewModel.loadModels(ModelSelectionContext.VLM)
                        vlmViewModel.setShowModelSelection(true)
                    },
                    onCancelGeneration = { vlmViewModel.cancelGeneration() },
                    onDismissResult = { vlmViewModel.dismissResult() },
                    onBindCamera = { previewView, lifecycleOwner ->
                        vlmViewModel.bindCamera(previewView, lifecycleOwner)
                    },
                )
            }

            // Model selection bottom sheet
            if (state.showModelSelection) {
                ModelSelectionSheet(
                    state = modelState,
                    onDismiss = { vlmViewModel.setShowModelSelection(false) },
                    onSelectModel = { modelId ->
                        modelSelectionViewModel.selectModel(modelId) { name, _ ->
                            scope.launch {
                                try {
                                    RunAnywhere.loadVLMModel(modelId)
                                    vlmViewModel.onModelLoaded(name)
                                } catch (_: Exception) {
                                    vlmViewModel.refreshModelStatus()
                                }
                            }
                        }
                    },
                    onDownloadModel = { modelSelectionViewModel.downloadModel(it) },
                    onCancelModelDownload = { modelSelectionViewModel.cancelModelDownload() },
                    onLoadLora = { },
                    onUnloadLora = { },
                    onDownloadLora = { },
                    onCancelLoraDownload = { },
                    isLoraDownloaded = { false },
                    isLoraLoaded = { false },
                )
            }
        }

        is VLMUiState.Error -> {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "Something went wrong",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = state.message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// -- Immersive full-screen VLM content --

@Composable
private fun ImmersiveVlmContent(
    state: VLMUiState.Ready,
    onRequestCameraPermission: () -> Unit,
    onPickPhoto: () -> Unit,
    onDescribeFrame: () -> Unit,
    onToggleLive: () -> Unit,
    onStopAutoStream: () -> Unit,
    onSelectModel: () -> Unit,
    onCancelGeneration: () -> Unit,
    onDismissResult: () -> Unit,
    onBindCamera: (PreviewView, androidx.lifecycle.LifecycleOwner) -> Unit,
) {
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()

    // Show result view when in single-shot result mode (not auto-streaming)
    if (state.showingResult && !state.isAutoStreamingEnabled) {
        ResultScreen(
            description = state.currentDescription,
            error = state.error,
            isProcessing = state.isProcessing,
            modelName = state.loadedModelName,
            onDismiss = onDismissResult,
            onCopy = {
                if (state.currentDescription.isNotEmpty()) {
                    scope.launch {
                        clipboard.setClipEntry(
                            ClipEntry(
                                android.content.ClipData.newPlainText(
                                    "description",
                                    state.currentDescription,
                                ),
                            ),
                        )
                    }
                }
            },
        )
        return
    }

    // Live camera mode
    val hasDescription = state.currentDescription.isNotEmpty()

    // Panel state management
    var panelState by remember { mutableStateOf(PanelState.Collapsed) }

    val panelHeight by animateDpAsState(
        targetValue = when (panelState) {
            PanelState.Collapsed -> PANEL_COLLAPSED_HEIGHT
            PanelState.Expanded -> PANEL_EXPANDED_HEIGHT
        },
        animationSpec = spring(
            dampingRatio = 0.8f,
            stiffness = Spring.StiffnessMediumLow,
        ),
        label = "panelHeight",
    )

    Box(modifier = Modifier.fillMaxSize()) {
        // Layer 1: Full-screen camera preview (edge-to-edge)
        FullScreenCameraPreview(
            state = state,
            onRequestPermission = onRequestCameraPermission,
            onBindCamera = onBindCamera,
        )

        // Layer 2: Processing shimmer overlay
        ProcessingShimmerOverlay(isVisible = state.isProcessing)

        // Layer 3: Top floating status bar
        TopStatusBar(
            modelName = state.loadedModelName,
            isAutoStreaming = state.isAutoStreamingEnabled,
            isProcessing = state.isProcessing,
        )

        // Layer 4: Bottom gradient scrim (always visible, gives depth)
        BottomGradientScrim()

        // Layer 5: Draggable description panel (only in live/auto-stream mode)
        DescriptionPanel(
            description = state.currentDescription,
            error = state.error,
            hasDescription = hasDescription,
            isAutoStreaming = state.isAutoStreamingEnabled,
            panelHeight = panelHeight,
            onDragUp = { panelState = PanelState.Expanded },
            onDragDown = { panelState = PanelState.Collapsed },
            onCopy = {
                if (state.currentDescription.isNotEmpty()) {
                    scope.launch {
                        clipboard.setClipEntry(
                            ClipEntry(
                                android.content.ClipData.newPlainText(
                                    "description",
                                    state.currentDescription,
                                ),
                            ),
                        )
                    }
                }
            },
        )

        // Layer 6: Floating control pill at the bottom
        FloatingControlPill(
            isProcessing = state.isProcessing,
            isAutoStreaming = state.isAutoStreamingEnabled,
            onPickPhoto = onPickPhoto,
            onDescribeFrame = onDescribeFrame,
            onStopAutoStream = onStopAutoStream,
            onToggleLive = onToggleLive,
            onSelectModel = onSelectModel,
        )
    }
}

// -- Result screen (camera closed, clean description card) --

@Composable
private fun ResultScreen(
    description: String,
    error: String?,
    isProcessing: Boolean,
    modelName: String?,
    onDismiss: () -> Unit,
    onCopy: () -> Unit,
) {
    val scrollState = rememberScrollState()

    // Auto-scroll as streaming text grows
    LaunchedEffect(description) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 20.dp, vertical = 16.dp),
        ) {
            // Top bar: back button + model name + copy
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = onDismiss,
                    modifier = Modifier.size(40.dp),
                ) {
                    Icon(
                        imageVector = RAIcons.ChevronLeft,
                        contentDescription = "Back to camera",
                        tint = MaterialTheme.colorScheme.onSurface,
                    )
                }

                Spacer(modifier = Modifier.width(8.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Analysis",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    if (modelName != null) {
                        Text(
                            text = modelName,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                // Copy button
                if (description.isNotEmpty()) {
                    IconButton(
                        onClick = onCopy,
                        modifier = Modifier.size(40.dp),
                    ) {
                        Icon(
                            imageVector = RAIcons.Copy,
                            contentDescription = "Copy",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Description content
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(scrollState),
            ) {
                when {
                    error != null -> {
                        Surface(
                            shape = MaterialTheme.shapes.medium,
                            color = MaterialTheme.colorScheme.errorContainer,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                modifier = Modifier.padding(16.dp),
                                verticalAlignment = Alignment.Top,
                            ) {
                                Icon(
                                    imageVector = RAIcons.AlertCircle,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error,
                                    modifier = Modifier.size(20.dp),
                                )
                                Spacer(modifier = Modifier.width(12.dp))
                                Text(
                                    text = error,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onErrorContainer,
                                )
                            }
                        }
                    }

                    description.isNotEmpty() -> {
                        MarkdownText(
                            text = description,
                            style = MaterialTheme.typography.bodyLarge.copy(
                                lineHeight = MaterialTheme.typography.bodyLarge.lineHeight * 1.3f,
                            ),
                        )

                        // Streaming indicator
                        if (isProcessing) {
                            Spacer(modifier = Modifier.height(12.dp))
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(14.dp),
                                    strokeWidth = 1.5.dp,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                                Text(
                                    text = "Generating...",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }

                    isProcessing -> {
                        // Processing but no text yet
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 48.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(32.dp),
                                strokeWidth = 3.dp,
                                color = MaterialTheme.colorScheme.primary,
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Text(
                                text = "Analyzing image...",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // Bottom: New capture button
            Spacer(modifier = Modifier.height(16.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .padding(bottom = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                GlassButton(
                    text = "New Capture",
                    onClick = onDismiss,
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                )
            }
        }
    }
}

// -- Full-screen camera preview --

@Composable
private fun BoxScope.FullScreenCameraPreview(
    state: VLMUiState.Ready,
    onRequestPermission: () -> Unit,
    onBindCamera: (PreviewView, androidx.lifecycle.LifecycleOwner) -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        if (state.isCameraAuthorized) {
            val context = LocalContext.current
            val lifecycleOwner = LocalLifecycleOwner.current
            val previewView = remember {
                PreviewView(context).apply {
                    scaleType = PreviewView.ScaleType.FILL_CENTER
                    implementationMode = PreviewView.ImplementationMode.PERFORMANCE
                }
            }

            DisposableEffect(lifecycleOwner) {
                onBindCamera(previewView, lifecycleOwner)
                onDispose { }
            }

            AndroidView(
                factory = { previewView },
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            ImmersiveCameraPermissionView(onRequestPermission = onRequestPermission)
        }
    }
}

// -- Immersive camera permission view --

@Composable
private fun ImmersiveCameraPermissionView(onRequestPermission: () -> Unit) {
    val context = LocalContext.current

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
        modifier = Modifier.padding(48.dp),
    ) {
        // Camera icon with subtle glow
        Box(contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f)),
            )
            Icon(
                imageVector = RAIcons.Camera,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.7f),
                modifier = Modifier.size(36.dp),
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            "Camera Access",
            color = Color.White,
            style = MaterialTheme.typography.titleLarge,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Grant camera access to analyze what you see in real time.",
            color = Color.White.copy(alpha = 0.6f),
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Pill-shaped grant button
        GlassButton(
            text = "Grant Permission",
            onClick = onRequestPermission,
            containerColor = Color.White.copy(alpha = 0.15f),
            contentColor = Color.White,
        )

        Spacer(modifier = Modifier.height(12.dp))

        GlassButton(
            text = "Open Settings",
            onClick = {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", context.packageName, null)
                }
                context.startActivity(intent)
            },
            containerColor = Color.Transparent,
            contentColor = Color.White.copy(alpha = 0.5f),
        )
    }
}

// -- Processing shimmer overlay --

@Composable
private fun BoxScope.ProcessingShimmerOverlay(isVisible: Boolean) {
    val alpha by animateFloatAsState(
        targetValue = if (isVisible) 1f else 0f,
        animationSpec = AppMotion.tweenMedium(),
        label = "shimmerAlpha",
    )

    if (alpha > 0f) {
        val infiniteTransition = rememberInfiniteTransition(label = "shimmer")
        val shimmerOffset by infiniteTransition.animateFloat(
            initialValue = -1f,
            targetValue = 2f,
            animationSpec = infiniteRepeatable(
                animation = tween(2000, easing = LinearEasing),
                repeatMode = RepeatMode.Restart,
            ),
            label = "shimmerOffset",
        )

        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { this.alpha = alpha * 0.3f }
                .drawBehind {
                    val shimmerWidth = size.width * 0.5f
                    val start = size.width * shimmerOffset
                    drawRect(
                        brush = Brush.linearGradient(
                            colors = listOf(
                                Color.Transparent,
                                Color.White.copy(alpha = 0.15f),
                                Color.Transparent,
                            ),
                            start = Offset(start, 0f),
                            end = Offset(start + shimmerWidth, size.height),
                        ),
                    )
                },
        )
    }
}

// -- Top floating status bar --

@Composable
private fun BoxScope.TopStatusBar(
    modelName: String?,
    isAutoStreaming: Boolean,
    isProcessing: Boolean,
) {
    Row(
        modifier = Modifier
            .align(Alignment.TopCenter)
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Model name chip
        modelName?.let { name ->
            Surface(
                shape = RoundedCornerShape(50),
                color = Color.Black.copy(alpha = 0.4f),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Icon(
                        imageVector = RAIcons.Cpu,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.7f),
                        modifier = Modifier.size(14.dp),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = name,
                        color = Color.White.copy(alpha = 0.9f),
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        } ?: Spacer(modifier = Modifier.width(1.dp))

        // LIVE badge + processing indicator
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Processing indicator
            AnimatedVisibility(
                visible = isProcessing,
                enter = fadeIn(AppMotion.tweenShort()) + scaleIn(
                    animationSpec = AppMotion.tweenShort(),
                    initialScale = 0.8f,
                ),
                exit = fadeOut(AppMotion.tweenShort()) + scaleOut(
                    animationSpec = AppMotion.tweenShort(),
                    targetScale = 0.8f,
                ),
            ) {
                Surface(
                    shape = RoundedCornerShape(50),
                    color = Color.Black.copy(alpha = 0.4f),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                    ) {
                        CircularProgressIndicator(
                            color = Color.White,
                            modifier = Modifier.size(12.dp),
                            strokeWidth = 1.5.dp,
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            "Analyzing",
                            color = Color.White.copy(alpha = 0.9f),
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                }
            }

            // LIVE badge
            AnimatedVisibility(
                visible = isAutoStreaming,
                enter = fadeIn(AppMotion.tweenShort()) + scaleIn(
                    animationSpec = spring(
                        dampingRatio = Spring.DampingRatioMediumBouncy,
                        stiffness = Spring.StiffnessMedium,
                    ),
                    initialScale = 0.5f,
                ),
                exit = fadeOut(AppMotion.tweenShort()) + scaleOut(
                    animationSpec = AppMotion.tweenShort(),
                    targetScale = 0.5f,
                ),
            ) {
                val pulseTransition = rememberInfiniteTransition(label = "livePulse")
                val pulseAlpha by pulseTransition.animateFloat(
                    initialValue = 0.7f,
                    targetValue = 1f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(800, easing = LinearEasing),
                        repeatMode = RepeatMode.Reverse,
                    ),
                    label = "pulseAlpha",
                )

                Surface(
                    shape = RoundedCornerShape(50),
                    color = Color(0xFFFF3B30).copy(alpha = 0.9f),
                    modifier = Modifier.graphicsLayer { alpha = pulseAlpha },
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(Color.White),
                        )
                        Spacer(modifier = Modifier.width(5.dp))
                        Text(
                            "LIVE",
                            color = Color.White,
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                }
            }
        }
    }
}

// -- Bottom gradient scrim --

@Composable
private fun BoxScope.BottomGradientScrim() {
    Box(
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .fillMaxWidth()
            .height(300.dp)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.Transparent,
                        Color.Black.copy(alpha = 0.6f),
                        Color.Black.copy(alpha = 0.85f),
                    ),
                ),
            ),
    )
}

// -- Draggable description panel --

@Composable
private fun BoxScope.DescriptionPanel(
    description: String,
    error: String?,
    hasDescription: Boolean,
    isAutoStreaming: Boolean,
    panelHeight: androidx.compose.ui.unit.Dp,
    onDragUp: () -> Unit,
    onDragDown: () -> Unit,
    onCopy: () -> Unit,
) {
    val density = LocalDensity.current

    // Panel visibility: show when there's content, error, or auto-streaming
    val showPanel by remember(hasDescription, error, isAutoStreaming) {
        derivedStateOf { hasDescription || error != null || isAutoStreaming }
    }

    val panelAlpha by animateFloatAsState(
        targetValue = if (showPanel) 1f else 0f,
        animationSpec = AppMotion.tweenMedium(),
        label = "panelAlpha",
    )

    // Slide-up offset
    val panelOffsetY by animateFloatAsState(
        targetValue = if (showPanel) 0f else with(density) { 100.dp.toPx() },
        animationSpec = spring(
            dampingRatio = 0.85f,
            stiffness = Spring.StiffnessMediumLow,
        ),
        label = "panelOffsetY",
    )

    // Drag accumulator
    var dragAccumulated by remember { mutableFloatStateOf(0f) }

    Box(
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .fillMaxWidth()
            .offset { IntOffset(0, panelOffsetY.roundToInt()) }
            .graphicsLayer { alpha = panelAlpha }
            // Leave space for the control pill below
            .padding(bottom = 100.dp)
            .windowInsetsPadding(WindowInsets.navigationBars),
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .height(panelHeight)
                .padding(horizontal = 12.dp)
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragStart = { dragAccumulated = 0f },
                        onDragEnd = {
                            if (dragAccumulated < -DRAG_THRESHOLD) onDragUp()
                            else if (dragAccumulated > DRAG_THRESHOLD) onDragDown()
                        },
                        onDragCancel = { dragAccumulated = 0f },
                    ) { _, dragAmount ->
                        dragAccumulated += dragAmount.y
                    }
                },
            shape = RoundedCornerShape(PANEL_CORNER_RADIUS),
            color = Color.Black.copy(alpha = 0.55f),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
            ) {
                // Drag handle
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .width(36.dp)
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(Color.White.copy(alpha = 0.3f)),
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Header row
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Description",
                        color = Color.White.copy(alpha = 0.6f),
                        style = MaterialTheme.typography.labelMedium,
                    )

                    // Copy button
                    AnimatedVisibility(
                        visible = hasDescription,
                        enter = fadeIn(AppMotion.tweenShort()) + scaleIn(
                            animationSpec = AppMotion.tweenShort(),
                            initialScale = 0.8f,
                        ),
                        exit = fadeOut(AppMotion.tweenShort()),
                    ) {
                        GlassIconButton(
                            icon = RAIcons.Copy,
                            contentDescription = "Copy",
                            onClick = onCopy,
                            size = 28.dp,
                            iconSize = 14.dp,
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Description text with scroll
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState()),
                ) {
                    when {
                        error != null -> {
                            Text(
                                error,
                                color = Color(0xFFFF6B6B),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                        description.isNotEmpty() -> {
                            Text(
                                description,
                                color = Color.White.copy(alpha = 0.95f),
                                style = MaterialTheme.typography.bodyMedium,
                                lineHeight = MaterialTheme.typography.bodyMedium.lineHeight,
                            )
                        }
                        isAutoStreaming -> {
                            Text(
                                "Analyzing what you see...",
                                color = Color.White.copy(alpha = 0.4f),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                }
            }
        }
    }
}

// -- Floating control pill --

@Composable
private fun BoxScope.FloatingControlPill(
    isProcessing: Boolean,
    isAutoStreaming: Boolean,
    onPickPhoto: () -> Unit,
    onDescribeFrame: () -> Unit,
    onStopAutoStream: () -> Unit,
    onToggleLive: () -> Unit,
    onSelectModel: () -> Unit,
) {
    Box(
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(bottom = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            shape = RoundedCornerShape(50),
            color = Color.Black.copy(alpha = 0.55f),
            modifier = Modifier.padding(horizontal = 24.dp),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Gallery button
                PillActionButton(
                    icon = RAIcons.FileText,
                    contentDescription = "Gallery",
                    enabled = !isProcessing,
                    onClick = onPickPhoto,
                )

                // Live toggle button
                PillActionButton(
                    icon = RAIcons.Play,
                    contentDescription = if (isAutoStreaming) "Stop Live" else "Live",
                    enabled = true,
                    isActive = isAutoStreaming,
                    activeColor = Color(0xFFFF3B30),
                    onClick = onToggleLive,
                )

                Spacer(modifier = Modifier.width(4.dp))

                // Main capture/analyze button (large)
                MainCaptureButton(
                    isProcessing = isProcessing,
                    isAutoStreaming = isAutoStreaming,
                    onClick = {
                        if (isAutoStreaming) onStopAutoStream() else onDescribeFrame()
                    },
                )

                Spacer(modifier = Modifier.width(4.dp))

                // Camera flip / model selector
                PillActionButton(
                    icon = RAIcons.Cpu,
                    contentDescription = "Model",
                    enabled = true,
                    onClick = onSelectModel,
                )
            }
        }
    }
}

// -- Main capture button (large, center) --

@Composable
private fun MainCaptureButton(
    isProcessing: Boolean,
    isAutoStreaming: Boolean,
    onClick: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    val scale by animateFloatAsState(
        targetValue = when {
            pressed -> 0.88f
            isProcessing && !isAutoStreaming -> 0.95f
            else -> 1f
        },
        animationSpec = spring(
            dampingRatio = 0.6f,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "captureScale",
    )

    val buttonColor = when {
        isAutoStreaming -> Color(0xFFFF3B30)
        isProcessing -> Color.White.copy(alpha = 0.15f)
        else -> MaterialTheme.colorScheme.primary
    }

    IconButton(
        onClick = onClick,
        enabled = !isProcessing || isAutoStreaming,
        interactionSource = interactionSource,
        modifier = Modifier
            .size(60.dp)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clip(CircleShape)
            .background(buttonColor),
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = Color.Transparent,
            contentColor = Color.White,
            disabledContainerColor = Color.Transparent,
            disabledContentColor = Color.White.copy(alpha = 0.4f),
        ),
    ) {
        AnimatedContent(
            targetState = when {
                isProcessing && !isAutoStreaming -> "loading"
                isAutoStreaming -> "stop"
                else -> "analyze"
            },
            transitionSpec = {
                (fadeIn(AppMotion.tweenShort()) + scaleIn(
                    animationSpec = spring(
                        dampingRatio = Spring.DampingRatioMediumBouncy,
                        stiffness = Spring.StiffnessMedium,
                    ),
                    initialScale = 0.7f,
                )).togetherWith(
                    fadeOut(AppMotion.tweenShort()) + scaleOut(
                        animationSpec = AppMotion.tweenShort(),
                        targetScale = 0.7f,
                    ),
                )
            },
            label = "captureIcon",
        ) { state ->
            when (state) {
                "loading" -> CircularProgressIndicator(
                    color = Color.White,
                    modifier = Modifier.size(24.dp),
                    strokeWidth = 2.dp,
                )
                "stop" -> Icon(
                    imageVector = RAIcons.Stop,
                    contentDescription = "Stop",
                    tint = Color.White,
                    modifier = Modifier.size(26.dp),
                )
                else -> Icon(
                    imageVector = RAIcons.Sparkles,
                    contentDescription = "Analyze",
                    tint = Color.White,
                    modifier = Modifier.size(26.dp),
                )
            }
        }
    }
}

// -- Pill action button (smaller, surrounding buttons) --

@Composable
private fun PillActionButton(
    icon: ImageVector,
    contentDescription: String,
    enabled: Boolean,
    isActive: Boolean = false,
    activeColor: Color = MaterialTheme.colorScheme.primary,
    onClick: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.85f else 1f,
        animationSpec = spring(
            dampingRatio = 0.6f,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "pillButtonScale",
    )

    val tint = when {
        isActive -> activeColor
        enabled -> Color.White.copy(alpha = 0.85f)
        else -> Color.White.copy(alpha = 0.3f)
    }

    IconButton(
        onClick = onClick,
        enabled = enabled,
        interactionSource = interactionSource,
        modifier = Modifier
            .size(44.dp)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            },
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = if (isActive) activeColor.copy(alpha = 0.2f) else Color.Transparent,
            contentColor = tint,
            disabledContainerColor = Color.Transparent,
            disabledContentColor = Color.White.copy(alpha = 0.3f),
        ),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            modifier = Modifier.size(22.dp),
        )
    }
}

// -- Glass-morphism button (for permission view) --

@Composable
private fun GlassButton(
    text: String,
    onClick: () -> Unit,
    containerColor: Color,
    contentColor: Color,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.95f else 1f,
        animationSpec = AppMotion.springSnappy(),
        label = "glassButtonScale",
    )

    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(50),
        color = containerColor,
        interactionSource = interactionSource,
        modifier = Modifier.graphicsLayer {
            scaleX = scale
            scaleY = scale
        },
    ) {
        Text(
            text = text,
            color = contentColor,
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
        )
    }
}

// -- Small glass icon button --

@Composable
private fun GlassIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    size: androidx.compose.ui.unit.Dp = 32.dp,
    iconSize: androidx.compose.ui.unit.Dp = 16.dp,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.85f else 1f,
        animationSpec = spring(
            dampingRatio = 0.6f,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "glassIconScale",
    )

    IconButton(
        onClick = onClick,
        interactionSource = interactionSource,
        modifier = Modifier
            .size(size)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.1f)),
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = Color.Transparent,
            contentColor = Color.White.copy(alpha = 0.7f),
        ),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            modifier = Modifier.size(iconSize),
        )
    }
}

// -- Model required full-screen view --

@Composable
private fun ModelRequiredFullScreen(onSelectModel: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.padding(48.dp),
        ) {
            // Glowing eye icon
            Box(contentAlignment = Alignment.Center) {
                Box(
                    modifier = Modifier
                        .size(96.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.05f)),
                )
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.05f)),
                )
                Icon(
                    imageVector = RAIcons.Eye,
                    contentDescription = null,
                    modifier = Modifier.size(36.dp),
                    tint = Color.White.copy(alpha = 0.5f),
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Vision AI",
                style = MaterialTheme.typography.headlineSmall,
                color = Color.White,
            )
            Text(
                text = "Select a vision model to analyze images and camera frames in real time.",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.5f),
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(8.dp))

            GlassButton(
                text = "Select Model",
                onClick = onSelectModel,
                containerColor = Color.White.copy(alpha = 0.12f),
                contentColor = Color.White,
            )
        }
    }
}
