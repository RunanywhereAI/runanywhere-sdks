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
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.ModelCategory
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
    private val pauseButton = JButton("Pause")
    private val stopButton = JButton("Stop")
    private val insertButton = JButton("Insert at Cursor")
    private val clearButton = JButton("Clear")
    private val saveButton = JButton("Save")

    private val modelComboBox = JComboBox<ModelItem>()
    private val downloadModelButton = JButton("Download")
    private val modelStatusLabel = JLabel("No model loaded")

    private val transcriptionArea = JBTextArea()
    private val transcriptionHistoryArea = JBTextArea()
    private val logArea = JBTextArea()
    private val statusLabel = JLabel("Ready")
    private val recordingTimeLabel = JLabel("00:00")

    // State
    private var isRecording = false
    private var isPaused = false
    private var recordingStartTime = 0L
    private var recordingTimer: Timer? = null
    private val transcriptionHistory = mutableListOf<TranscriptionEntry>()
    private var currentTranscription = ""

    init {
        Disposer.register(project, this)
        setupUI()

        // Initialize with welcome message
        logToUI("INFO", "STT Tool Window initialized")
        logToUI("INFO", "Waiting for SDK initialization...")

        loadAvailableModels()
        updateButtonStates()
    }

    private fun setupUI() {
        // Top panel with model selection
        val topPanel = JPanel(BorderLayout()).apply {
            border = TitledBorder("Model Selection")

            val modelPanel = JPanel(FlowLayout(FlowLayout.LEFT)).apply {
                add(JLabel("STT Model:"))
                add(modelComboBox.apply {
                    preferredSize = Dimension(200, 25)
                })
                add(downloadModelButton)
                add(Box.createHorizontalStrut(20))
                add(modelStatusLabel)
            }

            add(modelPanel, BorderLayout.CENTER)
        }

        // Recording controls panel
        val controlsPanel = JPanel(FlowLayout(FlowLayout.LEFT)).apply {
            border = TitledBorder("Recording Controls")

            recordButton.apply {
                preferredSize = Dimension(120, 30)
                background = Color(0, 128, 0)
                foreground = Color.WHITE
                addActionListener { toggleRecording() }
            }

            pauseButton.apply {
                preferredSize = Dimension(80, 30)
                isEnabled = false
                addActionListener { togglePause() }
            }

            stopButton.apply {
                preferredSize = Dimension(80, 30)
                isEnabled = false
                addActionListener { stopRecording() }
            }

            add(recordButton)
            add(pauseButton)
            add(stopButton)
            add(Box.createHorizontalStrut(20))
            add(JLabel("Recording Time:"))
            add(recordingTimeLabel)
            add(Box.createHorizontalStrut(20))
            add(statusLabel)
        }

        // Current transcription panel
        val transcriptionPanel = JPanel(BorderLayout()).apply {
            border = TitledBorder("Current Transcription")

            transcriptionArea.apply {
                lineWrap = true
                wrapStyleWord = true
                font = Font("Monospaced", Font.PLAIN, 14)
            }

            val scrollPane = JBScrollPane(transcriptionArea).apply {
                preferredSize = Dimension(0, 150)
            }

            val buttonPanel = JPanel(FlowLayout(FlowLayout.LEFT)).apply {
                insertButton.apply {
                    addActionListener { insertAtCursor() }
                }
                clearButton.apply {
                    addActionListener {
                        transcriptionArea.text = ""
                        currentTranscription = ""
                    }
                }

                add(insertButton)
                add(clearButton)
            }

            add(scrollPane, BorderLayout.CENTER)
            add(buttonPanel, BorderLayout.SOUTH)
        }

        // History panel
        val historyPanel = JPanel(BorderLayout()).apply {
            border = TitledBorder("Transcription History")

            transcriptionHistoryArea.apply {
                isEditable = false
                lineWrap = true
                wrapStyleWord = true
                font = Font("Monospaced", Font.PLAIN, 12)
            }

            val scrollPane = JBScrollPane(transcriptionHistoryArea).apply {
                preferredSize = Dimension(0, 150)
            }

            val buttonPanel = JPanel(FlowLayout(FlowLayout.LEFT)).apply {
                saveButton.apply {
                    addActionListener { saveTranscriptions() }
                }

                val clearHistoryButton = JButton("Clear History").apply {
                    addActionListener {
                        transcriptionHistory.clear()
                        updateHistoryDisplay()
                    }
                }

                add(saveButton)
                add(clearHistoryButton)
            }

            add(scrollPane, BorderLayout.CENTER)
            add(buttonPanel, BorderLayout.SOUTH)
        }

        // Logging panel
        val loggingPanel = JPanel(BorderLayout()).apply {
            border = TitledBorder("Debug Logs")

            logArea.apply {
                isEditable = false
                lineWrap = true
                wrapStyleWord = true
                font = Font("Monospaced", Font.PLAIN, 10)
                background = Color(40, 44, 52)
                foreground = Color(171, 178, 191)
            }

            val scrollPane = JBScrollPane(logArea).apply {
                preferredSize = Dimension(0, 120)
            }

            val logButtonPanel = JPanel(FlowLayout(FlowLayout.LEFT)).apply {
                val clearLogsButton = JButton("Clear Logs").apply {
                    addActionListener {
                        SwingUtilities.invokeLater {
                            logArea.text = ""
                        }
                    }
                }

                val exportLogsButton = JButton("Export Logs").apply {
                    addActionListener { exportLogs() }
                }

                add(clearLogsButton)
                add(exportLogsButton)
            }

            add(scrollPane, BorderLayout.CENTER)
            add(logButtonPanel, BorderLayout.SOUTH)
        }

        // Main layout
        val mainPanel = JPanel().apply {
            layout = BoxLayout(this, BoxLayout.Y_AXIS)
            border = EmptyBorder(10, 10, 10, 10)

            add(topPanel)
            add(Box.createVerticalStrut(10))
            add(controlsPanel)
            add(Box.createVerticalStrut(10))
            add(transcriptionPanel)
            add(Box.createVerticalStrut(10))
            add(historyPanel)
            add(Box.createVerticalStrut(10))
            add(loggingPanel)
        }

        add(JBScrollPane(mainPanel), BorderLayout.CENTER)

        // Setup model selection listener
        modelComboBox.addActionListener {
            val selected = modelComboBox.selectedItem as? ModelItem
            selected?.let { updateModelStatus(it) }
        }

        downloadModelButton.addActionListener {
            val selected = modelComboBox.selectedItem as? ModelItem
            selected?.let { downloadModel(it.model) }
        }
    }

    private fun loadAvailableModels() {
        scope.launch {
            try {
                logToUI("INFO", "Loading available models...")

                // Wait for SDK initialization with timeout
                var attempts = 0
                while (!RunAnywhere.isInitialized && attempts < 10) {
                    delay(500)
                    attempts++
                    logToUI("INFO", "Waiting for SDK initialization... attempt $attempts")
                }

                if (!RunAnywhere.isInitialized) {
                    SwingUtilities.invokeLater {
                        modelStatusLabel.text = "SDK initialization timeout"
                    }
                    logToUI("ERROR", "SDK initialization timeout after ${attempts * 500}ms")
                    return@launch
                }

                logToUI("INFO", "SDK is initialized, fetching models...")
                val allModels = RunAnywhere.availableModels()
                val models = allModels.filter { it.category == ModelCategory.SPEECH_RECOGNITION }

                logToUI("INFO", "Found ${allModels.size} total models, ${models.size} STT models")

                if (models.isEmpty()) {
                    logToUI("WARN", "No STT models found")
                    SwingUtilities.invokeLater {
                        modelStatusLabel.text = "No STT models found"
                    }
                    return@launch
                }

                val downloader = RunAnywhere.getModelDownloader()
                val loadedModel = RunAnywhere.getLoadedSTTModel()

                SwingUtilities.invokeLater {
                    modelComboBox.removeAllItems()

                    models.forEach { model ->
                        val item = ModelItem(model)
                        modelComboBox.addItem(item)
                        logToUI("INFO", "Added model to dropdown: ${model.name} (${model.id})")

                        // Select loaded model if available
                        if (model == loadedModel) {
                            modelComboBox.selectedItem = item
                            logToUI("INFO", "Selected loaded model: ${model.id}")
                        }
                    }

                    // If no model is selected, select the first one
                    if (modelComboBox.selectedItem == null && models.isNotEmpty()) {
                        modelComboBox.selectedIndex = 0
                    }

                    if (models.isNotEmpty() && modelComboBox.selectedItem != null) {
                        updateModelStatus(modelComboBox.selectedItem as ModelItem)
                    }

                    logToUI("INFO", "Model loading completed successfully")
                }
            } catch (e: Exception) {
                logToUI("ERROR", "Failed to load models: ${e.message}")
                logger.error("Failed to load models", e)
                SwingUtilities.invokeLater {
                    modelStatusLabel.text = "Error: ${e.message}"
                }
            }
        }
    }

    private fun updateModelStatus(item: ModelItem) {
        scope.launch {
            try {
                val downloader = RunAnywhere.getModelDownloader()
                val isDownloaded = downloader.isModelDownloaded(item.model)
                val isLoaded = item.model == RunAnywhere.getLoadedSTTModel()
                val sizeMB = (item.model.downloadSize ?: 0) / 1048576

                logToUI("INFO", "Updating status for model ${item.model.id}: downloaded=$isDownloaded, loaded=$isLoaded, size=${sizeMB}MB")

                SwingUtilities.invokeLater {
                    val statusText = when {
                        isLoaded -> "✅ Loaded in memory (${sizeMB}MB)"
                        isDownloaded -> "💾 Downloaded, ready to load (${sizeMB}MB)"
                        else -> "📥 Available for download (${sizeMB}MB)"
                    }

                    modelStatusLabel.text = statusText

                    downloadModelButton.text = when {
                        isLoaded -> "✅ Loaded"
                        isDownloaded -> "🔄 Load Model"
                        else -> "⬇️ Download (${sizeMB}MB)"
                    }

                    downloadModelButton.isEnabled = !isLoaded

                    // Update button color based on status
                    downloadModelButton.background = when {
                        isLoaded -> Color(0, 150, 0) // Green
                        isDownloaded -> Color(0, 100, 200) // Blue
                        else -> Color(100, 100, 100) // Gray
                    }
                    downloadModelButton.foreground = Color.WHITE
                }
            } catch (e: Exception) {
                logToUI("ERROR", "Error checking model status: ${e.message}")
                logger.error("Error checking model status", e)
                SwingUtilities.invokeLater {
                    modelStatusLabel.text = "Error checking status: ${e.message}"
                }
            }
        }
    }

    private fun downloadModel(model: ModelInfo) {
        scope.launch {
            try {
                val downloader = RunAnywhere.getModelDownloader()
                val isDownloaded = downloader.isModelDownloaded(model)

                SwingUtilities.invokeLater {
                    downloadModelButton.isEnabled = false
                    modelStatusLabel.text = if (isDownloaded) "Loading..." else "Downloading..."
                }

                if (!isDownloaded) {
                    // Download the model
                    RunAnywhere.downloadModel(model.id).collect { progress ->
                        SwingUtilities.invokeLater {
                            val percentage = (progress * 100).toInt()
                            modelStatusLabel.text = "Downloading: $percentage%"
                        }
                    }
                }

                // Load the model
                SwingUtilities.invokeLater {
                    modelStatusLabel.text = "Loading model..."
                }

                RunAnywhere.loadSTTModel(model)

                SwingUtilities.invokeLater {
                    modelStatusLabel.text = "Loaded"
                    downloadModelButton.text = "Loaded"
                    downloadModelButton.isEnabled = false
                    statusLabel.text = "Model ready for transcription"
                    updateButtonStates()
                }

            } catch (e: Exception) {
                logToUI("ERROR", "Error downloading/loading model: ${e.message}")
                logger.error("Error downloading/loading model", e)
                SwingUtilities.invokeLater {
                    modelStatusLabel.text = "Error: ${e.message}"
                    downloadModelButton.isEnabled = true
                }
            }
        }
    }

    private fun toggleRecording() {
        if (!isRecording) {
            startRecording()
        } else if (isPaused) {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    private fun startRecording() {
        if (!RunAnywhere.isSTTPipelineReady()) {
            JOptionPane.showMessageDialog(
                this,
                "Please download and load an STT model first",
                "Model Not Ready",
                JOptionPane.WARNING_MESSAGE
            )
            return
        }

        isRecording = true
        isPaused = false
        recordingStartTime = System.currentTimeMillis()
        currentTranscription = ""

        recordButton.text = "Pause"
        recordButton.background = Color(255, 140, 0)
        statusLabel.text = "Recording..."
        updateButtonStates()

        // Start recording timer
        recordingTimer = Timer(1000) { updateRecordingTime() }
        recordingTimer?.start()

        // Start voice capture
        voiceService.startVoiceCapture { transcription ->
            ApplicationManager.getApplication().invokeLater {
                handleTranscription(transcription)
            }
        }
    }

    private fun pauseRecording() {
        isPaused = true
        recordButton.text = "Resume"
        recordButton.background = Color(0, 128, 0)
        statusLabel.text = "Paused"
        recordingTimer?.stop()

        // Stop voice capture temporarily
        voiceService.stopVoiceCapture()
    }

    private fun resumeRecording() {
        isPaused = false
        recordButton.text = "Pause"
        recordButton.background = Color(255, 140, 0)
        statusLabel.text = "Recording..."
        recordingTimer?.start()

        // Resume voice capture
        voiceService.startVoiceCapture { transcription ->
            ApplicationManager.getApplication().invokeLater {
                handleTranscription(transcription)
            }
        }
    }

    private fun stopRecording() {
        isRecording = false
        isPaused = false
        recordButton.text = "Start Recording"
        recordButton.background = Color(0, 128, 0)
        statusLabel.text = "Ready"
        recordingTimer?.stop()
        recordingTimeLabel.text = "00:00"
        updateButtonStates()

        // Stop voice capture
        voiceService.stopVoiceCapture()

        // Add to history if we have transcription
        if (currentTranscription.isNotEmpty()) {
            addToHistory(currentTranscription)
        }
    }

    private fun togglePause() {
        if (isPaused) {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    private fun handleTranscription(transcription: String) {
        currentTranscription = transcription
        transcriptionArea.text = transcription
        statusLabel.text = "Transcription received"
    }

    private fun addToHistory(transcription: String) {
        val entry = TranscriptionEntry(
            timestamp = Date(),
            text = transcription,
            duration = System.currentTimeMillis() - recordingStartTime
        )
        transcriptionHistory.add(0, entry) // Add to beginning
        updateHistoryDisplay()
    }

    private fun updateHistoryDisplay() {
        val dateFormat = SimpleDateFormat("HH:mm:ss")
        val historyText = transcriptionHistory.joinToString("\n\n") { entry ->
            val time = dateFormat.format(entry.timestamp)
            val duration = entry.duration / 1000
            "[$time] (${duration}s):\n${entry.text}"
        }
        transcriptionHistoryArea.text = historyText
    }

    private fun insertAtCursor() {
        val text = transcriptionArea.text
        if (text.isEmpty()) {
            JOptionPane.showMessageDialog(
                this,
                "No transcription to insert",
                "Nothing to Insert",
                JOptionPane.WARNING_MESSAGE
            )
            return
        }

        // Get active editor
        val editor: Editor? = FileEditorManager.getInstance(project).selectedTextEditor
        if (editor != null) {
            ApplicationManager.getApplication().runWriteAction {
                val document = editor.document
                val caretModel = editor.caretModel
                val offset = caretModel.offset
                document.insertString(offset, text)
                caretModel.moveToOffset(offset + text.length)
            }
            statusLabel.text = "Text inserted at cursor"
        } else {
            JOptionPane.showMessageDialog(
                this,
                "No active editor found",
                "Cannot Insert",
                JOptionPane.WARNING_MESSAGE
            )
        }
    }

    private fun saveTranscriptions() {
        if (transcriptionHistory.isEmpty()) {
            JOptionPane.showMessageDialog(
                this,
                "No transcriptions to save",
                "Nothing to Save",
                JOptionPane.WARNING_MESSAGE
            )
            return
        }

        val fileChooser = JFileChooser().apply {
            dialogTitle = "Save Transcriptions"
            selectedFile = java.io.File("transcriptions_${System.currentTimeMillis()}.txt")
        }

        if (fileChooser.showSaveDialog(this) == JFileChooser.APPROVE_OPTION) {
            try {
                fileChooser.selectedFile.writeText(transcriptionHistoryArea.text)
                statusLabel.text = "Transcriptions saved to ${fileChooser.selectedFile.name}"
            } catch (e: Exception) {
                logger.error("Failed to save transcriptions", e)
                JOptionPane.showMessageDialog(
                    this,
                    "Failed to save: ${e.message}",
                    "Save Error",
                    JOptionPane.ERROR_MESSAGE
                )
            }
        }
    }

    private fun updateRecordingTime() {
        val elapsed = (System.currentTimeMillis() - recordingStartTime) / 1000
        val minutes = elapsed / 60
        val seconds = elapsed % 60
        recordingTimeLabel.text = String.format("%02d:%02d", minutes, seconds)
    }

    private fun updateButtonStates() {
        pauseButton.isEnabled = isRecording && !isPaused
        stopButton.isEnabled = isRecording
        insertButton.isEnabled = transcriptionArea.text.isNotEmpty()
        clearButton.isEnabled = transcriptionArea.text.isNotEmpty()
        saveButton.isEnabled = transcriptionHistory.isNotEmpty()
    }

    private fun exportLogs() {
        val fileChooser = JFileChooser().apply {
            dialogTitle = "Export Debug Logs"
            selectedFile = java.io.File("stt_debug_logs_${System.currentTimeMillis()}.txt")
        }

        if (fileChooser.showSaveDialog(this) == JFileChooser.APPROVE_OPTION) {
            try {
                fileChooser.selectedFile.writeText(logArea.text)
                statusLabel.text = "Logs exported to ${fileChooser.selectedFile.name}"
            } catch (e: Exception) {
                logger.error("Failed to export logs", e)
                statusLabel.text = "Failed to export logs: ${e.message}"
            }
        }
    }

    private fun logToUI(level: String, message: String) {
        SwingUtilities.invokeLater {
            val timestamp = java.text.SimpleDateFormat("HH:mm:ss.SSS").format(java.util.Date())
            val logLine = "[$timestamp] $level: $message\n"

            logArea.append(logLine)

            // Keep only last 500 lines to prevent memory issues
            val lines = logArea.text.split("\n")
            if (lines.size > 500) {
                val recentLines = lines.takeLast(400).joinToString("\n")
                logArea.text = recentLines
            }

            // Auto-scroll to bottom
            logArea.caretPosition = logArea.document.length
        }
    }

    override fun dispose() {
        recordingTimer?.stop()
        scope.cancel()
        if (isRecording) {
            voiceService.stopVoiceCapture()
        }
    }

    // Helper classes
    private data class ModelItem(val model: ModelInfo) {
        override fun toString(): String = model.name
    }

    private data class TranscriptionEntry(
        val timestamp: Date,
        val text: String,
        val duration: Long
    )
}
