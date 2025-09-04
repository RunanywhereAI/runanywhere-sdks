package com.runanywhere.plugin.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.components.service
import com.intellij.openapi.ui.Messages
import com.runanywhere.plugin.services.VoiceService

/**
 * Action to trigger voice command input
 */
class VoiceCommandAction : AnAction("Voice Command") {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project
        if (project == null) {
            Messages.showErrorDialog(
                "No project is open",
                "Voice Command Error"
            )
            return
        }

        val voiceService = project.service<VoiceService>()

        // For now, just show a message
        Messages.showInfoMessage(
            project,
            "Voice command feature is being initialized...\nPress Ctrl+Shift+V to activate",
            "RunAnywhere Voice Commands"
        )

        // Start voice capture
        voiceService.startVoiceCapture()

        // TODO: Show voice input dialog and process commands
    }

    override fun update(e: AnActionEvent) {
        // Enable the action only when a project is open
        e.presentation.isEnabled = e.project != null
    }
}
