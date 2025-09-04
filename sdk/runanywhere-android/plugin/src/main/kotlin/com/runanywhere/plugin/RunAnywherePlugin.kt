package com.runanywhere.plugin

import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.StartupActivity
import com.intellij.openapi.components.service

/**
 * Main plugin startup activity
 */
class RunAnywherePlugin : StartupActivity {
    override fun runActivity(project: Project) {
        // Initialize plugin services
        val voiceService = project.service<services.VoiceService>()

        // Log startup
        println("RunAnywhere Voice Commands plugin initialized for project: ${project.name}")
    }
}
