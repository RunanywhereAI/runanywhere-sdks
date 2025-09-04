package com.runanywhere.plugin.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.actionSystem.CommonDataKeys
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.components.service
import com.intellij.openapi.ui.Messages
import com.runanywhere.plugin.RunAnywherePlugin
import com.runanywhere.plugin.services.VoiceService
import com.runanywhere.plugin.ui.ModelManagerDialog
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

        if (!RunAnywherePlugin.isInitialized) {
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

            voiceService.startVoiceCapture { transcription ->
                // Handle transcription result
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

                    isRecording = false
                    e.presentation.text = "Voice Command"
                }
            }
        } else {
            // Stop recording
            voiceService.stopVoiceCapture()
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
