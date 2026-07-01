package com.runanywhere.runanywhereai.ui.screens.npu.screens

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.fromFilePath
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.screens.npu.MetricStrip
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelBar
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelsViewModel
import com.runanywhere.runanywhereai.ui.screens.npu.SectionCard
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun VlmScreen(modelsVm: NpuModelsViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var imageBytes by remember { mutableStateOf<ByteArray?>(null) }
    var thumbnail by remember { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    var prompt by remember { mutableStateOf(TextFieldValue("Describe this image.")) }
    var output by remember { mutableStateOf("") }
    var running by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var tps by remember { mutableStateOf("—") }
    var liveMode by remember { mutableStateOf(false) }
    val loadedModelId = modelsVm.loadedId(NpuModality.VLM)

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            imageBytes = bytes
            thumbnail = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        NpuModelBar(modality = NpuModality.VLM, vm = modelsVm)

        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            FilterChip(
                selected = !liveMode,
                onClick = { liveMode = false },
                label = { Text("Image") },
            )
            FilterChip(
                selected = liveMode,
                onClick = { liveMode = true },
                label = { Text("Live view") },
            )
        }

        if (liveMode) {
            VlmLiveView(loadedModelId = loadedModelId)
            return@Column
        }

        OutlinedButton(onClick = { picker.launch("image/*") }, modifier = Modifier.fillMaxWidth()) {
            Text(if (imageBytes == null) "Pick an image" else "Change image")
        }
        thumbnail?.let {
            Image(
                bitmap = it,
                contentDescription = null,
                modifier = Modifier.fillMaxWidth().height(200.dp),
                contentScale = ContentScale.Fit,
            )
        }
        OutlinedTextField(
            value = prompt,
            onValueChange = { prompt = it },
            label = { Text("Prompt") },
            modifier = Modifier.fillMaxWidth(),
            enabled = !running,
        )
        Button(
            onClick = {
                output = ""; error = null; running = true
                val bytes = imageBytes!!
                scope.launch {
                    try {
                        // The NPU (QHexRT) VLM ABI consumes the image by file path and
                        // decodes the container itself; raw-pixel / base64 forms are not
                        // accepted. Spool the picked image to a cache file and pass the
                        // path — this also works for every other VLM engine.
                        val image = withContext(Dispatchers.IO) {
                            val file = File(context.cacheDir, "vlm_input.jpg")
                            file.writeBytes(bytes)
                            RAVLMImage.fromFilePath(file.absolutePath)
                        }
                        // Honor the app-wide Settings (More → Settings) for the NPU/QHexRT
                        // VLM tab: max tokens caps the description length and the system
                        // prompt steers the persona. The image prompt stays user-driven.
                        val s = SettingsRepository.settings
                        val opts = RAVLMGenerationOptions(
                            prompt = prompt.text,
                            max_tokens = s.maxTokens,
                            system_prompt = s.systemPrompt.ifBlank { null },
                        )
                        val result = withContext(Dispatchers.Default) {
                            RunAnywhere.processImage(image, opts)
                        }
                        output = result.text
                        tps = "%.1f".format(result.tokens_per_second)
                    } catch (e: Exception) {
                        error = e.message ?: "processing failed"
                    } finally {
                        running = false
                    }
                }
            },
            enabled = !running && imageBytes != null && prompt.text.isNotBlank() && loadedModelId != null,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                when {
                    running -> "Processing…"
                    loadedModelId == null -> "Load a model to describe"
                    else -> "Describe"
                },
            )
        }

        MetricStrip(listOf("tokens/s" to tps, "image" to if (imageBytes != null) "loaded" else "—"))

        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }

        SectionCard(title = "Result") {
            Text(
                output.ifBlank { if (running) "…" else "Pick an image and describe it." },
                style = MaterialTheme.typography.bodyLarge,
                color = if (output.isBlank()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}
