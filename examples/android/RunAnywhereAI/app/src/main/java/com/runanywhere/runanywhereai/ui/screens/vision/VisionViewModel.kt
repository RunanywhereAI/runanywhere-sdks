package com.runanywhere.runanywhereai.ui.screens.vision

import android.app.Application
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.screens.chat.ComposerAttachmentKind
import com.runanywhere.runanywhereai.ui.screens.chat.ComposerAttachmentPolicy
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.GenerationEvent
import com.runanywhere.sdk.public.api.GenerationResult
import com.runanywhere.sdk.public.api.ImageInput
import com.runanywhere.sdk.public.api.vlm
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.coroutines.cancellation.CancellationException

/**
 * The photo half of the Vision screen: one staged image, one question, one streamed answer.
 *
 * Every outcome the screen can reach is a [VisionRunStatus], and every refused file is an
 * [imageRejection] sentence, so there is no path through this class that leaves the UI with
 * nothing to say. The live-camera half is [VisionLiveViewModel].
 */
class VisionViewModel(application: Application) : AndroidViewModel(application) {

    var image by mutableStateOf<StagedVisionImage?>(null)
        private set

    /**
     * Why the file the user just chose was not staged, or null.
     *
     * A pick that silently does nothing is indistinguishable from a broken picker — which is
     * exactly what an unreadable or oversized image used to produce here.
     */
    var imageRejection by mutableStateOf<String?>(null)
        private set

    /** A pick is being read off its content provider and decoded. */
    var isPreparingImage by mutableStateOf(false)
        private set

    var prompt by mutableStateOf(DEFAULT_VISION_PROMPT)
        private set

    var description by mutableStateOf("")
        private set

    var status by mutableStateOf<VisionRunStatus>(VisionRunStatus.Idle)
        private set

    private var job: Job? = null
    private var watchdog: Job? = null

    /** Stage an image the user picked with the photo picker. */
    fun onImagePicked(uri: Uri) {
        if (isPreparingImage) return
        stop()
        imageRejection = null
        isPreparingImage = true
        viewModelScope.launch {
            val outcome = withContext(Dispatchers.IO) { stageFromUri(uri) }
            isPreparingImage = false
            when (outcome) {
                is StageOutcome.Accepted -> accept(outcome.image)
                is StageOutcome.Rejected -> imageRejection = outcome.reason
            }
        }
    }

    /** Stage the photo the system camera returned. */
    fun onImageCaptured(bitmap: Bitmap?) {
        // TakePicturePreview reports a back-press and a camera-app failure identically — both
        // arrive as null — so this cannot name a failure without risking calling a deliberate
        // cancel an error. A cancel leaves the previously staged image exactly as it was.
        val captured = bitmap ?: return
        stop()
        imageRejection = null
        accept(StagedVisionImage(captured, "Camera photo"))
    }

    fun dismissImageRejection() {
        imageRejection = null
    }

    /** Drop the staged image so the screen returns to its empty state. */
    fun clearImage() {
        if (status.isBusy) return
        image = null
        description = ""
        status = VisionRunStatus.Idle
        imageRejection = null
    }

    fun onPromptChange(value: String) {
        prompt = value
    }

    fun describe() {
        val staged = image ?: return
        if (status.isBusy) return
        val requestPrompt = prompt.trim()
        if (requestPrompt.isBlank()) return
        // Derive the answer mode from the current prompt at generate time rather than latching it
        // on edit: the default describe prompt gets the larger detailed-description budget, any
        // custom prompt is a focused question.
        val requestMode = if (requestPrompt == DEFAULT_VISION_PROMPT) {
            VisionAnswerMode.DETAILED_DESCRIPTION
        } else {
            VisionAnswerMode.FOCUSED_QUESTION
        }
        description = ""
        status = VisionRunStatus.Running
        startWatchdog()
        job = viewModelScope.launch {
            var file: File? = null
            val startedAt = System.currentTimeMillis()
            try {
                file = withContext(Dispatchers.IO) { writeJpegToCache(staged.bitmap) }
                val activeModel = RuntimeModelSelection.requireCurrent(ModelSelectionContext.VLM)
                val options = VisionGenerationPolicy.options(
                    model = activeModel.model,
                    mode = requestMode,
                    userLimit = SettingsRepository.settings.maxTokens,
                )
                // Streamed rather than unary, for two reasons that are really one: cancelling the
                // Flow *is* the SDK's VLM cancellation contract (it drops the request lease and
                // calls the native cancel), so Stop can only be honest on this path. Text arriving
                // as it is produced is the same guarantee seen from the front.
                var completed: GenerationResult? = null
                RunAnywhere.vlm.generateStream(
                    ImageInput.file(file.absolutePath),
                    requestPrompt,
                    options,
                ).collect { event ->
                    when (event) {
                        is GenerationEvent.TextDelta -> description += event.text
                        is GenerationEvent.Completed -> completed = event.result
                        is GenerationEvent.Failed -> throw event.error
                        else -> Unit
                    }
                }
                val result = completed
                if (result == null) {
                    // The stream closed without its terminal event. Saying so beats presenting
                    // whatever partial text arrived as a finished answer.
                    status = VisionRunStatus.Failed("Vision ended before the model finished.")
                } else {
                    // A backend whose stream granularity is whole-response emits no deltas at
                    // all; its full caption only exists on the completed result.
                    if (description.isBlank()) description = result.toDisplayText()
                    status = VisionRunStatus.Done(
                        metrics = result.toUiMetrics(System.currentTimeMillis() - startedAt),
                        truncated = VisionGenerationPolicy.wasTruncated(
                            options,
                            result.finishReason,
                            result.outputTokens,
                        ),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("vlm describe failed", e)
                status = VisionRunStatus.Failed(e.userFacingVisionMessage())
            } finally {
                // The native call has unwound by the time this runs, so this — and not stop() —
                // is where the busy guard may finally come down.
                watchdog?.cancel()
                if (status is VisionRunStatus.Stopping) status = VisionRunStatus.Cancelled
                file?.delete()
            }
        }
    }

    fun stop() {
        val active = job ?: return
        if (!status.isRunning) return
        status = VisionRunStatus.Stopping
        active.cancel()
    }

    /**
     * Force-clears the busy guard if a request never unwinds. Cancelling the flow reaches the
     * native VLM cancel through the SDK, but a wedged engine can still leave the job's finally
     * block unreached, so this timeout is the UI backstop that surfaces the failure and
     * re-enables the screen.
     */
    private fun startWatchdog() {
        watchdog?.cancel()
        watchdog = viewModelScope.launch {
            delay(GENERATION_TIMEOUT_MS)
            if (status.isBusy) {
                status = VisionRunStatus.Failed("Vision timed out after two minutes.")
                job?.cancel()
            }
        }
    }

    override fun onCleared() {
        watchdog?.cancel()
        job?.cancel()
    }

    /** The result of pre-flighting one picked file. */
    private sealed interface StageOutcome {
        data class Accepted(val image: StagedVisionImage) : StageOutcome
        data class Rejected(val reason: String) : StageOutcome
    }

    private fun stageFromUri(uri: Uri): StageOutcome {
        val context = getApplication<Application>()
        // The composer's policy, not a second copy of it: chat and Vision must refuse the same
        // file for the same stated reason, including the same size ceiling.
        ComposerAttachmentPolicy
            .reasonToReject(context, ComposerAttachmentKind.IMAGE, uri)
            ?.let { return StageOutcome.Rejected(it) }
        val bitmap = VisionImageDecoder.decode(context, uri)
            ?: return StageOutcome.Rejected("That image could not be opened. Try a PNG or JPEG.")
        return StageOutcome.Accepted(
            StagedVisionImage(
                bitmap = bitmap,
                name = ComposerAttachmentPolicy.displayName(
                    context,
                    ComposerAttachmentKind.IMAGE,
                    uri,
                ),
            ),
        )
    }

    private fun accept(staged: StagedVisionImage) {
        image = staged
        description = ""
        status = VisionRunStatus.Idle
    }

    private fun writeJpegToCache(bitmap: Bitmap): File {
        val file = File.createTempFile("vlm_", ".jpg", getApplication<Application>().cacheDir)
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it) }
        return file
    }

    private companion object {
        // Generous ceiling: a full detailed description on the slowest supported VLM stays well
        // under this, so only a genuinely hung native call trips it.
        const val GENERATION_TIMEOUT_MS = 120_000L
        const val JPEG_QUALITY = 90
    }
}

internal fun GenerationResult.toUiMetrics(processingMs: Long): VlmMetrics =
    VlmMetrics(
        tokens = outputTokens,
        tokensPerSecond = tokensPerSecond.toDouble(),
        processingMs = processingMs,
        ttftMs = timeToFirstTokenMs,
    )

internal fun GenerationResult.toDisplayText(): String = text.ifBlank { "I could not read that image." }

/**
 * A sentence for the user out of whatever the failure carried.
 *
 * `requireCurrent` throws with a written sentence, SDK exceptions carry a backend message, and a
 * few failures carry only a class name — the fallback exists so none of them reach the screen as
 * a blank error row.
 */
internal fun Exception.userFacingVisionMessage(): String =
    message?.takeIf { it.isNotBlank() } ?: "Vision failed. Try again, or pick another model."
