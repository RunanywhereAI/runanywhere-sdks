package com.runanywhere.runanywhereai.ui.screens.npu.screens

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.runanywhereai.ui.screens.npu.MetricStrip
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelBar
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelsViewModel
import com.runanywhere.runanywhereai.ui.screens.npu.SectionCard
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

private const val SAMPLE_RATE = 16_000

@Composable
fun SttScreen(modelsVm: NpuModelsViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var recording by remember { mutableStateOf(false) }
    var running by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var conf by remember { mutableStateOf("—") }
    val recorderState = remember { RecorderState() }
    val loadedModelId = modelsVm.loadedId(NpuModality.STT)

    fun transcribe(pcm: ByteArray) {
        running = true; error = null
        scope.launch {
            try {
                val out = withContext(Dispatchers.Default) { RunAnywhere.transcribe(pcm) }
                text = out.text
                conf = "%.0f%%".format(out.confidence * 100)
            } catch (e: Exception) {
                error = e.message ?: "transcription failed"
            } finally {
                running = false
            }
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            recording = true
            scope.launch { recorderState.record() }
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        NpuModelBar(modality = NpuModality.STT, vm = modelsVm)

        Button(
            onClick = {
                if (!recording) {
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                        == PackageManager.PERMISSION_GRANTED
                    ) {
                        recording = true
                        scope.launch { recorderState.record() }
                    } else {
                        permission.launch(Manifest.permission.RECORD_AUDIO)
                    }
                } else {
                    recording = false
                    val pcm = recorderState.stop()
                    if (pcm.isNotEmpty()) transcribe(pcm)
                }
            },
            enabled = !running && (recording || loadedModelId != null),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                when {
                    recording -> "Stop & transcribe"
                    running -> "Transcribing…"
                    loadedModelId == null -> "Load a model to transcribe"
                    else -> "Record"
                },
            )
        }

        MetricStrip(listOf("confidence" to conf, "sample rate" to "16 kHz"))

        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }

        SectionCard(title = "Transcript") {
            Text(
                text.ifBlank { if (recording) "Listening…" else "Tap Record and speak." },
                style = MaterialTheme.typography.bodyLarge,
                color = if (text.isBlank()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

/** Captures mono 16 kHz PCM-16 from the mic into a buffer until [stop]. */
private class RecorderState {
    @Volatile private var active = false
    private val buffer = ByteArrayOutputStream()

    suspend fun record() = withContext(Dispatchers.IO) {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        @Suppress("MissingPermission")
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBuf,
        )
        buffer.reset()
        active = true
        val chunk = ByteArray(minBuf)
        recorder.startRecording()
        while (active) {
            val n = recorder.read(chunk, 0, chunk.size)
            if (n > 0) buffer.write(chunk, 0, n)
        }
        recorder.stop()
        recorder.release()
    }

    fun stop(): ByteArray {
        active = false
        return buffer.toByteArray()
    }
}
