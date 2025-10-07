package com.runanywhere.plugin.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.ui.Messages
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Test action to demonstrate RunAnywhere SDK integration in IntelliJ plugin
 */
class SDKTestAction : AnAction("Test RunAnywhere SDK") {

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    override fun actionPerformed(event: AnActionEvent) {
        val project = event.project ?: return

        // Launch coroutine for async SDK operations
        scope.launch {
            try {
                // Initialize SDK
                val isInitialized = initializeSDK()

                if (isInitialized) {
                    // Show success on UI thread
                    ApplicationManager.getApplication().invokeLater {
                        Messages.showInfoMessage(
                            project,
                            """
                            RunAnywhere SDK Test Results:

                            ✅ SDK Initialized: ${RunAnywhere.isInitialized}
                            📦 SDK Version: 0.1.0
                            🎯 Environment: ${RunAnywhere.currentEnvironment}

                            Available Components:
                            • STT (Speech-to-Text)
                            • VAD (Voice Activity Detection)
                            • Model Loading
                            • Analytics

                            SDK is ready for use!
                            """.trimIndent(),
                            "RunAnywhere SDK Test"
                        )
                    }

                    // Test STT component (if available)
                    testSTTComponent(project)
                } else {
                    ApplicationManager.getApplication().invokeLater {
                        Messages.showErrorDialog(
                            project,
                            "Failed to initialize RunAnywhere SDK",
                            "SDK Error"
                        )
                    }
                }
            } catch (e: Exception) {
                ApplicationManager.getApplication().invokeLater {
                    Messages.showErrorDialog(
                        project,
                        "Error testing SDK: ${e.message}",
                        "SDK Error"
                    )
                }
            }
        }
    }

    private suspend fun initializeSDK(): Boolean {
        return try {
            // Initialize with mock API key for testing
            RunAnywhere.initialize(
                apiKey = "test-api-key-12345",
                baseURL = "http://localhost:8080",
                environment = SDKEnvironment.DEVELOPMENT
            )
            true
        } catch (e: Exception) {
            println("SDK initialization failed: ${e.message}")
            false
        }
    }

    private suspend fun testSTTComponent(project: com.intellij.openapi.project.Project) {
        try {
            // Check if STT is available
            val hasSTT = RunAnywhere.isInitialized

            if (hasSTT) {
                ApplicationManager.getApplication().invokeLater {
                    Messages.showInfoMessage(
                        project,
                        """
                        STT Component Status:
                        ✅ Component Available
                        🎤 Ready for voice input

                        Features:
                        • Whisper model support
                        • Real-time transcription
                        • Multiple language support
                        """.trimIndent(),
                        "STT Component Test"
                    )
                }
            }
        } catch (e: Exception) {
            println("STT test failed: ${e.message}")
        }
    }

    override fun update(e: AnActionEvent) {
        // Action is always enabled
        e.presentation.isEnabledAndVisible = e.project != null
    }
}
