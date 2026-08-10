package com.runanywhere.runanywhereai.ui.screens.segmentation

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.components.EmptyState
import com.runanywhere.runanywhereai.ui.components.EmptyStateAction
import com.runanywhere.runanywhereai.ui.components.ScreenLede
import com.runanywhere.runanywhereai.ui.components.SectionCard
import com.runanywhere.runanywhereai.ui.components.SectionHeader
import com.runanywhere.runanywhereai.ui.components.StatusNote
import com.runanywhere.runanywhereai.ui.components.StatusTone
import com.runanywhere.runanywhereai.ui.screens.models.ModelPickerCard
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

/**
 * Semantic image segmentation UI. Model selection uses the shared catalog
 * [ModelSelectionSheet] (same as iOS / STT / Vision). The file picker here is
 * only for the input image, never for model weights.
 */
@Composable
fun SegmentationScreen(viewModel: SegmentationViewModel = viewModel()) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val modelVm: ModelSelectionViewModel =
        viewModel(factory = ModelSelectionViewModel.Factory(ModelSelectionContext.SEGMENTATION))
    var showSheet by remember { mutableStateOf(false) }

    val model = modelVm.state.models.firstOrNull { it.id == modelVm.state.currentModelId }
    val modelLoaded = model != null
    val busy = modelVm.state.busyModelId != null

    // The Android photo picker rather than ACTION_GET_CONTENT: it needs no storage permission and
    // offers only images, so the user can never pick something this screen cannot decode.
    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
            }.onSuccess { bitmap ->
                if (bitmap != null) viewModel.onImagePicked(bitmap)
                else viewModel.reportError("Could not decode the selected image.")
            }.onFailure {
                viewModel.reportError("Could not read the selected image: ${it.message}")
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        ScreenLede(
            "Pick a segmentation model, then choose an image to label its regions on-device.",
        )

        // Lock the sheet during inference too: swapping the model under an
        // in-flight segmentation would pull native state out from under it.
        ModelPickerCard(
            label = "Segmentation model",
            model = model,
            icon = RACIcons.Outline.Layers,
            busy = busy,
            enabled = !(busy || viewModel.isSegmenting),
            onClick = { showSheet = true },
        )
        ImageCard(
            viewModel = viewModel,
            modelLoaded = modelLoaded,
            busy = busy,
            onPickImage = {
                imagePicker.launch(
                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                )
            },
        )

        AnimatedVisibility(
            visible = viewModel.classSummaries.isNotEmpty(),
            enter = fadeIn(AppMotion.standard()),
            exit = fadeOut(AppMotion.exit()),
        ) {
            ResultCard(viewModel)
        }

        viewModel.error?.let { StatusNote(it, StatusTone.ERROR) }
        if (viewModel.status.isNotEmpty()) StatusNote(viewModel.status, StatusTone.NEUTRAL)
    }

    if (showSheet) {
        ModelSelectionSheet(viewModel = modelVm, onDismiss = { showSheet = false })
    }
}

@Composable
private fun ImageCard(
    viewModel: SegmentationViewModel,
    modelLoaded: Boolean,
    busy: Boolean,
    onPickImage: () -> Unit,
) {
    val dimens = LocalDimens.current
    SectionCard {
        SectionHeader(title = "Image")

        val source = viewModel.sourceBitmap
        if (source != null) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(dimens.radiusMd)),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    bitmap = source.asImageBitmap(),
                    contentDescription = "Source image",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth(),
                )
                viewModel.maskBitmap?.let { mask ->
                    Image(
                        bitmap = mask.asImageBitmap(),
                        contentDescription = "Segmentation mask",
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxWidth()
                            .alpha(0.55f),
                    )
                }
            }
        } else {
            // Where a first-time user actually is. It names what segmentation produces,
            // because "no image selected" describes the app's state and not the user's goal.
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHighest,
                shape = RoundedCornerShape(dimens.radiusMd),
                modifier = Modifier.fillMaxWidth(),
            ) {
                EmptyState(
                    icon = RACIcons.Outline.Layers,
                    title = "No image yet",
                    body = if (modelLoaded) {
                        "Choose a photo and the model paints every region it recognises — " +
                            "sky, road, person — as a coloured mask over your image."
                    } else {
                        "Choose a segmentation model above first, then pick a photo to label " +
                            "its regions."
                    },
                    primaryAction = EmptyStateAction(
                        label = "Choose an image",
                        enabled = !viewModel.isSegmenting,
                        onClick = onPickImage,
                    ),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
            if (viewModel.sourceBitmap != null) {
                OutlinedButton(onClick = onPickImage, enabled = !viewModel.isSegmenting) {
                    Text("Change image…")
                }
            }
            Button(
                onClick = { viewModel.runSegmentation() },
                enabled = modelLoaded &&
                    !busy &&
                    viewModel.sourceBitmap != null &&
                    !viewModel.isSegmenting,
            ) {
                if (viewModel.isSegmenting) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(dimens.iconSm),
                            strokeWidth = 2.dp,
                        )
                        Text("Labelling…")
                    }
                } else {
                    Text("Run segmentation")
                }
            }
        }
        if (!modelLoaded && viewModel.sourceBitmap != null) {
            StatusNote(
                "Choose a segmentation model above to label this image.",
                StatusTone.NEUTRAL,
            )
        }
    }
}

@Composable
private fun ResultCard(viewModel: SegmentationViewModel) {
    SectionCard {
        SectionHeader(
            title = "Classes",
            status = viewModel.processingTimeMs.takeIf { it > 0 }?.let { "$it ms" },
        )
        viewModel.classSummaries.forEach { summary ->
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    summary.label.ifEmpty { "class ${summary.classId}" },
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    "${summary.pixelCount} px · ${"%.1f".format(summary.fraction * 100)}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
