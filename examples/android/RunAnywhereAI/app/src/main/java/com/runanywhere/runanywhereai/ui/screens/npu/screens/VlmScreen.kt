package com.runanywhere.runanywhereai.ui.screens.npu.screens

import ai.runanywhere.proto.v1.VLMImageFormat
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
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
import com.runanywhere.sdk.public.extensions.fromEncoded
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.runanywhereai.ui.screens.npu.MetricStrip
import com.runanywhere.runanywhereai.ui.screens.npu.SectionCard
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun VlmScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var imageBytes by remember { mutableStateOf<ByteArray?>(null) }
    var thumbnail by remember { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    var prompt by remember { mutableStateOf(TextFieldValue("Describe this image.")) }
    var output by remember { mutableStateOf("") }
    var running by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var tps by remember { mutableStateOf("—") }

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
                        val image = RAVLMImage.fromEncoded(bytes, VLMImageFormat.VLM_IMAGE_FORMAT_JPEG)
                        val opts = RAVLMGenerationOptions(prompt = prompt.text, max_tokens = 200)
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
            enabled = !running && imageBytes != null && prompt.text.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (running) "Processing…" else "Describe")
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
