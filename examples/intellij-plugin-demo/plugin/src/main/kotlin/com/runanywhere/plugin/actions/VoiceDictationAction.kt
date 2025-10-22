package com.runanywhere.plugin.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.ui.Messages

class VoiceDictationAction : AnAction("Voice Dictation") {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        Messages.showInfoMessage(
            project,
            "Voice Dictation feature coming soon!",
            "Voice Dictation"
        )
    }
}
