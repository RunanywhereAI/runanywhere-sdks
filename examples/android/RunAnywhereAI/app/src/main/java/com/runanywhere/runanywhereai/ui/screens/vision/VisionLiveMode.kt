package com.runanywhere.runanywhereai.ui.screens.vision

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.permissions.PermissionRecoveryCard
import com.runanywhere.runanywhereai.ui.permissions.openRunAnywhereAppSettings
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Live mode: a back-camera preview whose frames are captioned by the loaded VLM.
 *
 * This file is the camera and the controls; [VisionLiveViewModel] is the loop. Everything the
 * user can be told about — permission not yet granted, permission refused, a device with no
 * camera, a bind that failed, a caption in flight, a caption stopped, a caption that failed —
 * is a state one of the two of them owns, because the previous version of this screen answered
 * all seven with the same black rectangle.
 */
@Composable
fun VisionLiveMode(loadedModelId: String?, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val liveVm: VisionLiveViewModel = viewModel()

    val deviceHasCamera = remember(context) { context.hasAnyCamera() }
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    // Distinguishes "we have not asked yet" from "the user said no", which the single
    // hasPermission flag could not: both rendered the same refusal copy.
    var permissionRefused by remember { mutableStateOf(false) }
    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        hasPermission = granted
        permissionRefused = !granted
    }

    val cameraProvider = remember { AtomicReference<ProcessCameraProvider?>(null) }
    val cameraBindingActive = remember { AtomicBoolean(true) }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }

    LaunchedEffect(deviceHasCamera, hasPermission) {
        when {
            !deviceHasCamera -> liveVm.onCameraUnavailable(
                "This device has no camera. Attach a photo from the Photo tab instead.",
            )
            !hasPermission -> permLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    LaunchedEffect(loadedModelId) { liveVm.onModelChanged(loadedModelId) }

    DisposableEffect(Unit) {
        cameraBindingActive.set(true)
        onDispose {
            // Release the camera when leaving Live mode — without unbindAll() the preview and
            // analyzer stay bound to the screen's lifecycle and keep the camera busy in the
            // background — and stop the loop, which outlives this composable.
            cameraBindingActive.set(false)
            cameraProvider.getAndSet(null)?.unbindAll()
            analysisExecutor.shutdown()
            liveVm.onLeaveLiveMode()
        }
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
        if (!deviceHasCamera) {
            LiveNoticeCard(
                message = (liveVm.cameraState as? LiveCameraState.Unavailable)?.message
                    ?: "This device has no camera.",
            )
            return@Column
        }

        if (!hasPermission) {
            if (permissionRefused) {
                PermissionRecoveryCard(
                    message = "Camera access was denied, so the live view cannot open. " +
                        "Enable it in Android settings, or attach a photo from the Photo tab.",
                    onOpenSettings = context::openRunAnywhereAppSettings,
                )
            } else {
                LiveNoticeCard(
                    message = "Camera access is needed for the live view.",
                    action = "Grant camera permission",
                    onAction = { permLauncher.launch(Manifest.permission.CAMERA) },
                    secondaryAction = "Open app settings",
                    onSecondaryAction = context::openRunAnywhereAppSettings,
                )
            }
            return@Column
        }

        CameraPreviewBox(
            state = liveVm.cameraState,
            analyzing = liveVm.status.isRunning,
            onFrame = liveVm.frames::offer,
            onReady = liveVm::onCameraReady,
            onUnavailable = liveVm::onCameraUnavailable,
            lifecycleOwner = lifecycleOwner,
            executor = analysisExecutor,
            providerOut = cameraProvider,
            bindingActive = cameraBindingActive,
        )

        LiveControls(
            captureMode = liveVm.captureMode,
            status = liveVm.status,
            enabled = liveVm.cameraState is LiveCameraState.Ready && loadedModelId != null,
            onSetAuto = liveVm::setAutoCapture,
            onCaptureOnce = liveVm::captureOnce,
            onStop = liveVm::stop,
        )

        LiveStatusRow(status = liveVm.status, metrics = liveVm.lastMetrics)

        // Live captions run on a deliberately tight token budget, so hitting it is routine —
        // and a caption that ends mid-word without explanation reads as a broken model.
        (liveVm.status as? VisionRunStatus.Done)?.takeIf { it.truncated }?.let {
            Text(
                text = "Caption reached its length limit.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = liveVm.caption.ifBlank { liveEmptyCaption(loadedModelId, liveVm) },
                style = MaterialTheme.typography.bodyLarge,
                color = if (liveVm.caption.isBlank()) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                modifier = Modifier.padding(dimens.spacingLg),
            )
        }
    }
}

/** What the caption pane says before the model has produced anything. */
private fun liveEmptyCaption(loadedModelId: String?, liveVm: VisionLiveViewModel): String = when {
    loadedModelId == null -> "Choose a vision model above to start captioning."
    liveVm.cameraState is LiveCameraState.Starting -> "Starting the camera…"
    liveVm.captureMode == LiveCaptureMode.MANUAL -> "Point the camera at a scene, then Capture now."
    else -> "Point the camera at a scene…"
}

@Composable
private fun CameraPreviewBox(
    state: LiveCameraState,
    analyzing: Boolean,
    onFrame: ((() -> Bitmap?) -> Unit),
    onReady: () -> Unit,
    onUnavailable: (String) -> Unit,
    lifecycleOwner: androidx.lifecycle.LifecycleOwner,
    executor: java.util.concurrent.Executor,
    providerOut: AtomicReference<ProcessCameraProvider?>,
    bindingActive: AtomicBoolean,
) {
    val dimens = LocalDimens.current
    Box(
        Modifier
            .fillMaxWidth()
            .height(PREVIEW_HEIGHT)
            .clip(RoundedCornerShape(dimens.radiusLg))
            .background(Color.Black),
    ) {
        AndroidView(
            factory = { ctx ->
                PreviewView(ctx).also { view ->
                    view.scaleType = PreviewView.ScaleType.FILL_CENTER
                    bindCamera(
                        context = ctx,
                        lifecycleOwner = lifecycleOwner,
                        previewView = view,
                        onFrame = onFrame,
                        executor = executor,
                        providerOut = providerOut,
                        bindingActive = bindingActive,
                        onReady = onReady,
                        onUnavailable = onUnavailable,
                    )
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .semantics { contentDescription = "Live camera preview" },
        )

        when (state) {
            is LiveCameraState.Unavailable -> PreviewOverlayMessage(
                icon = RACIcons.Outline.AlertTriangle,
                text = state.message,
                modifier = Modifier.align(Alignment.Center),
            )
            LiveCameraState.Starting -> PreviewOverlayMessage(
                icon = RACIcons.Outline.Camera,
                text = "Starting the camera…",
                modifier = Modifier.align(Alignment.Center),
            )
            LiveCameraState.Ready -> {
                // The LIVE badge only appears once frames are genuinely arriving; it used to sit
                // on top of a camera that had failed to bind.
                ScrimPill(modifier = Modifier.align(Alignment.TopStart).padding(dimens.spacingSm)) {
                    Box(Modifier.size(LIVE_DOT).clip(CircleShape).background(primaryGreen))
                    Text("LIVE", color = Color.White, style = MaterialTheme.typography.labelMedium)
                }
            }
        }

        if (analyzing && state is LiveCameraState.Ready) {
            ScrimPill(modifier = Modifier.align(Alignment.BottomStart).padding(dimens.spacingSm)) {
                CircularProgressIndicator(
                    Modifier.size(SPINNER_SIZE),
                    color = Color.White,
                    strokeWidth = 2.dp,
                )
                Text("Analyzing…", color = Color.White, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

/** A dark pill for text that has to stay legible over an arbitrary camera image. */
@Composable
private fun ScrimPill(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Row(
        modifier
            .clip(RoundedCornerShape(SCRIM_RADIUS))
            .background(PREVIEW_SCRIM)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) { content() }
}

@Composable
private fun PreviewOverlayMessage(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = modifier.padding(dimens.spacingLg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(dimens.iconLg))
        Text(
            text = text,
            color = Color.White,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

/**
 * Auto/single-shot, and the one button that starts or stops a caption.
 *
 * The button label is derived rather than fixed so it can never promise something the loop will
 * not do: "Capture now" while a continuous loop is already cycling would be a control that does
 * nothing, so continuous mode offers Stop instead.
 */
@Composable
private fun LiveControls(
    captureMode: LiveCaptureMode,
    status: VisionRunStatus,
    enabled: Boolean,
    onSetAuto: (Boolean) -> Unit,
    onCaptureOnce: () -> Unit,
    onStop: () -> Unit,
) {
    val dimens = LocalDimens.current
    val auto = captureMode == LiveCaptureMode.CONTINUOUS
    val running = status.isRunning
    val stopping = status is VisionRunStatus.Stopping
    val stops = running || auto

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FilterChip(
            selected = auto,
            onClick = { onSetAuto(!auto) },
            enabled = enabled && !stopping,
            label = { Text("Auto") },
        )
        Button(
            onClick = { if (stops) onStop() else onCaptureOnce() },
            enabled = enabled && !stopping,
            modifier = Modifier.weight(1f),
        ) {
            Icon(
                imageVector = if (stops) RACIcons.Outline.PlayerStop else RACIcons.Outline.Camera,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
            Text(
                text = when {
                    stopping -> "Stopping…"
                    running -> "Stop"
                    auto -> "Stop auto captions"
                    else -> "Capture now"
                },
                modifier = Modifier.padding(start = dimens.spacingSm),
            )
        }
    }
}

/** One line for whatever the last caption attempt did, including the outcomes with no text. */
@Composable
private fun LiveStatusRow(status: VisionRunStatus, metrics: VlmMetrics?) {
    val label: String
    val value: String
    when (status) {
        VisionRunStatus.Idle -> {
            label = "tokens/s"
            value = metrics?.let { formatTokensPerSecond(it.tokensPerSecond) } ?: "—"
        }
        VisionRunStatus.Running -> {
            label = "tokens/s"
            value = "captioning…"
        }
        VisionRunStatus.Stopping -> {
            label = "tokens/s"
            value = "stopping…"
        }
        is VisionRunStatus.Done -> {
            label = "tokens/s"
            value = formatTokensPerSecond(status.metrics.tokensPerSecond)
        }
        VisionRunStatus.Cancelled -> {
            label = "Last caption"
            value = "stopped"
        }
        is VisionRunStatus.Failed -> {
            Text(
                text = status.message,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.fillMaxWidth(),
            )
            return
        }
    }
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

private fun formatTokensPerSecond(rate: Double): String =
    if (rate > 0) String.format(Locale.US, "%.1f", rate) else "—"

/** A neutral card for the states where the camera is not the problem the user can fix here. */
@Composable
private fun LiveNoticeCard(
    message: String,
    action: String? = null,
    onAction: (() -> Unit)? = null,
    secondaryAction: String? = null,
    onSecondaryAction: (() -> Unit)? = null,
) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Text(message, style = MaterialTheme.typography.bodyMedium)
            if (action != null && onAction != null) {
                Button(onClick = onAction) { Text(action) }
            }
            if (secondaryAction != null && onSecondaryAction != null) {
                TextButton(onClick = onSecondaryAction) { Text(secondaryAction) }
            }
        }
    }
}

/**
 * Binds a back-camera [Preview] + [ImageAnalysis] to [lifecycleOwner].
 *
 * The analyzer hands each frame to [onFrame] as an *unevaluated* conversion, so the sink decides
 * whether the bitmap is worth materialising. [onReady]/[onUnavailable] report the outcome to the
 * caller — a bind failure used to be swallowed here, leaving a black preview and no explanation.
 */
private fun bindCamera(
    context: Context,
    lifecycleOwner: androidx.lifecycle.LifecycleOwner,
    previewView: PreviewView,
    onFrame: ((() -> Bitmap?) -> Unit),
    executor: java.util.concurrent.Executor,
    providerOut: AtomicReference<ProcessCameraProvider?>,
    bindingActive: AtomicBoolean,
    onReady: () -> Unit,
    onUnavailable: (String) -> Unit,
) {
    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({
        if (!bindingActive.get()) return@addListener
        val provider = try {
            future.get()
        } catch (_: Exception) {
            onUnavailable("The camera service is unavailable on this device.")
            return@addListener
        }
        val preview = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }
        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also {
                it.setAnalyzer(executor) { proxy ->
                    try {
                        onFrame { rotatedBitmap(proxy) }
                    } finally {
                        proxy.close()
                    }
                }
            }
        try {
            if (!bindingActive.get()) return@addListener
            provider.unbindAll()
            provider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                analysis,
            )
            if (bindingActive.get()) {
                providerOut.set(provider)
                onReady()
            } else {
                // The provider future can complete after the composable leaves Live mode. Undo
                // that late bind instead of retaining the camera until the activity is destroyed.
                provider.unbind(preview, analysis)
            }
        } catch (_: Exception) {
            // No back camera, or another app holds it. Emulators without a configured camera
            // land here, and so does a device whose camera is in use elsewhere.
            onUnavailable("No camera could be opened. Another app may be using it.")
        }
    }, ContextCompat.getMainExecutor(context))
}

/** The frame the analyzer produced, turned upright. Null when the frame cannot be converted. */
private fun rotatedBitmap(proxy: androidx.camera.core.ImageProxy): Bitmap? =
    try {
        val bitmap = proxy.toBitmap()
        val rotation = proxy.imageInfo.rotationDegrees
        if (rotation == 0) {
            bitmap
        } else {
            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }
    } catch (_: Exception) {
        null
    }

private val PREVIEW_HEIGHT = 300.dp
private val LIVE_DOT = 8.dp
private val SPINNER_SIZE = 12.dp
private val SCRIM_RADIUS = 6.dp

/** Fixed scrim, not a theme token: it sits over camera pixels, not over app surface. */
private val PREVIEW_SCRIM = Color(0xCC000000)
