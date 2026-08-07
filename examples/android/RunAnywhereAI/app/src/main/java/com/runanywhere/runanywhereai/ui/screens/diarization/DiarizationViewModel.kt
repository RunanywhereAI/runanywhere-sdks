package com.runanywhere.runanywhereai.ui.screens.diarization

import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelImportRequest
import android.app.Application
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.ui.screens.stt.AudioRecorder
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.AudioInput
import com.runanywhere.sdk.public.api.SpeakerSegment
import com.runanywhere.sdk.public.api.diarization
import com.runanywhere.sdk.public.api.models
import com.runanywhere.sdk.public.extensions.importModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Drives standalone speaker diarization (NVIDIA Sortformer) through the canonical
 * `RunAnywhere.diarization.diarize` facade. Pure platform plumbing: SDK model lifecycle,
 * microphone capture, and the diarize call. All inference and model routing live
 * in the SDK / C++ commons.
 */
class DiarizationViewModel(application: Application) : AndroidViewModel(application) {

    var isModelLoaded by mutableStateOf(false)
        private set
    var loadedModelId by mutableStateOf<String?>(null)
        private set
    var isImportingModel by mutableStateOf(false)
        private set

    var isRecording by mutableStateOf(false)
        private set
    var isDiarizing by mutableStateOf(false)
        private set
    var audioLevel by mutableFloatStateOf(0f)
        private set

    var segments by mutableStateOf<List<SpeakerSegment>>(emptyList())
        private set
    var speakerCount by mutableStateOf(0)
        private set
    var audioDurationMs by mutableStateOf(0L)
        private set
    var processingTimeMs by mutableStateOf(0L)
        private set

    var status by mutableStateOf("")
        private set
    var error by mutableStateOf<String?>(null)
        private set

    private val recorder = AudioRecorder()
    private val buffer = ByteArrayOutputStream()

    fun refreshModelStatus() {
        viewModelScope.launch {
            isModelLoaded = runCatching {
                RunAnywhere.models.state().loaded
                    .containsKey(ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION)
            }.getOrDefault(false)
        }
    }

    /**
     * Stage the user-picked Sortformer bundle files into app storage, then import
     * and load them under the speaker-diarization category.
     */
    fun importAndLoadModel(uris: List<Uri>) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            isImportingModel = true
            error = null
            status = "Importing model…"
            try {
                val stagedDir = withContext(Dispatchers.IO) { stageFiles(uris) }
                val importResult = RunAnywhere.importModel(
                    ModelImportRequest(
                        source_path = stagedDir.absolutePath,
                        copy_into_managed_storage = true,
                        validate_before_register = false,
                    ),
                )
                if (importResult.error != null) {
                    error = importResult.error?.message?.ifEmpty { "Model import failed." } ?: "Model import failed."
                    status = ""
                    return@launch
                }
                val modelId = importResult.model?.id
                if (modelId.isNullOrEmpty()) {
                    error = "Imported model has no identifier; cannot load."
                    status = ""
                    return@launch
                }

                status = "Loading model…"
                // No LoadOptions.framework: the SDK resolves the engine from the
                // imported model's registry entry (ONNX Sortformer). The example
                // must not pin an engine constant (layering rule).
                RunAnywhere.models.load(modelId)
                loadedModelId = modelId
                isModelLoaded = true
                status = "Model loaded: $modelId."
            } catch (e: Exception) {
                RACLog.e("$TAG: Model import/load failed", e)
                error = "Model import/load failed: ${e.message}"
                status = ""
            } finally {
                isImportingModel = false
            }
        }
    }

    fun toggleRecording() {
        if (isRecording) stopAndDiarize() else startRecording()
    }

    private fun startRecording() {
        if (!isModelLoaded) { error = "Load a diarization model first."; return }
        error = null
        segments = emptyList()
        speakerCount = 0
        audioDurationMs = 0L
        processingTimeMs = 0L
        synchronized(buffer) { buffer.reset() }
        audioLevel = 0f
        isRecording = true
        status = "Recording…"
        try {
            recorder.start(
                onChunk = { chunk, level ->
                    synchronized(buffer) { buffer.write(chunk) }
                    audioLevel = level
                },
                onError = { t ->
                    RACLog.e("$TAG: microphone read failed", t)
                    viewModelScope.launch {
                        if (isRecording) {
                            error = t.message ?: "Microphone stopped unexpectedly"
                            cancel()
                        }
                    }
                },
            )
        } catch (e: Exception) {
            RACLog.e("$TAG: microphone start failed", e)
            error = e.message ?: "Could not start the microphone"
            cancel()
        }
    }

    private fun stopAndDiarize() {
        isRecording = false
        recorder.stop()
        audioLevel = 0f
        val audio = synchronized(buffer) { val bytes = buffer.toByteArray(); buffer.reset(); bytes }
        if (audio.size < MIN_BYTES) {
            error = "Recording too short — hold a little longer."
            status = ""
            return
        }
        runDiarization(audio)
    }

    private fun runDiarization(audio: ByteArray) {
        viewModelScope.launch {
            isDiarizing = true
            error = null
            status = "Running diarization…"
            try {
                val startedAt = System.currentTimeMillis()
                val result = RunAnywhere.diarization.diarize(
                    AudioInput.pcm16(audio, AudioRecorder.SAMPLE_RATE),
                )
                val elapsed = System.currentTimeMillis() - startedAt
                segments = result.segments.sortedBy { it.startMs }
                speakerCount = result.speakerCount
                audioDurationMs = audio.size.toLong() / (AudioRecorder.SAMPLE_RATE * 2L / 1000L)
                processingTimeMs = elapsed
                status = "Done — ${result.speakerCount} speakers, " +
                    "${result.segments.size} segments in ${elapsed}ms."
            } catch (e: Exception) {
                RACLog.e("$TAG: Diarization failed", e)
                error = "Diarization failed: ${e.message}"
            } finally {
                isDiarizing = false
            }
        }
    }

    /** Release the mic on navigation-away or lifecycle stop. */
    fun cancel() {
        isRecording = false
        recorder.stop()
        audioLevel = 0f
    }

    override fun onCleared() {
        cancel()
    }

    // --- File helpers ---------------------------------------------------------

    private fun stageFiles(uris: List<Uri>): File {
        val resolver = getApplication<Application>().contentResolver
        val dir = File(getApplication<Application>().filesDir, "diarization-import").apply {
            deleteRecursively()
            mkdirs()
        }
        uris.forEachIndexed { index, uri ->
            val name = displayName(uri) ?: "model-file-$index"
            resolver.openInputStream(uri)?.use { input ->
                File(dir, name).outputStream().use { output -> input.copyTo(output) }
            }
        }
        return dir
    }

    private fun displayName(uri: Uri): String? {
        val resolver = getApplication<Application>().contentResolver
        return resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    private companion object {
        const val TAG = "DiarizationVM"
        const val MIN_BYTES = 16000
    }
}
