package com.runanywhere.runanywhereai.ui.screens.diffusion

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import java.util.Locale

@Composable
fun DiffusionScreen() {
    val dimens = LocalDimens.current
    val vm: DiffusionViewModel = viewModel()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
            Text(
                text = "Image generation",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Cosmos3-Edge diffusion runs the whole text-to-image pipeline on the Hexagon NPU.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // --- prompt ---
        OutlinedTextField(
            value = vm.prompt,
            onValueChange = vm::onPromptChange,
            label = { Text("Prompt") },
            supportingText = {
                Text(
                    "Preview build: this Cosmos3-Edge export renders a fixed baked prompt; " +
                        "free-form prompts arrive with the prompt-conditioned export.",
                )
            },
            singleLine = false,
            enabled = !vm.isGenerating,
            modifier = Modifier.fillMaxWidth(),
        )

        // --- action / status ---
        when (vm.stage) {
            DiffusionModelStage.READY -> {
                Button(
                    onClick = vm::generate,
                    enabled = !vm.isGenerating && vm.prompt.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(if (vm.isGenerating) "Generating…" else "Generate") }
            }
            DiffusionModelStage.DOWNLOADING -> {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Text(
                    "Downloading model… ${vm.downloadPercent ?: 0}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            DiffusionModelStage.LOADING -> {
                Row2 { CircularProgressIndicator(modifier = Modifier.size(20.dp)); Text("Loading model onto the NPU…") }
            }
            DiffusionModelStage.NEEDS_TOKEN -> {
                Text(
                    "Add a Hugging Face token in Settings to download this private model.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            DiffusionModelStage.NOT_DOWNLOADED -> {
                Button(onClick = vm::prepare, modifier = Modifier.fillMaxWidth()) {
                    Text("Download & load model (~4.4 GB)")
                }
                Text(
                    "First run downloads ~4.4 GB. Generation takes ~30–60 s per image on-device.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            DiffusionModelStage.UNKNOWN -> {
                Text(
                    "Cosmos3-Edge Diffusion is unavailable on this device.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        vm.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }

        // --- result ---
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(dimens.radiusLg)),
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                val bmp = vm.image
                when {
                    vm.isGenerating -> Row2 { CircularProgressIndicator(modifier = Modifier.size(24.dp)); Text("Generating on the NPU…") }
                    bmp != null -> Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = "Generated image",
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxSize(),
                    )
                    else -> Text(
                        "Your image will appear here",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        vm.lastLatencyMs?.let {
            Text(
                text = "Generated in ${String.format(Locale.US, "%.1f", it / 1000.0)} s (NPU)",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

@Composable
private fun Row2(content: @Composable () -> Unit) {
    val dimens = LocalDimens.current
    androidx.compose.foundation.layout.Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) { content() }
}
