package com.runanywhere.plugin.toolwindow

import com.intellij.openapi.Disposable
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.editor.Editor
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.Disposer
import com.intellij.openapi.wm.ToolWindow
import com.intellij.openapi.wm.ToolWindowFactory
import com.intellij.ui.components.JBScrollPane
import com.intellij.ui.components.JBTextArea
import com.intellij.ui.content.ContentFactory
import com.runanywhere.plugin.services.VoiceService
import com.runanywhere.plugin.ui.ModelManagerDialog
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.*
import java.awt.*
import java.awt.event.ActionEvent
import java.text.SimpleDateFormat
import java.util.Date
import javax.swing.*
import javax.swing.border.EmptyBorder
import javax.swing.border.TitledBorder

/**
 * Tool window for RunAnywhere STT with recording controls and transcription display
 */
class STTToolWindow : ToolWindowFactory {

    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val contentFactory = ContentFactory.getInstance()
        val content = contentFactory.createContent(STTPanel(project), "", false)
        toolWindow.contentManager.addContent(content)
    }
}

/**
 * Main panel for STT functionality
 */
class STTPanel(private val project: Project) : JPanel(BorderLayout()), Disposable {

    private val logger = SDKLogger("STTPanel")
    private val voiceService = project.getService(VoiceService::class.java)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // UI Components
    private val recordButton = JButton("Start Recording")
    private val modelButton = JButton("Model Manager")
    private val statusLabel = JLabel("Ready")
    private val transcriptionArea = JBTextArea().apply {
        isEditable = false
        lineWrap = true
        wrapStyleWord = true
        font = Font(Font.MONOSPACED, Font.PLAIN, 12)
    }

    private var isRecording = false

    init {
        setupUI()
        setupListeners()
        updateStatus()

        // Register for disposal
        Disposer.register(project, this)
    }

    private fun setupUI() {
        // Main layout
        layout = BorderLayout(10, 10)
        border = EmptyBorder(10, 10, 10, 10)

        // Top panel with controls
        val controlPanel = JPanel(FlowLayout(FlowLayout.LEFT)).apply {
            add(recordButton)
            add(Box.createHorizontalStrut(10))
            add(modelButton)
            add(Box.createHorizontalStrut(20))
            add(JLabel("Status:"))
            add(statusLabel)
        }

        // Center panel with transcription
        val transcriptionPanel = JPanel(BorderLayout()).apply {
            border = TitledBorder("Transcriptions")
            add(JBScrollPane(transcriptionArea), BorderLayout.CENTER)
            preferredSize = Dimension(400, 300)
        }

        add(controlPanel, BorderLayout.NORTH)
        add(transcriptionPanel, BorderLayout.CENTER)
    }

    private fun setupListeners() {
        recordButton.addActionListener { event ->
            toggleRecording(event)
        }

        modelButton.addActionListener {
            showModelManager()
        }
    }

    private fun toggleRecording(event: ActionEvent) {
        if (!isRecording) {
            startRecording()
        } else {
            stopRecording()
        }
    }

    private fun startRecording() {
        isRecording = true
        recordButton.text = "Stop Recording"
        statusLabel.text = "Recording..."
        statusLabel.foreground = Color.RED

        voiceService.startVoiceCapture { transcription ->
            ApplicationManager.getApplication().invokeLater {
                appendTranscription(transcription)
                stopRecording() // Auto-stop after transcription
            }
        }
    }

    private fun stopRecording() {
        isRecording = false
        recordButton.text = "Start Recording"
        statusLabel.text = "Processing..."
        statusLabel.foreground = Color.ORANGE

        voiceService.stopVoiceCapture()

        // Reset status after a delay
        Timer(2000) {
            ApplicationManager.getApplication().invokeLater {
                statusLabel.text = "Ready"
                statusLabel.foreground = Color.BLACK
            }
        }.apply {
            isRepeats = false
            start()
        }
    }

    private fun appendTranscription(text: String) {
        val timestamp = SimpleDateFormat("HH:mm:ss").format(Date())
        val entry = "[$timestamp] $text\n"
        transcriptionArea.append(entry)
        transcriptionArea.caretPosition = transcriptionArea.document.length

        // Insert into active editor if available
        val editor = FileEditorManager.getInstance(project).selectedTextEditor
        if (editor != null && editor.document.isWritable) {
            ApplicationManager.getApplication().runWriteAction {
                val offset = editor.caretModel.offset
                editor.document.insertString(offset, text)
                editor.caretModel.moveToOffset(offset + text.length)
            }
        }
    }

    private fun showModelManager() {
        val dialog = ModelManagerDialog(project)
        dialog.show()
    }

    private fun updateStatus() {
        scope.launch {
            try {
                val models = RunAnywhere.availableModels()
                ApplicationManager.getApplication().invokeLater {
                    logger.info("Found ${models.size} available models")
                }
            } catch (e: Exception) {
                ApplicationManager.getApplication().invokeLater {
                    logger.warn("Failed to fetch models: ${e.message}")
                }
            }
        }
    }

    override fun dispose() {
        scope.cancel()
        logger.info("STTPanel disposed")
    }
}
