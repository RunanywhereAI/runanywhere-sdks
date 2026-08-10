package com.runanywhere.runanywhereai.ui.screens.vision

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.components.ScreenLede
import com.runanywhere.runanywhereai.ui.permissions.PermissionRecoveryCard
import com.runanywhere.runanywhereai.ui.permissions.openRunAnywhereAppSettings
import com.runanywhere.runanywhereai.ui.screens.chat.MarkdownText
import com.runanywhere.runanywhereai.ui.screens.models.ModelPickerCard
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.util.readableWidth
import java.util.Locale

@Composable
fun VisionScreen(openLiveCamera: Boolean = false) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val visionVm: VisionViewModel = viewModel()
    val modelVm: ModelSelectionViewModel =
        viewModel(factory = ModelSelectionViewModel.Factory(ModelSelectionContext.VLM))
    var showSheet by remember { mutableStateOf(false) }
    var cameraPermissionDenied by remember { mutableStateOf(false) }
    val resultRequester = remember { BringIntoViewRequester() }

    val model = modelVm.state.models.firstOrNull { it.id == modelVm.state.currentModelId }
    val busy = visionVm.status.isBusy
    val deviceHasCamera = remember(context) { context.hasAnyCamera() }

    var liveMode by remember(openLiveCamera) { mutableStateOf(openLiveCamera) }

    // The Android photo picker rather than ACTION_GET_CONTENT: no storage permission, photos only,
    // and the Compat contract falls back to a document picker on devices without the system one.
    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        // A cancelled pick returns null and must leave the staged image alone; anything else is
        // pre-flighted against the same policy the chat composer uses.
        uri?.let(visionVm::onImagePicked)
    }
    val cameraLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicturePreview(),
    ) { bitmap -> visionVm.onImageCaptured(bitmap) }
    // CAMERA is declared in the manifest (for Live mode), which makes the runtime
    // grant mandatory for the system-camera capture intent too.
    val captureWithGrant = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        cameraPermissionDenied = !granted
        if (granted) cameraLauncher.launch(null)
    }

    fun onCapture() {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            cameraPermissionDenied = false
            cameraLauncher.launch(null)
        } else {
            captureWithGrant.launch(Manifest.permission.CAMERA)
        }
    }

    val canDescribe = model != null && visionVm.image != null &&
        visionVm.prompt.isNotBlank() && !busy && !visionVm.isPreparingImage

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        ScreenLede(
            "Attach a photo, capture one, or open live camera mode with an on-device " +
                "vision model.",
        )

        ModelPickerCard(
            label = "Image model",
            model = model,
            icon = RACIcons.Outline.Eye,
            enabled = !busy,
            onClick = { showSheet = true },
        )

        // Named rather than implied by a greyed-out button. "Ask about image" being dim says
        // nothing about which of the three preconditions is missing, and no model is the one
        // the user cannot guess.
        if (model == null) {
            VisionNoticeStrip(
                message = "No vision model is loaded.",
                detail = "Choose one above — it downloads once, then runs on this device.",
                onClick = { showSheet = true },
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            FilterChip(selected = !liveMode, onClick = { liveMode = false }, label = { Text("Photo") })
            FilterChip(
                selected = liveMode,
                onClick = { liveMode = true },
                enabled = !busy,
                label = { Text("Live camera") },
            )
        }

        if (liveMode) {
            // The model-selection sheet at the end of VisionScreen still composes.
            VisionLiveMode(loadedModelId = model?.id)
            return@Column
        }

        ImagePreview(
            image = visionVm.image,
            preparing = visionVm.isPreparingImage,
            onClear = visionVm::clearImage.takeIf { !busy },
        )

        visionVm.imageRejection?.let { reason ->
            VisionRejectionStrip(reason = reason, onDismiss = visionVm::dismissImageRejection)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
            OutlinedButton(
                onClick = {
                    galleryLauncher.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                    )
                },
                enabled = !busy && !visionVm.isPreparingImage,
                modifier = Modifier.weight(1f),
            ) {
                Icon(RACIcons.Outline.Image, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
                Text("Gallery", modifier = Modifier.padding(start = dimens.spacingSm))
            }
            OutlinedButton(
                onClick = { onCapture() },
                // A capture button on a device with no camera throws ActivityNotFoundException
                // when tapped. Disabled here and explained below, rather than crashing.
                enabled = deviceHasCamera && !busy && !visionVm.isPreparingImage,
                modifier = Modifier.weight(1f),
            ) {
                Icon(RACIcons.Outline.Camera, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
                Text("Camera", modifier = Modifier.padding(start = dimens.spacingSm))
            }
        }

        if (!deviceHasCamera) {
            Text(
                "This device has no camera, so photos have to come from the gallery.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        OutlinedTextField(
            value = visionVm.prompt,
            onValueChange = visionVm::onPromptChange,
            modifier = Modifier.fillMaxWidth(),
            enabled = !busy,
            label = { Text("Prompt") },
            minLines = 2,
            maxLines = 4,
        )

        Button(
            onClick = { if (visionVm.status.isRunning) visionVm.stop() else visionVm.describe() },
            enabled = visionVm.status.isRunning || canDescribe,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(
                imageVector = if (busy) RACIcons.Outline.PlayerStop else RACIcons.Outline.Eye,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
            Text(
                text = when {
                    visionVm.status is VisionRunStatus.Stopping -> "Stopping…"
                    visionVm.status.isRunning -> "Stop"
                    else -> "Ask about image"
                },
                modifier = Modifier.padding(start = dimens.spacingSm),
            )
        }

        // Only before the first token: once text is streaming, the text itself is the progress.
        if (visionVm.status.isBusy && visionVm.description.isBlank()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(modifier = Modifier.size(dimens.iconMd), strokeWidth = 2.dp)
                Text(
                    text = if (visionVm.status is VisionRunStatus.Stopping) {
                        "Stopping…"
                    } else {
                        "Analyzing image…"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = dimens.spacingSm),
                )
            }
        }

        val answer = visionVm.description
        val status = visionVm.status
        val hasResultBlock = answer.isNotBlank() ||
            status is VisionRunStatus.Done ||
            status is VisionRunStatus.Cancelled ||
            status is VisionRunStatus.Failed
        if (hasResultBlock) {
            // Scroll the answer into view when the run *settles*, not on every delta. Keying this
            // on the streamed text re-scrolls the column on each token, which both jitters the
            // page and drags the Stop button out from under the finger reaching for it — a
            // cancel control that moves while you aim at it is not a cancel control.
            LaunchedEffect(status) {
                if (!status.isBusy) resultRequester.bringIntoView()
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .bringIntoViewRequester(resultRequester),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
            ) {
                if (answer.isNotBlank()) {
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        shape = RoundedCornerShape(dimens.radiusLg),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        MarkdownText(
                            markdown = answer,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.padding(dimens.spacingLg),
                        )
                    }
                }
                when (status) {
                    is VisionRunStatus.Done -> {
                        // The budget that cut the answer off is ours, not the model's. Left
                        // unsaid, an answer ending mid-word reads as the model having failed.
                        if (status.truncated) {
                            Text(
                                text = "The answer reached this screen's length limit and stops " +
                                    "here. Ask a narrower question for a complete one.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        StatsCard(status.metrics)
                    }
                    VisionRunStatus.Cancelled -> Text(
                        text = if (answer.isBlank()) {
                            "Stopped before the model answered."
                        } else {
                            "Stopped — the answer above is incomplete."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    is VisionRunStatus.Failed -> Text(
                        text = status.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    else -> Unit
                }
            }
        }
        if (cameraPermissionDenied && !liveMode) {
            PermissionRecoveryCard(
                message = "Camera access was denied. Enable it in Android settings to capture photos.",
                onOpenSettings = context::openRunAnywhereAppSettings,
            )
        }
    }

    if (showSheet) {
        ModelSelectionSheet(viewModel = modelVm, onDismiss = { showSheet = false })
    }
}

/** The one thing standing between this screen and an answer, plus the tap that clears it. */
@Composable
private fun VisionNoticeStrip(message: String, detail: String, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = RACIcons.Outline.Model,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconSm),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(message, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    detail,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = RACIcons.Outline.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconSm),
            )
        }
    }
}

/**
 * The file this screen would not take, and why.
 *
 * Error-coloured, and dismissible rather than self-clearing: a pick that is silently dropped is
 * indistinguishable from a picker that never returned.
 */
@Composable
private fun VisionRejectionStrip(reason: String, onDismiss: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
    ) {
        Row(
            modifier = Modifier.padding(
                start = dimens.spacingMd,
                end = dimens.spacingXs,
                top = dimens.spacingXs,
                bottom = dimens.spacingXs,
            ),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                RACIcons.Outline.AlertTriangle,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
            Text(reason, style = MaterialTheme.typography.labelMedium, modifier = Modifier.weight(1f))
            IconButton(onClick = onDismiss, modifier = Modifier.size(DISMISS_TARGET)) {
                Icon(
                    RACIcons.Outline.Close,
                    contentDescription = "Dismiss",
                    modifier = Modifier.size(dimens.iconSm),
                )
            }
        }
    }
}

@Composable
private fun ImagePreview(
    image: StagedVisionImage?,
    preparing: Boolean,
    /** Null while a run holds the image — swapping it mid-inference is not offered. */
    onClear: (() -> Unit)?,
) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(PREVIEW_HEIGHT)
                .clip(RoundedCornerShape(dimens.radiusLg))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
            contentAlignment = Alignment.Center,
        ) {
            when {
                preparing -> Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(dimens.iconMd), strokeWidth = 2.dp)
                    Text(
                        "Opening image…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                image != null -> Image(
                    bitmap = image.bitmap.asImageBitmap(),
                    contentDescription = "Selected image: ${image.name}",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
                else -> Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                ) {
                    Icon(
                        imageVector = RACIcons.Outline.Eye,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(dimens.iconLg),
                    )
                    Text(
                        "Pick or capture an image",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        // The name below the frame, not over it: two photos from the same album crop to the
        // same rectangle, and the caption is the only way to tell which one is loaded.
        if (image != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            ) {
                Text(
                    text = image.name,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (onClear != null) {
                    IconButton(onClick = onClear, modifier = Modifier.size(DISMISS_TARGET)) {
                        Icon(
                            RACIcons.Outline.Close,
                            contentDescription = "Remove image",
                            modifier = Modifier.size(dimens.iconSm),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StatsCard(metrics: VlmMetrics) {
    val dimens = LocalDimens.current
    val rows = buildList {
        add("Tokens" to metrics.tokens.toString())
        if (metrics.tokensPerSecond > 0) add("Speed" to String.format(Locale.US, "%.1f tok/s", metrics.tokensPerSecond))
        add("Processing" to String.format(Locale.US, "%.1fs", metrics.processingMs / 1000.0))
        if (metrics.ttftMs > 0) add("Time to first token" to "${metrics.ttftMs}ms")
    }
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        Text("Stats", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(dimens.spacingLg),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            ) {
                rows.forEach { (label, value) ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(value, style = RACTextStyles.Metric)
                    }
                }
            }
        }
    }
}

private val PREVIEW_HEIGHT = 240.dp

/** Above the 44 dp coarse-pointer floor: these sit beside text the user is already aiming at. */
private val DISMISS_TARGET = 44.dp
