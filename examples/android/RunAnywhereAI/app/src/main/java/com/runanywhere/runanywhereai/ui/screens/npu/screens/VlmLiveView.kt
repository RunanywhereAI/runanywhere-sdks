package com.runanywhere.runanywhereai.ui.screens.npu.screens

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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.runanywhere.runanywhereai.ui.screens.npu.MetricStrip
import com.runanywhere.runanywhereai.ui.screens.npu.SectionCard
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.fromFilePath
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/** Live mirror of the iOS `VLMCameraView`: a back-camera preview that samples the
 * latest frame every [LIVE_INTERVAL_MS] and streams a one-sentence caption from the
 * loaded VLM. The NPU (QHexRT) VLM ABI consumes images by file path, so each sampled
 * frame is spooled to a cache JPEG before inference — the same route the static path uses. */
private const val LIVE_INTERVAL_MS = 2_500L

@Composable
fun VlmLiveView(loadedModelId: String?, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestFrame = remember { AtomicReference<Bitmap?>(null) }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }

    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> hasPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasPermission) permLauncher.launch(Manifest.permission.CAMERA)
    }

    var caption by remember { mutableStateOf("") }
    var analyzing by remember { mutableStateOf(false) }
    var tps by remember { mutableStateOf("—") }
    var error by remember { mutableStateOf<String?>(null) }

    // Auto-caption loop — mirrors the iOS auto-stream cadence: run one inference,
    // wait for it to finish (collect suspends), then pause LIVE_INTERVAL_MS.
    LaunchedEffect(hasPermission, loadedModelId) {
        if (!hasPermission || loadedModelId == null) return@LaunchedEffect
        while (isActive) {
            val frame = latestFrame.get()
            if (frame != null) {
                analyzing = true
                try {
                    val path = withContext(Dispatchers.IO) {
                        val file = File(context.cacheDir, "vlm_live.jpg")
                        FileOutputStream(file).use { frame.compress(Bitmap.CompressFormat.JPEG, 90, it) }
                        file.absolutePath
                    }
                    val image = RAVLMImage.fromFilePath(path)
                    val opts = RAVLMGenerationOptions(
                        prompt = "Describe what you see in one sentence.",
                        max_tokens = 100,
                    )
                    // Use the non-streaming process() — the same path the static
                    // "Describe" button uses. The QHexRT VLM streaming token path
                    // can complete with 0 tokens (the engine doesn't fan out
                    // incremental tokens for VLM), which left the caption blank;
                    // process() returns the full result text reliably.
                    val result = withContext(Dispatchers.Default) {
                        RunAnywhere.processImage(image, opts)
                    }
                    if (result.text.isNotBlank()) caption = result.text
                    tps = "%.1f".format(result.tokens_per_second)
                    error = null
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    error = e.message ?: "live inference failed"
                } finally {
                    analyzing = false
                }
            }
            delay(LIVE_INTERVAL_MS)
        }
    }

    DisposableEffect(Unit) {
        onDispose { analysisExecutor.shutdown() }
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        if (!hasPermission) {
            SectionCard(title = "Camera") {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Text(
                        "Camera access is needed for the live view.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Button(onClick = { permLauncher.launch(Manifest.permission.CAMERA) }) {
                        Text("Grant camera permission")
                    }
                }
            }
            return@Column
        }

        Box(
            Modifier
                .fillMaxWidth()
                .height(300.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color.Black),
        ) {
            AndroidView(
                factory = { ctx ->
                    PreviewView(ctx).also { view ->
                        view.scaleType = PreviewView.ScaleType.FILL_CENTER
                        bindCamera(ctx, lifecycleOwner, view, latestFrame, analysisExecutor)
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )

            // LIVE badge (top-left).
            Row(
                Modifier
                    .align(Alignment.TopStart)
                    .padding(Spacing.sm)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xCC000000))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(Color(0xFF34C759)))
                Text("LIVE", color = Color.White, style = MaterialTheme.typography.labelMedium)
            }

            if (analyzing) {
                Row(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(Spacing.sm)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xCC000000))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    CircularProgressIndicator(Modifier.size(12.dp), color = Color.White, strokeWidth = 2.dp)
                    Text("Analyzing…", color = Color.White, style = MaterialTheme.typography.labelMedium)
                }
            }
        }

        MetricStrip(listOf("tokens/s" to tps, "mode" to "live"))

        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }

        SectionCard(title = "Live description") {
            Text(
                caption.ifBlank {
                    if (loadedModelId == null) "Load a VLM model to start the live view." else "Point the camera at a scene…"
                },
                style = MaterialTheme.typography.bodyLarge,
                color = if (caption.isBlank()) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
            )
        }
    }
}

/** Binds a back-camera [Preview] + [ImageAnalysis] to [lifecycleOwner]. The analyzer
 * keeps only the latest frame (rotation-corrected) in [latestFrame] for the caption loop. */
private fun bindCamera(
    context: Context,
    lifecycleOwner: androidx.lifecycle.LifecycleOwner,
    previewView: PreviewView,
    latestFrame: AtomicReference<Bitmap?>,
    executor: java.util.concurrent.Executor,
) {
    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({
        val provider = future.get()
        val preview = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }
        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { it.setAnalyzer(executor) { proxy ->
                try {
                    val bitmap = proxy.toBitmap()
                    val rotation = proxy.imageInfo.rotationDegrees
                    val output = if (rotation != 0) {
                        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
                        Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                    } else {
                        bitmap
                    }
                    latestFrame.set(output)
                } catch (_: Exception) {
                    // Drop the frame; the next one will be analyzed.
                } finally {
                    proxy.close()
                }
            } }
        try {
            provider.unbindAll()
            provider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                analysis,
            )
        } catch (_: Exception) {
            // Camera unavailable (e.g. emulator without a camera) — preview stays black.
        }
    }, ContextCompat.getMainExecutor(context))
}
