package com.runanywhere.plugin.toolwindow

import com.intellij.openapi.Disposable
import com.intellij.openapi.application.ApplicationManager
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
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.awt.BorderLayout
import java.awt.Color
import java.awt.Dimension
import java.awt.FlowLayout
import java.awt.Font
import java.awt.GridBagConstraints
import java.awt.GridBagLayout
import java.awt.Insets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.swing.JButton
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.JSeparator
import javax.swing.Timer
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
 * Main panel for STT functionality with two modes:
 * 1. Simple recording - Record audio then transcribe once
 * 2. Continuous streaming - Real-time transcription as you speak
 */
class STTPanel(private val project: Project) : JPanel(BorderLayout()), Disposable {

    private val logger = SDKLogger("STTPanel")
    private val voiceService = project.getService(VoiceService::class.java)

    // Create a coroutine scope with proper exception handling for IntelliJ
    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        logger.error("Coroutine exception", throwable)
    }
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob() + exceptionHandler)

    // UI Components
    private val simpleRecordButton = JButton("Start Recording")
    private val streamingButton = JButton("Start Streaming")
    private val modelManagerButton = JButton("Manage Models")
    private val clearButton = JButton("Clear")
    private val statusLabel = JLabel("Ready")
    private val transcriptionArea = JBTextArea().apply {
        isEditable = false
        lineWrap = true
        wrapStyleWord = true
        font = Font(Font.MONOSPACED, Font.PLAIN, 12)
    }

    // State tracking
    private var isSimpleRecording = false
    private var isStreaming = false
    private var recordingJob: Job? = null
    private var recordingStartTime = 0L

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

        // Top panel with title and status
        val topPanel = JPanel(BorderLayout()).apply {
            val titleLabel = JLabel("RunAnywhere Speech-to-Text").apply {
                font = font.deriveFont(Font.BOLD, 14f)
            }
            add(titleLabel, BorderLayout.WEST)

            val statusPanel = JPanel(FlowLayout(FlowLayout.RIGHT)).apply {
                add(JLabel("Status:"))
                add(statusLabel)
            }
            add(statusPanel, BorderLayout.EAST)
        }

        // Control panel with recording buttons
        val controlPanel = JPanel(GridBagLayout()).apply {
            border = TitledBorder("Controls")
            val gbc = GridBagConstraints().apply {
                fill = GridBagConstraints.HORIZONTAL
                insets = Insets(5, 5, 5, 5)
            }

            // Simple Recording Section
            gbc.gridx = 0
            gbc.gridy = 0
            gbc.gridwidth = 2
            add(JLabel("Simple Recording:").apply {
                font = font.deriveFont(Font.BOLD)
            }, gbc)

            gbc.gridy = 1
            gbc.gridwidth = 1
            add(JLabel("Record and transcribe once:"), gbc)

            gbc.gridx = 1
            add(simpleRecordButton, gbc)

            // Separator
            gbc.gridx = 0
            gbc.gridy = 2
            gbc.gridwidth = 2
            add(JSeparator(), gbc)

            // Streaming Section
            gbc.gridy = 3
            add(JLabel("Continuous Streaming:").apply {
                font = font.deriveFont(Font.BOLD)
            }, gbc)

            gbc.gridy = 4
            gbc.gridwidth = 1
            add(JLabel("Real-time transcription:"), gbc)

            gbc.gridx = 1
            add(streamingButton, gbc)

            // Separator
            gbc.gridx = 0
            gbc.gridy = 5
            gbc.gridwidth = 2
            add(JSeparator(), gbc)

            // Model Manager and Clear buttons
            gbc.gridy = 6
            gbc.gridwidth = 1
            add(modelManagerButton, gbc)

            gbc.gridx = 1
            add(clearButton, gbc)
        }

        // Center panel with transcription area
        val transcriptionPanel = JPanel(BorderLayout()).apply {
            border = TitledBorder("Transcriptions")
            add(JBScrollPane(transcriptionArea), BorderLayout.CENTER)
            preferredSize = Dimension(400, 300)
        }

        // Add all panels
        add(topPanel, BorderLayout.NORTH)

        val mainPanel = JPanel(BorderLayout(10, 10)).apply {
            add(controlPanel, BorderLayout.WEST)
            add(transcriptionPanel, BorderLayout.CENTER)
        }
        add(mainPanel, BorderLayout.CENTER)
    }

    private fun setupListeners() {
        // Simple recording button - Start/Stop recording then transcribe
        simpleRecordButton.addActionListener {
            if (!isStreaming) {
                toggleSimpleRecording()
            }
        }

        // Streaming button - Continuous real-time transcription
        streamingButton.addActionListener {
            if (!isSimpleRecording) {
                toggleStreaming()
            }
        }

        // Model manager button
        modelManagerButton.addActionListener {
            showModelManager()
        }

        // Clear button
        clearButton.addActionListener {
            transcriptionArea.text = ""
        }
    }

    /**
     * Toggle simple recording mode
     * This records audio for a fixed duration and transcribes it once
     */
    private fun toggleSimpleRecording() {
        if (!isSimpleRecording) {
            startSimpleRecording()
        } else {
            stopSimpleRecording()
        }
    }

    private fun startSimpleRecording() {
        if (!com.runanywhere.plugin.isInitialized) {
            statusLabel.text = "SDK not initialized"
            statusLabel.foreground = Color.RED
            return
        }

        isSimpleRecording = true
        simpleRecordButton.text = "Stop Recording"
        streamingButton.isEnabled = false
        statusLabel.text = "Recording..."
        statusLabel.foreground = Color.RED
        recordingStartTime = System.currentTimeMillis()

        // Start recording using SDK's new recording API
        RunAnywhere.startRecording()

        // Start a timer to show recording duration
        recordingJob = scope.launch {
            try {
                while (isSimpleRecording) {
                    val elapsed = (System.currentTimeMillis() - recordingStartTime) / 1000

                    // Auto-stop after 30 seconds
                    if (elapsed >= 30) {
                        ApplicationManager.getApplication().invokeLater {
                            stopSimpleRecording()
                        }
                        break
                    }

                    // Update status to show recording time
                    ApplicationManager.getApplication().invokeLater {
                        statusLabel.text = "Recording... (${elapsed}s)"
                    }

                    delay(100) // Update every 100ms
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                // Normal cancellation when user stops
                logger.info("Recording timer cancelled")
            }
        }
    }

    private fun stopSimpleRecording() {
        if (!isSimpleRecording) return

        // Calculate recording duration
        val recordingDuration = ((System.currentTimeMillis() - recordingStartTime) / 1000).toInt()

        isSimpleRecording = false
        simpleRecordButton.text = "Start Recording"
        streamingButton.isEnabled = true
        statusLabel.text = "Transcribing ${recordingDuration}s of audio..."
        statusLabel.foreground = Color.ORANGE

        // Cancel the timer job
        recordingJob?.cancel()
        recordingJob = null

        // Stop recording and transcribe using SDK's new API
        scope.launch {
            try {
                // Stop recording and get transcription of what was recorded
                val text = RunAnywhere.stopRecordingAndTranscribe()

                ApplicationManager.getApplication().invokeLater {
                    if (text.isNotEmpty()) {
                        appendTranscription("[Recorded ${recordingDuration}s] $text")
                    } else {
                        appendTranscription("[Recorded ${recordingDuration}s] (No speech detected)")
                    }
                    statusLabel.text = "Ready"
                    statusLabel.foreground = Color.BLACK
                }
            } catch (e: Exception) {
                ApplicationManager.getApplication().invokeLater {
                    logger.error("Transcription error", e)
                    appendTranscription("[Error] Failed to transcribe: ${e.message}")
                    statusLabel.text = "Ready"
                    statusLabel.foreground = Color.BLACK
                }
            }
        }
    }

    /**
     * Toggle streaming transcription mode
     * This provides real-time transcription as you speak
     */
    private fun toggleStreaming() {
        if (!isStreaming) {
            startStreaming()
        } else {
            stopStreaming()
        }
    }

    private fun startStreaming() {
        if (!com.runanywhere.plugin.isInitialized) {
            statusLabel.text = "SDK not initialized"
            statusLabel.foreground = Color.RED
            return
        }

        isStreaming = true
        streamingButton.text = "Stop Streaming"
        simpleRecordButton.isEnabled = false
        statusLabel.text = "Listening..."
        statusLabel.foreground = Color.GREEN

        // Use SDK's startStreamingTranscription API directly
        // The SDK handles all audio capture internally
        recordingJob = scope.launch {
            try {
                RunAnywhere.startStreamingTranscription(100) // 100ms chunks
                    .collect { event ->
                        when (event) {
                            is com.runanywhere.sdk.components.stt.STTStreamEvent.SpeechStarted -> {
                                ApplicationManager.getApplication().invokeLater {
                                    statusLabel.text = "Speaking..."
                                    statusLabel.foreground = Color.GREEN
                                }
                            }

                            is com.runanywhere.sdk.components.stt.STTStreamEvent.PartialTranscription -> {
                                ApplicationManager.getApplication().invokeLater {
                                    // Show partial transcription in status
                                    val partial = event.text.take(50)
                                    statusLabel.text =
                                        "Speaking: $partial${if (event.text.length > 50) "..." else ""}"
                                }
                            }

                            is com.runanywhere.sdk.components.stt.STTStreamEvent.FinalTranscription -> {
                                val text = event.result.transcript
                                if (text.isNotEmpty()) {
                                    ApplicationManager.getApplication().invokeLater {
                                        appendTranscription("[Streaming] $text")
                                        statusLabel.text = "Listening..."
                                        statusLabel.foreground = Color.GREEN
                                    }
                                }
                            }

                            is com.runanywhere.sdk.components.stt.STTStreamEvent.SpeechEnded -> {
                                ApplicationManager.getApplication().invokeLater {
                                    statusLabel.text = "Listening..."
                                    statusLabel.foreground = Color.GREEN
                                }
                            }

                            is com.runanywhere.sdk.components.stt.STTStreamEvent.SilenceDetected -> {
                                // Optionally update UI for silence
                            }

                            is com.runanywhere.sdk.components.stt.STTStreamEvent.Error -> {
                                ApplicationManager.getApplication().invokeLater {
                                    logger.error("Streaming error: ${event.error.message}")
                                    appendTranscription("[Error] ${event.error.message}")
                                    statusLabel.text = "Error - Restarting..."
                                    statusLabel.foreground = Color.RED
                                }
                            }

                            else -> {
                                // Handle any other events
                                logger.debug("Streaming event: $event")
                            }
                        }
                    }
            } catch (e: kotlinx.coroutines.CancellationException) {
                // Normal cancellation when stopping
                logger.info("Streaming cancelled")
            } catch (e: Exception) {
                ApplicationManager.getApplication().invokeLater {
                    logger.error("Streaming error", e)
                    appendTranscription("[Error] Streaming failed: ${e.message}")
                    statusLabel.text = "Ready"
                    statusLabel.foreground = Color.BLACK
                    isStreaming = false
                    streamingButton.text = "Start Streaming"
                    simpleRecordButton.isEnabled = true
                }
            }
        }
    }

    private fun stopStreaming() {
        isStreaming = false
        streamingButton.text = "Start Streaming"
        simpleRecordButton.isEnabled = true
        statusLabel.text = "Stopping..."
        statusLabel.foreground = Color.ORANGE

        // Stop SDK's internal audio capture
        RunAnywhere.stopStreamingTranscription()

        // Cancel the streaming job
        recordingJob?.cancel()
        recordingJob = null

        // Reset status after a short delay
        Timer(1000) {
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
        val timestamp = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())
        val entry = "[$timestamp] $text\n"
        transcriptionArea.append(entry)
        transcriptionArea.caretPosition = transcriptionArea.document.length

        // Insert into active editor if available
        val cleanText = text.removePrefix("[Recorded] ").removePrefix("[Streaming] ")
        if (cleanText.isNotEmpty() && !text.startsWith("[Listening...]")) {
            val editor = FileEditorManager.getInstance(project).selectedTextEditor
            if (editor != null && editor.document.isWritable) {
                ApplicationManager.getApplication().runWriteAction {
                    val offset = editor.caretModel.offset
                    editor.document.insertString(offset, cleanText)
                    editor.caretModel.moveToOffset(offset + cleanText.length)
                }
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
                if (com.runanywhere.plugin.isInitialized) {
                    val models = RunAnywhere.availableModels()
                    ApplicationManager.getApplication().invokeLater {
                        logger.info("Found ${models.size} available models")
                    }
                }
            } catch (e: Exception) {
                ApplicationManager.getApplication().invokeLater {
                    logger.warn("Failed to fetch models: ${e.message}")
                }
            }
        }
    }

    override fun dispose() {
        if (isStreaming) {
            voiceService.stopVoiceCapture()
        }
        if (isSimpleRecording) {
            RunAnywhere.stopStreamingTranscription()
        }
        recordingJob?.cancel()
        scope.cancel()
        logger.info("STTPanel disposed")
    }
}
