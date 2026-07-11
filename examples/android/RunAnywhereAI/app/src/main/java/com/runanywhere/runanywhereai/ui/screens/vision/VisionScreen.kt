package com.runanywhere.runanywhereai.ui.screens.vision

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.screens.chat.MarkdownText
import com.runanywhere.runanywhereai.ui.screens.models.BackendBadge
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.permissions.PermissionRecoveryCard
import com.runanywhere.runanywhereai.ui.permissions.openRunAnywhereAppSettings
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.util.readableWidth
import com.runanywhere.sdk.public.types.RAModelInfo
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

    val model = modelVm.state.models.firstOrNull { it.id == modelVm.state.currentModelId }

    var liveMode by remember(openLiveCamera) { mutableStateOf(openLiveCamera) }

    val galleryLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { visionVm.onImagePicked(decodeBitmap(context, it)) }
    }
    val cameraLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bitmap ->
        visionVm.onImagePicked(bitmap)
    }
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

    val canDescribe = model != null && visionVm.image != null && !visionVm.isGenerating

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            Text("Images & Live", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Attach a photo, capture one, or open live camera mode with an on-device vision model.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        ModelCard(
            model = model,
            enabled = !visionVm.isGenerating,
            onClick = { showSheet = true },
        )

        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            FilterChip(selected = !liveMode, onClick = { liveMode = false }, label = { Text("Photo") })
            FilterChip(
                selected = liveMode,
                onClick = { liveMode = true },
                enabled = !visionVm.isGenerating,
                label = { Text("Live camera") },
            )
        }

        if (liveMode) {
            // The model-selection sheet at the end of VisionScreen still composes.
            VisionLiveMode(loadedModelId = model?.id)
            return@Column
        }

        ImagePreview(bitmap = visionVm.image)

        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
            OutlinedButton(onClick = { galleryLauncher.launch("image/*") }, modifier = Modifier.weight(1f)) {
                Text("Gallery")
            }
            OutlinedButton(onClick = { onCapture() }, modifier = Modifier.weight(1f)) {
                Text("Camera")
            }
        }

        OutlinedTextField(
            value = visionVm.prompt,
            onValueChange = visionVm::onPromptChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Prompt") },
            minLines = 2,
            maxLines = 4,
        )

        Button(
            onClick = { if (visionVm.isGenerating) visionVm.stop() else visionVm.describe() },
            enabled = visionVm.isGenerating || canDescribe,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(
                imageVector = if (visionVm.isGenerating) RACIcons.Outline.PlayerStop else RACIcons.Outline.Eye,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
            Text(
                text = if (visionVm.isGenerating) "Stop" else "Ask about image",
                modifier = Modifier.padding(start = dimens.spacingSm),
            )
        }

        if (visionVm.isGenerating && visionVm.description.isBlank()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(modifier = Modifier.size(dimens.iconMd), strokeWidth = 2.dp)
                Text(
                    text = "Analyzing image…",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = dimens.spacingSm),
                )
            }
        }

        if (visionVm.description.isNotBlank()) {
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shape = RoundedCornerShape(dimens.radiusLg),
                modifier = Modifier.fillMaxWidth(),
            ) {
                MarkdownText(
                    markdown = visionVm.description,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(dimens.spacingLg),
                )
            }
        }
        visionVm.metrics?.let { StatsCard(it) }

        visionVm.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
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

@Composable
private fun ImagePreview(bitmap: Bitmap?) {
    val dimens = LocalDimens.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(240.dp)
            .clip(RoundedCornerShape(dimens.radiusLg))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "Selected image",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
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
}

@Composable
private fun ModelCard(model: RAModelInfo?, enabled: Boolean, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .clickable(enabled = enabled, onClick = onClick)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = RACIcons.Outline.Eye,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                Text("Image model", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(model?.name ?: "Select a model", style = MaterialTheme.typography.bodyLarge)
                model?.let {
                    BackendBadge(framework = it.framework, compact = true)
                }
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

@Composable
private fun StatsCard(metrics: VlmMetrics) {
    val dimens = LocalDimens.current
    val rows = buildList {
        add("Tokens" to metrics.tokens.toString())
        if (metrics.tokensPerSecond > 0) add("Speed" to String.format(Locale.US, "%.1f tok/s", metrics.tokensPerSecond))
        add("Processing" to String.format(Locale.US, "%.1fs", metrics.processingMs / 1000.0))
        if (metrics.imageEncodeMs > 0) add("Image encode" to "${metrics.imageEncodeMs}ms")
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

private fun decodeBitmap(context: Context, uri: Uri): Bitmap? = runCatching {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
        return@runCatching context.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
    }
    val source = ImageDecoder.createSource(context.contentResolver, uri)
    ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        decoder.isMutableRequired = false
    }
}.getOrNull()
