package com.runanywhere.runanywhereai.presentation.hybird

import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelListRequest
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.runanywhereai.SDKInitializationState
import com.runanywhere.runanywhereai.domain.services.AudioCaptureService
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.hybrid.BACKEND
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.hybrid.RACModel
import com.runanywhere.sdk.public.hybrid.RACRouter
import com.runanywhere.sdk.public.hybrid.ROUTER
import com.runanywhere.sdk.public.hybrid.TranscribeResult
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun HybridRouterScreen(paddingValues: PaddingValues) {
    val context = LocalContext.current
    val audioService = remember { AudioCaptureService(context) }

    DisposableEffect(audioService) {
        onDispose { audioService.release() }
    }

    val setup by produceState<HybridSttSetup>(HybridSttSetup.Loading) {
        value = setupHybridSttDemo(audioService)
    }

    when (val s = setup) {
        HybridSttSetup.Loading -> Status(paddingValues, "Initializing SDK and verifying models…")
        is HybridSttSetup.Error -> Status(paddingValues, "Setup failed:\n${s.message}")
        is HybridSttSetup.Ready -> HybridSttDemoBody(
            paddingValues = paddingValues,
            audioService = audioService,
            offlineModelId = s.offlineModelId,
            onlineModelId = s.onlineModelId,
        )
    }
}

/** Outcome of [setupHybridSttDemo]. The screen renders one branch per case. */
sealed class HybridSttSetup {
    object Loading : HybridSttSetup()
    data class Ready(val offlineModelId: String, val onlineModelId: String) : HybridSttSetup()
    data class Error(val message: String) : HybridSttSetup()
}

/**
 * Single setup helper for the hybrid STT demo screen.
 *
 * Waits for [RunAnywhereApplication]'s async SDK init to finish, verifies the
 * curated sherpa STT model has been registered AND downloaded by
 * [com.runanywhere.runanywhereai.data.ModelBootstrap], confirms the Sarvam
 * cloud model id is present in [BACKEND.SARVAM]'s registry, and verifies
 * the RECORD_AUDIO permission is held.
 */
suspend fun setupHybridSttDemo(
    audioService: AudioCaptureService,
    offlineModelId: String = "sherpa-onnx-whisper-tiny.en",
    onlineModelId: String = "saaras",
): HybridSttSetup {
    val sdkState = RunAnywhereApplication.getInstance().initializationState
        .first { it !is SDKInitializationState.Loading }
    if (sdkState is SDKInitializationState.Error) {
        return HybridSttSetup.Error("SDK init failed: ${sdkState.error.message}")
    }

    if (!audioService.hasRecordPermission()) {
        return HybridSttSetup.Error(
            "RECORD_AUDIO permission not granted. Grant it via system settings and reopen this screen.",
        )
    }

    val model = try {
        RunAnywhere.listModels(ModelListRequest())
            .models?.models.orEmpty()
            .firstOrNull { it.id == offlineModelId }
    } catch (e: Throwable) {
        return HybridSttSetup.Error("listModels failed: ${e.message}")
    } ?: return HybridSttSetup.Error(
        "Offline STT model '$offlineModelId' is not in the registry. Check ModelBootstrap.",
    )

    if (!model.isDownloadedOnDisk) {
        return HybridSttSetup.Error(
            "Offline STT model '$offlineModelId' is registered but not downloaded yet. " +
                "Download it from the Models screen first.",
        )
    }

    if (!BACKEND.SARVAM.isRegistered(onlineModelId)) {
        return HybridSttSetup.Error(
            "Sarvam id '$onlineModelId' is not registered. " +
                "Check the BACKEND.SARVAM.register call in ModelBootstrap.",
        )
    }

    // Prime the sherpa model via the lifecycle pipeline so the nested-archive
    // path is resolved before the hybrid router calls rac_stt_create() under
    // the hood. Without this, rac_stt_create() reads the registry's outer
    // local_path and sherpa returns RAC_ERROR_MODEL_LOAD_FAILED because the
    // .onnx files live one level deeper (ARCHIVE_STRUCTURE_NESTED_DIRECTORY).
    try {
        RunAnywhere.loadModel(
            RAModelLoadRequest(
                model_id = offlineModelId,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
            ),
        )
    } catch (e: Throwable) {
        return HybridSttSetup.Error("Failed to load offline STT model: ${e.message}")
    }

    return HybridSttSetup.Ready(offlineModelId, onlineModelId)
}

@Composable
private fun HybridSttDemoBody(
    paddingValues: PaddingValues,
    audioService: AudioCaptureService,
    offlineModelId: String,
    onlineModelId: String,
) {
    val scope = rememberCoroutineScope()

    val router = remember {
        RACRouter.stt.init(
            backendOffline = BACKEND.SHERPA.STT,
            backendOnline = BACKEND.SARVAM.STT,
        )
    }

    DisposableEffect(router) {
        onDispose { router.close() }
    }

    LaunchedEffect(router, offlineModelId, onlineModelId) {
        router.stt.addPair(
            model1 = RACModel(id = offlineModelId, modelType = ROUTER.OFFLINE),
            model2 = RACModel(id = onlineModelId, modelType = ROUTER.ONLINE),
            // Local-first: sherpa runs first so the router can read its
            // confidence and cascade to Sarvam only when the score is below
            // RAC_HYBRID_STT_CONFIDENCE_THRESHOLD (0.5). PreferOnlineFirst
            // would make Sarvam the primary and sherpa would never run, so the
            // confidence signal would never be evaluated.
            routerPolicy = RACRouter.AdvanceRouterPolicy {
                hardFilters = arrayOf(
                    RACRouter.RoutingPolicy.NETWORK(),
                    RACRouter.RoutingPolicy.Battery(minPercent = 20),
                )
                cascadeConditions = RACRouter.RoutingPolicy.Confidence(0.5f)
                rankSort = RACRouter.RoutingPolicy.PreferLocalFirst
            },
        )
    }

    var isRecording by remember { mutableStateOf(false) }
    var recordingJob by remember { mutableStateOf<Job?>(null) }
    val pcmBuffer = remember { ByteArrayOutputStream() }
    var transcribeJob by remember { mutableStateOf<Job?>(null) }
    var transcribing by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<TranscribeResult?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val audioLevel by audioService.audioLevel.collectAsState()

    Column(
        modifier = Modifier
            .padding(paddingValues)
            .padding(16.dp)
            .fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Hybrid STT Demo", style = MaterialTheme.typography.titleLarge)
        Text("Offline: $offlineModelId")
        Text("Online:  $onlineModelId")
        Text(
            "Policy: PreferOnlineFirst · NETWORK · Battery(20) · failure-fallback",
            style = MaterialTheme.typography.bodySmall,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = {
                    if (!isRecording) {
                        // Start recording.
                        result = null
                        error = null
                        pcmBuffer.reset()
                        isRecording = true
                        recordingJob = scope.launch {
                            try {
                                audioService.startCapture().collect { chunk ->
                                    pcmBuffer.write(chunk)
                                }
                            } catch (e: CancellationException) {
                                // Expected when the user presses Stop — propagate
                                // so structured concurrency tears down cleanly.
                                throw e
                            } catch (t: Throwable) {
                                error = "Recording failed: ${t.message}"
                                isRecording = false
                            }
                        }
                    } else {
                        // Stop + transcribe. Run in a coroutine so we can
                        // cancelAndJoin the recording job before reading the
                        // buffer (otherwise the last few PCM chunks race with
                        // toByteArray()).
                        transcribeJob = scope.launch {
                            isRecording = false
                            audioService.stopCapture()
                            recordingJob?.cancelAndJoin()
                            recordingJob = null

                            val pcm = pcmBuffer.toByteArray()
                            if (pcm.isEmpty()) {
                                error = "No audio captured."
                                transcribeJob = null
                                return@launch
                            }
                            val wav = pcmToWav(pcm, sampleRate = AudioCaptureService.SAMPLE_RATE)

                            transcribing = true
                            try {
                                val r = withContext(Dispatchers.IO) {
                                    router.stt.transcribe(
                                        audioBytes = wav,
                                        audioFormat = 1, // RAC_AUDIO_FORMAT_WAV
                                        sampleRate = AudioCaptureService.SAMPLE_RATE,
                                    )
                                }
                                result = r
                            } catch (e: CancellationException) {
                                throw e
                            } catch (t: Throwable) {
                                error = "Transcribe failed: ${t.message}"
                            } finally {
                                transcribing = false
                                transcribeJob = null
                            }
                        }
                    }
                },
                enabled = !transcribing,
            ) {
                Text(
                    when {
                        transcribing -> "Transcribing…"
                        isRecording -> "Stop + Transcribe"
                        else -> "Record"
                    },
                )
            }
        }

        if (isRecording) {
            Text("Recording…", style = MaterialTheme.typography.bodyMedium)
            LinearProgressIndicator(
                progress = { audioLevel.coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        error?.let {
            HorizontalDivider()
            Text("Error: $it", color = MaterialTheme.colorScheme.error)
        }

        result?.let { r ->
            HorizontalDivider()
            RoutingInfoRow(routing = r.routing)
            if (r.detectedLanguage.isNotEmpty()) {
                Text(
                    "language = ${r.detectedLanguage}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text("transcript:", style = MaterialTheme.typography.labelMedium)
            Text(r.text)
        }
    }
}

/**
 * Result chip showing which backend served the request, its confidence,
 * and (when a confidence cascade fired) the primary's score.
 */
@Composable
private fun RoutingInfoRow(routing: com.runanywhere.sdk.public.hybrid.RoutedMetadata) {
    val isFallback = routing.wasFallback
    val badge = if (isFallback) "Cloud Fallback" else "Local"
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text(
                    badge,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (isFallback) {
                        MaterialTheme.colorScheme.tertiary
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                )
                Text(routing.chosenModelId, style = MaterialTheme.typography.bodySmall)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    confidencePercent(routing.confidence),
                    style = MaterialTheme.typography.titleMedium,
                )
                Text("confidence", style = MaterialTheme.typography.labelSmall)
            }
            if (isFallback && !routing.primaryConfidence.isNaN()) {
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        confidencePercent(routing.primaryConfidence),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Text("local score", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        Text("attempts = ${routing.attemptCount}", style = MaterialTheme.typography.labelSmall)
        if (isFallback && routing.primaryErrorCode != 0) {
            Text(
                "primary error: rc=${routing.primaryErrorCode} " +
                    "\"${routing.primaryErrorMessage}\"",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

private fun confidencePercent(value: Float): String =
    if (value.isNaN()) "n/a" else "${(value * 100).toInt()}%"

@Composable
private fun Status(paddingValues: PaddingValues, message: String) {
    Box(
        modifier = Modifier
            .padding(paddingValues)
            .padding(24.dp)
            .fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(message)
    }
}

/**
 * Wrap raw 16-bit mono PCM bytes in a 44-byte WAV header. Sarvam accepts
 * the resulting bytes as a multipart `file` upload; sherpa-onnx whisper
 * parses the WAV header inline before decoding.
 */
private fun pcmToWav(pcm: ByteArray, sampleRate: Int): ByteArray {
    val channels = 1
    val bitsPerSample = 16
    val byteRate = sampleRate * channels * bitsPerSample / 8
    val blockAlign = channels * bitsPerSample / 8
    val dataSize = pcm.size
    val out = ByteArray(44 + dataSize)
    val bb = ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN)
    bb.put("RIFF".toByteArray(Charsets.US_ASCII))
    bb.putInt(36 + dataSize)
    bb.put("WAVE".toByteArray(Charsets.US_ASCII))
    bb.put("fmt ".toByteArray(Charsets.US_ASCII))
    bb.putInt(16)
    bb.putShort(1.toShort())
    bb.putShort(channels.toShort())
    bb.putInt(sampleRate)
    bb.putInt(byteRate)
    bb.putShort(blockAlign.toShort())
    bb.putShort(bitsPerSample.toShort())
    bb.put("data".toByteArray(Charsets.US_ASCII))
    bb.putInt(dataSize)
    bb.put(pcm)
    return out
}
