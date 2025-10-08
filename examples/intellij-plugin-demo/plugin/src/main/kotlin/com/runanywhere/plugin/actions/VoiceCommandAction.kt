package com.runanywhere.plugin.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.actionSystem.CommonDataKeys
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.components.service
import com.intellij.openapi.ui.Messages
import com.runanywhere.plugin.isInitialized
import com.runanywhere.plugin.services.VoiceService
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.components.stt.STTStreamEvent
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import javax.swing.SwingUtilities

/**
 * Action to trigger voice command input with STT
 */
class VoiceCommandAction : AnAction("Voice Command") {

    private var isRecording = false

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project
        if (project == null) {
            Messages.showErrorDialog(
                "No project is open",
                "Voice Command Error"
            )
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

        val voiceService = project.service<VoiceService>()
        val editor = e.getData(CommonDataKeys.EDITOR)

        if (!isRecording) {
            // Start recording
            isRecording = true
            e.presentation.text = "Stop Recording"

            // Use the new streaming transcription API
            GlobalScope.launch {
                try {
                    RunAnywhere.startStreamingTranscription()
                        .collect { sttEvent ->
                            // Handle different STT event types
                            when (sttEvent) {
                                is STTStreamEvent.FinalTranscription -> {
                                    val transcription = sttEvent.result.transcript
                                    SwingUtilities.invokeLater {
                                        if (editor != null && editor.document.isWritable) {
                                            // Insert transcription at cursor position
                                            WriteCommandAction.runWriteCommandAction(project) {
                                                val offset = editor.caretModel.offset
                                                editor.document.insertString(offset, transcription)
                                                editor.caretModel.moveToOffset(offset + transcription.length)
                                            }
                                        } else {
                                            // Show in dialog if no editor available
                                            Messages.showInfoMessage(
                                                project,
                                                "Transcription: $transcription",
                                                "Voice Command Result"
                                            )
                                        }
                                    }
                                }
                                is STTStreamEvent.PartialTranscription -> {
                                    // Could show partial results in status bar if desired
                                    // For now, we'll just ignore partial results
                                }
                                is STTStreamEvent.AudioLevelChanged -> {
                                    // Could show audio level indicator if desired
                                    // For now, we'll just ignore audio level changes
                                }
                                is STTStreamEvent.Error -> {
                                    // Handle transcription errors
                                    SwingUtilities.invokeLater {
                                        Messages.showErrorDialog(
                                            project,
                                            "Transcription error: ${sttEvent.error}",
                                            "Voice Command Error"
                                        )
                                    }
                                }
                                is STTStreamEvent.LanguageDetected -> {
                                    // Language detection - could log or ignore
                                }
                                STTStreamEvent.SilenceDetected -> {
                                    // Silence detection - could use for UI feedback
                                }
                                is STTStreamEvent.SpeakerChanged -> {
                                    // Speaker change - could use for multi-speaker scenarios
                                }
                                STTStreamEvent.SpeechEnded -> {
                                    // Speech ended - could use for UI feedback
                                }
                                STTStreamEvent.SpeechStarted -> {
                                    // Speech started - could use for UI feedback
                                }
                            }
                        }
                } catch (e: Exception) {
                    SwingUtilities.invokeLater {
                        Messages.showErrorDialog(
                            project,
                            "Voice transcription failed: ${e.message}",
                            "Voice Command Error"
                        )
                    }
                } finally {
                    SwingUtilities.invokeLater {
                        isRecording = false
                        e.presentation.text = "Voice Command"
                    }
                }
            }
        } else {
            // Stop recording
            RunAnywhere.stopStreamingTranscription()
            isRecording = false
            e.presentation.text = "Voice Command"
        }
    }

    override fun update(e: AnActionEvent) {
        // Enable the action only when a project is open
        e.presentation.isEnabled = e.project != null

        // Update text based on recording state
        if (isRecording) {
            e.presentation.text = "Stop Recording"
        } else {
            e.presentation.text = "Voice Command"
        }
    }
}
