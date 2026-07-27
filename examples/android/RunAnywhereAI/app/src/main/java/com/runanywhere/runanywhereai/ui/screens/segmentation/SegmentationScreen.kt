package com.runanywhere.runanywhereai.ui.screens.segmentation

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
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
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.screens.models.BackendBadge
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo

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

    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
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
        Text(
            text = "Segmentation",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "Download SegFormer B0 from the catalog, then pick an image to segment classes on-device.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        ModelCard(model = model, onClick = { showSheet = true })
        ImageCard(
            viewModel = viewModel,
            modelLoaded = modelLoaded,
            onPickImage = { imagePicker.launch("image/*") },
        )

        if (viewModel.classSummaries.isNotEmpty()) {
            ResultCard(viewModel)
        }

        viewModel.error?.let { message ->
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        if (viewModel.status.isNotEmpty()) {
            Text(
                text = viewModel.status,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    if (showSheet) {
        ModelSelectionSheet(viewModel = modelVm, onDismiss = { showSheet = false })
    }
}

@Composable
private fun ModelCard(model: RAModelInfo?, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .clickable(onClick = onClick)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = RACIcons.Outline.Cpu,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                Text(
                    "Model",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    model?.name ?: "Select a model",
                    style = MaterialTheme.typography.bodyLarge,
                )
                model?.let { BackendBadge(framework = it.framework, compact = true) }
            }
            Icon(
                imageVector = RACIcons.Outline.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ImageCard(
    viewModel: SegmentationViewModel,
    modelLoaded: Boolean,
    onPickImage: () -> Unit,
) {
    val dimens = LocalDimens.current
    Card {
        Text("Image", style = MaterialTheme.typography.titleMedium)

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
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHighest,
                shape = RoundedCornerShape(dimens.radiusMd),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(160.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        "No image selected",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
            OutlinedButton(onClick = onPickImage) {
                Text(if (viewModel.sourceBitmap == null) "Pick image…" else "Change image…")
            }
            Button(
                onClick = { viewModel.runSegmentation() },
                enabled = modelLoaded &&
                    viewModel.sourceBitmap != null &&
                    !viewModel.isSegmenting,
            ) {
                if (viewModel.isSegmenting) {
                    CircularProgressIndicator(modifier = Modifier.height(18.dp))
                } else {
                    Text("Run segmentation")
                }
            }
        }
    }
}

@Composable
private fun ResultCard(viewModel: SegmentationViewModel) {
    Card {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Classes", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (viewModel.processingTimeMs > 0) {
                Text(
                    "${viewModel.processingTimeMs} ms",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        viewModel.classSummaries.forEach { summary ->
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    summary.label.ifEmpty { "class ${summary.class_id}" },
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    "${summary.pixel_count} px · ${"%.1f".format(summary.fraction * 100)}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun Card(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            content = content,
        )
    }
}
