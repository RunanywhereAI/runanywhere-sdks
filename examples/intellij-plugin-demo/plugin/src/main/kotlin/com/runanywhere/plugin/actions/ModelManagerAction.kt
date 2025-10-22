package com.runanywhere.plugin.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.ui.Messages
import com.runanywhere.plugin.isInitialized
import com.runanywhere.plugin.ui.ModelManagerDialog

/**
 * Action to open the Model Manager dialog
 */
class ModelManagerAction : AnAction("Manage Models") {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project
        if (project == null) {
            Messages.showErrorDialog(
                "No project is open",
                "Model Manager Error"
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

        // Open the Model Manager dialog
        val dialog = ModelManagerDialog(project)
        dialog.show()
    }

    override fun update(e: AnActionEvent) {
        // Enable the action only when a project is open and SDK is initialized
        e.presentation.isEnabled = e.project != null && isInitialized
    }
}
