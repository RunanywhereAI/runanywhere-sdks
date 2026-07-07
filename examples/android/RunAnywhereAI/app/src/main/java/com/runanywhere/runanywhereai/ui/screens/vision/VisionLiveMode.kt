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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.fromFilePath
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/** Live mode: a back-camera preview that samples the latest frame every
 * [LIVE_INTERVAL_MS] and captions it with the loaded VLM. The VLM ABI consumes
 * images by file path, so each sampled frame is spooled to a cache JPEG before
 * inference — the same route the static Describe path uses. */
private const val LIVE_INTERVAL_MS = 2_500L

@Composable
fun VisionLiveMode(loadedModelId: String?, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestFrame = remember { AtomicReference<Bitmap?>(null) }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    val cameraProvider = remember { AtomicReference<ProcessCameraProvider?>(null) }

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

    // Auto-caption loop: run one inference, wait for it to finish, then pause
    // LIVE_INTERVAL_MS so the cadence stays responsive.
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
                    // Honor the app-wide system prompt for persona, but keep a tight
                    // token cap so each frame analyzes quickly.
                    val s = SettingsRepository.settings
                    val opts = RAVLMGenerationOptions(
                        prompt = "Describe what you see in one sentence.",
                        max_tokens = minOf(s.maxTokens, 100),
                        system_prompt = s.systemPrompt.ifBlank { null },
                    )
                    // Non-streaming process(): some VLM engines complete the stream
                    // path with 0 incremental tokens, which leaves the caption blank;
                    // process() returns the full result text reliably.
                    val result = withContext(Dispatchers.Default) {
                        RunAnywhere.processImage(image, opts)
                    }
                    if (result.text.isNotBlank()) caption = result.text
                    tps = String.format(Locale.US, "%.1f", result.tokens_per_second)
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
        onDispose {
            // Release the camera when leaving Live mode — without unbindAll() the
            // preview/analyzer stay bound to the screen's lifecycle and keep the
            // camera busy in the background.
            cameraProvider.getAndSet(null)?.unbindAll()
            analysisExecutor.shutdown()
        }
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
        if (!hasPermission) {
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shape = RoundedCornerShape(dimens.radiusLg),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(dimens.spacingLg),
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                ) {
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
                .clip(RoundedCornerShape(dimens.radiusLg))
                .background(Color.Black),
        ) {
            AndroidView(
                factory = { ctx ->
                    PreviewView(ctx).also { view ->
                        view.scaleType = PreviewView.ScaleType.FILL_CENTER
                        bindCamera(ctx, lifecycleOwner, view, latestFrame, analysisExecutor, cameraProvider)
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )

            // LIVE badge (top-left).
            Row(
                Modifier
                    .align(Alignment.TopStart)
                    .padding(dimens.spacingSm)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xCC000000))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(com.runanywhere.runanywhereai.ui.theme.primaryGreen))
                Text("LIVE", color = Color.White, style = MaterialTheme.typography.labelMedium)
            }

            if (analyzing) {
                Row(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(dimens.spacingSm)
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

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                "tokens/s",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(tps, style = MaterialTheme.typography.bodyMedium)
        }

        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }

        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = caption.ifBlank {
                    if (loadedModelId == null) {
                        "Load a vision model to start the live view."
                    } else {
                        "Point the camera at a scene…"
                    }
                },
                style = MaterialTheme.typography.bodyLarge,
                color = if (caption.isBlank()) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                modifier = Modifier.padding(dimens.spacingLg),
            )
        }
    }
}

/** Binds a back-camera [Preview] + [ImageAnalysis] to [lifecycleOwner]. The analyzer
 * keeps only the latest frame (rotation-corrected) in [latestFrame] for the caption
 * loop; the bound provider lands in [providerOut] so the caller can unbind on dispose. */
private fun bindCamera(
    context: Context,
    lifecycleOwner: androidx.lifecycle.LifecycleOwner,
    previewView: PreviewView,
    latestFrame: AtomicReference<Bitmap?>,
    executor: java.util.concurrent.Executor,
    providerOut: AtomicReference<ProcessCameraProvider?>,
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
            providerOut.set(provider)
        } catch (_: Exception) {
            // Camera unavailable (e.g. emulator without a camera) — preview stays black.
        }
    }, ContextCompat.getMainExecutor(context))
}
