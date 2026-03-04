package com.runanywhere.plugin.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.actionSystem.CommonDataKeys
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.ui.Messages
import com.runanywhere.plugin.isInitialized
import com.runanywhere.sdk.`public`.RunAnywhere
import com.runanywhere.sdk.`public`.extensions.transcribe
import com.runanywhere.sdk.features.stt.JvmAudioCaptureManager
import com.runanywhere.sdk.features.stt.AudioChunk
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import javax.swing.SwingUtilities

/**
 * Action to trigger voice command input with STT.
 * Records audio using JvmAudioCaptureManager, then transcribes with RunAnywhere.transcribe().
 */
class VoiceCommandAction : AnAction("Voice Command") {

    private var isRecording = false
    private var recordingJob: Job? = null
    private var audioCaptureManager: JvmAudioCaptureManager? = null

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project
        if (project == null) {
            Messages.showErrorDialog("No project is open", "Voice Command Error")
            return
        }

        if (!isInitialized) {
            Messages.showWarningDialog(
                project,
                "RunAnywhere SDK is still initializing. Please wait...",
                "SDK Not Ready"
            )
            return
        }

        val editor = e.getData(CommonDataKeys.EDITOR)

        if (!isRecording) {
            isRecording = true
            e.presentation.text = "Stop Recording"

            val captureManager = JvmAudioCaptureManager()
            audioCaptureManager = captureManager

            @OptIn(DelicateCoroutinesApi::class)
            recordingJob = GlobalScope.launch {
                val audioBuffer = mutableListOf<AudioChunk>()
                try {
                    captureManager.startRecording().collect { chunk ->
                        audioBuffer.add(chunk)
                    }
                } catch (_: CancellationException) {
                    // Normal cancellation when user stops recording
                }

                // Transcribe collected audio
                if (audioBuffer.isNotEmpty()) {
                    try {
                        val audioData = audioBuffer.flatMap { it.data.toList() }.toByteArray()
                        val transcription = RunAnywhere.transcribe(audioData)

                        SwingUtilities.invokeLater {
                            if (editor != null && editor.document.isWritable) {
                                WriteCommandAction.runWriteCommandAction(project) {
                                    val offset = editor.caretModel.offset
                                    editor.document.insertString(offset, transcription)
                                    editor.caretModel.moveToOffset(offset + transcription.length)
                                }
                            } else {
                                Messages.showInfoMessage(
                                    project,
                                    "Transcription: $transcription",
                                    "Voice Command Result"
                                )
                            }
                        }
                    } catch (e: Exception) {
                        SwingUtilities.invokeLater {
                            Messages.showErrorDialog(
                                project,
                                "Transcription failed: ${e.message}",
                                "Voice Command Error"
                            )
                        }
                    }
                }
            }
        } else {
            // Stop recording — cancels the collection which triggers transcription
            audioCaptureManager?.stopRecording()
            recordingJob?.cancel()
            recordingJob = null
            audioCaptureManager = null
            isRecording = false
            e.presentation.text = "Voice Command"
        }
    }

    override fun update(e: AnActionEvent) {
        e.presentation.isEnabled = e.project != null
        e.presentation.text = if (isRecording) "Stop Recording" else "Voice Command"
    }
}
