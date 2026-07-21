package com.runanywhere.runanywhereai.ui.screens.segmentation

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import com.runanywhere.runanywhereai.ui.theme.LocalDimens

/**
 * Semantic image segmentation (SegFormer) UI. Pure SwiftUI-style Compose: EULA
 * gate, user-supplied model import, image picker, and mask rendering. No
 * inference or model logic lives here — everything routes through
 * [SegmentationViewModel] into the SDK facade.
 */
@Composable
fun SegmentationScreen(viewModel: SegmentationViewModel = viewModel()) {
    val dimens = LocalDimens.current
    val context = LocalContext.current

    LaunchedEffect(Unit) { viewModel.refreshModelStatus() }

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

    val modelPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris ->
        if (uris.isNotEmpty()) viewModel.importAndLoadModel(uris)
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

        licenseCard(viewModel)
        modelCard(viewModel) { modelPicker.launch(arrayOf("*/*")) }
        imageCard(viewModel) { imagePicker.launch("image/*") }

        if (viewModel.classSummaries.isNotEmpty()) {
            resultCard(viewModel)
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
}

@Composable
private fun licenseCard(viewModel: SegmentationViewModel) {
    Card {
        val dimens = LocalDimens.current
        Text("Model license", style = MaterialTheme.typography.titleMedium)
        Text(
            "SegFormer segmentation weights are released for noncommercial research / evaluation only. " +
                "The SDK will not load them until you accept the pinned upstream terms. Acceptance applies " +
                "to this app session and does not download any model.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "I accept the NVIDIA SegFormer noncommercial license.",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            Switch(
                checked = viewModel.licenseAccepted,
                onCheckedChange = { if (it) viewModel.acceptLicense() },
                enabled = !viewModel.licenseAccepted,
            )
        }
    }
}

@Composable
private fun modelCard(viewModel: SegmentationViewModel, onPickModel: () -> Unit) {
    Card {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Model", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            Text(
                if (viewModel.isModelLoaded) "loaded" else "not loaded",
                style = MaterialTheme.typography.labelMedium,
                color = if (viewModel.isModelLoaded) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
        Text(
            "SegFormer weights are user-supplied and uncataloged. Pick the model files " +
                "(model.onnx, config.json, preprocessor_config.json, runanywhere-segmentation.json); " +
                "the SDK imports and loads them under the semantic-segmentation category.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(
            onClick = onPickModel,
            enabled = viewModel.licenseAccepted && !viewModel.isImportingModel,
        ) {
            if (viewModel.isImportingModel) {
                CircularProgressIndicator(modifier = Modifier.height(18.dp))
            } else {
                Text(if (viewModel.isModelLoaded) "Change model files…" else "Choose model files…")
            }
        }
    }
}

@Composable
private fun imageCard(viewModel: SegmentationViewModel, onPickImage: () -> Unit) {
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
            OutlinedButton(onClick = onPickImage, enabled = viewModel.licenseAccepted) {
                Text(if (viewModel.sourceBitmap == null) "Pick image…" else "Change image…")
            }
            Button(
                onClick = { viewModel.runSegmentation() },
                enabled = viewModel.licenseAccepted &&
                    viewModel.isModelLoaded &&
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
private fun resultCard(viewModel: SegmentationViewModel) {
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
