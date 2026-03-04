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
import com.runanywhere.plugin.ui.WaveformVisualization
import com.runanywhere.sdk.`public`.RunAnywhere
import com.runanywhere.sdk.`public`.extensions.availableModels
import com.runanywhere.sdk.`public`.extensions.transcribe
import com.runanywhere.sdk.features.stt.JvmAudioCaptureManager
import com.runanywhere.sdk.features.stt.AudioChunk
import kotlinx.coroutines.CancellationException
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
 * 2. Continuous streaming - Periodic transcription as you speak
 */
class STTPanel(private val project: Project) : JPanel(BorderLayout()), Disposable {

    private val voiceService = project.getService(VoiceService::class.java)

    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        println("[STTPanel] Coroutine exception: ${throwable.message}")
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
    private val waveformVisualization = WaveformVisualization()

    // State tracking
    private var isSimpleRecording = false
    private var isStreaming = false
    private var recordingJob: Job? = null
    private var waveformJob: Job? = null
    private var recordingStartTime = 0L
    private var audioCaptureManager: JvmAudioCaptureManager? = null

    init {
        setupUI()
        setupListeners()
        updateStatus()
        Disposer.register(project, this)
    }

    private fun setupUI() {
        layout = BorderLayout(10, 10)
        border = EmptyBorder(10, 10, 10, 10)

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

        val controlPanel = JPanel(GridBagLayout()).apply {
            border = TitledBorder("Controls")
            val gbc = GridBagConstraints().apply {
                fill = GridBagConstraints.HORIZONTAL
                insets = Insets(5, 5, 5, 5)
            }

            gbc.gridx = 0; gbc.gridy = 0; gbc.gridwidth = 2
            add(JLabel("Simple Recording:").apply { font = font.deriveFont(Font.BOLD) }, gbc)

            gbc.gridy = 1; gbc.gridwidth = 1
            add(JLabel("Record and transcribe once:"), gbc)
            gbc.gridx = 1
            add(simpleRecordButton, gbc)

            gbc.gridx = 0; gbc.gridy = 2; gbc.gridwidth = 2
            add(JSeparator(), gbc)

            gbc.gridy = 3
            add(JLabel("Continuous Streaming:").apply { font = font.deriveFont(Font.BOLD) }, gbc)

            gbc.gridy = 4; gbc.gridwidth = 1
            add(JLabel("Periodic transcription:"), gbc)
            gbc.gridx = 1
            add(streamingButton, gbc)

            gbc.gridx = 0; gbc.gridy = 5; gbc.gridwidth = 2
            add(JSeparator(), gbc)

            gbc.gridy = 6; gbc.gridwidth = 1
            add(modelManagerButton, gbc)
            gbc.gridx = 1
            add(clearButton, gbc)
        }

        val waveformPanel = JPanel(BorderLayout()).apply {
            border = TitledBorder("Audio Waveform")
            add(waveformVisualization, BorderLayout.CENTER)
            preferredSize = Dimension(400, 120)
        }

        val transcriptionPanel = JPanel(BorderLayout()).apply {
            border = TitledBorder("Transcriptions")
            add(JBScrollPane(transcriptionArea), BorderLayout.CENTER)
            preferredSize = Dimension(400, 200)
        }

        val rightPanel = JPanel(BorderLayout(0, 10)).apply {
            add(waveformPanel, BorderLayout.NORTH)
            add(transcriptionPanel, BorderLayout.CENTER)
        }

        add(topPanel, BorderLayout.NORTH)
        val mainPanel = JPanel(BorderLayout(10, 10)).apply {
            add(controlPanel, BorderLayout.WEST)
            add(rightPanel, BorderLayout.CENTER)
        }
        add(mainPanel, BorderLayout.CENTER)
    }

    private fun setupListeners() {
        simpleRecordButton.addActionListener {
            if (!isStreaming) toggleSimpleRecording()
        }
        streamingButton.addActionListener {
            if (!isSimpleRecording) toggleStreaming()
        }
        modelManagerButton.addActionListener { showModelManager() }
        clearButton.addActionListener {
            transcriptionArea.text = ""
            waveformVisualization.clear()
        }
    }

    // =========================================================================
    // SIMPLE RECORDING MODE
    // =========================================================================

    private fun toggleSimpleRecording() {
        if (!isSimpleRecording) startSimpleRecording() else stopSimpleRecording()
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

        val captureManager = JvmAudioCaptureManager()
        audioCaptureManager = captureManager

        // Collect waveform energy from audioLevel StateFlow
        waveformJob = scope.launch {
            captureManager.audioLevel.collect { level ->
                ApplicationManager.getApplication().invokeLater {
                    waveformVisualization.updateEnergy(level)
                }
            }
        }

        // Collect audio chunks
        recordingJob = scope.launch {
            val audioBuffer = mutableListOf<AudioChunk>()
            try {
                captureManager.startRecording().collect { chunk ->
                    audioBuffer.add(chunk)

                    // Auto-stop after 30 seconds
                    val elapsed = (System.currentTimeMillis() - recordingStartTime) / 1000
                    if (elapsed >= 30) {
                        ApplicationManager.getApplication().invokeLater {
                            stopSimpleRecording()
                        }
                        return@collect
                    }

                    if (elapsed % 1 == 0L) {
                        ApplicationManager.getApplication().invokeLater {
                            statusLabel.text = "Recording... (${elapsed}s)"
                        }
                    }
                }
            } catch (_: CancellationException) {
                println("[STTPanel] Recording cancelled")
            } catch (e: Exception) {
                ApplicationManager.getApplication().invokeLater {
                    println("[STTPanel] Recording error: ${e.message}")
                    statusLabel.text = "Recording error"
                    statusLabel.foreground = Color.RED
                }
                return@launch
            }

            // Transcribe collected audio
            transcribeBuffer(audioBuffer)
        }
    }

    private fun stopSimpleRecording() {
        if (!isSimpleRecording) return

        val recordingDuration = ((System.currentTimeMillis() - recordingStartTime) / 1000).toInt()

        isSimpleRecording = false
        simpleRecordButton.text = "Start Recording"
        streamingButton.isEnabled = true
        statusLabel.text = "Transcribing ${recordingDuration}s of audio..."
        statusLabel.foreground = Color.ORANGE

        audioCaptureManager?.stopRecording()
        waveformJob?.cancel()
        waveformJob = null
        waveformVisualization.clear()
    }

    private suspend fun transcribeBuffer(audioBuffer: List<AudioChunk>) {
        if (audioBuffer.isEmpty()) return

        val recordingDuration = ((System.currentTimeMillis() - recordingStartTime) / 1000).toInt()

        try {
            val audioData = audioBuffer.flatMap { it.data.toList() }.toByteArray()
            val text = RunAnywhere.transcribe(audioData)

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
                println("[STTPanel] Transcription error: ${e.message}")
                appendTranscription("[Error] Failed to transcribe: ${e.message}")
                statusLabel.text = "Ready"
                statusLabel.foreground = Color.BLACK
            }
        }
    }

    // =========================================================================
    // STREAMING MODE (periodic batch transcription)
    // =========================================================================

    private fun toggleStreaming() {
        if (!isStreaming) startStreaming() else stopStreaming()
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

        val captureManager = JvmAudioCaptureManager()
        audioCaptureManager = captureManager

        // Waveform visualization from audio level
        waveformJob = scope.launch {
            captureManager.audioLevel.collect { level ->
                ApplicationManager.getApplication().invokeLater {
                    waveformVisualization.updateEnergy(level)
                }
            }
        }

        // Collect audio and periodically transcribe
        recordingJob = scope.launch {
            val audioBuffer = mutableListOf<AudioChunk>()
            val transcribeIntervalMs = 3000L
            var lastTranscribeTime = System.currentTimeMillis()

            try {
                captureManager.startRecording().collect { chunk ->
                    audioBuffer.add(chunk)

                    val now = System.currentTimeMillis()
                    if (now - lastTranscribeTime >= transcribeIntervalMs && audioBuffer.isNotEmpty()) {
                        // Transcribe accumulated audio
                        val audioData = audioBuffer.flatMap { it.data.toList() }.toByteArray()
                        audioBuffer.clear()
                        lastTranscribeTime = now

                        try {
                            val text = RunAnywhere.transcribe(audioData)
                            if (text.isNotEmpty()) {
                                ApplicationManager.getApplication().invokeLater {
                                    appendTranscription("[Streaming] $text")
                                    statusLabel.text = "Listening..."
                                    statusLabel.foreground = Color.GREEN
                                }
                            }
                        } catch (e: Exception) {
                            ApplicationManager.getApplication().invokeLater {
                                println("[STTPanel] Streaming transcription error: ${e.message}")
                                appendTranscription("[Error] ${e.message}")
                            }
                        }
                    }
                }
            } catch (_: CancellationException) {
                println("[STTPanel] Streaming cancelled")
            } catch (e: Exception) {
                ApplicationManager.getApplication().invokeLater {
                    println("[STTPanel] Streaming error: ${e.message}")
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

        audioCaptureManager?.stopRecording()
        recordingJob?.cancel()
        recordingJob = null
        waveformJob?.cancel()
        waveformJob = null
        audioCaptureManager = null
        waveformVisualization.clear()

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

    // =========================================================================
    // HELPERS
    // =========================================================================

    private fun appendTranscription(text: String) {
        val timestamp = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())
        val entry = "[$timestamp] $text\n"
        transcriptionArea.append(entry)
        transcriptionArea.caretPosition = transcriptionArea.document.length

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
                        println("[STTPanel] Found ${models.size} available models")
                    }
                }
            } catch (e: Exception) {
                ApplicationManager.getApplication().invokeLater {
                    println("[STTPanel] Failed to fetch models: ${e.message}")
                }
            }
        }
    }

    override fun dispose() {
        if (isStreaming) {
            audioCaptureManager?.stopRecording()
        }
        if (isSimpleRecording) {
            audioCaptureManager?.stopRecording()
        }
        recordingJob?.cancel()
        waveformJob?.cancel()
        audioCaptureManager = null
        scope.cancel()
        println("[STTPanel] Disposed")
    }
}
