package com.runanywhere.plugin.ui

import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.ui.components.JBLabel
// import com.intellij.ui.components.JBProgressBar
import javax.swing.JProgressBar
import com.intellij.ui.components.JBScrollPane
import com.intellij.ui.table.JBTable
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import java.awt.*
import javax.swing.*
import javax.swing.table.DefaultTableModel

/**
 * Dialog for managing RunAnywhere models (download, delete, view status)
 */
class ModelManagerDialog(private val project: Project) : DialogWrapper(project, true) {

    private val tableModel = DefaultTableModel()
    private val table = JBTable(tableModel)
    private val progressBar = JProgressBar()
    private val statusLabel = JBLabel("Ready")
    private val downloadButton = JButton("Download")
    private val deleteButton = JButton("Delete")
    private val refreshButton = JButton("Refresh")

    private var selectedModel: ModelInfo? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    init {
        title = "RunAnywhere Model Manager"
        setOKButtonText("Close")
        // setCancelButtonText(null)

        setupTable()
        loadModels()

        init()
    }

    override fun createCenterPanel(): JComponent {
        val panel = JPanel(BorderLayout())

        // Table panel
        val tablePanel = JPanel(BorderLayout())
        tablePanel.add(JBScrollPane(table), BorderLayout.CENTER)
        tablePanel.preferredSize = Dimension(800, 400)

        // Button panel
        val buttonPanel = JPanel(FlowLayout(FlowLayout.LEFT)).apply {
            add(downloadButton)
            add(deleteButton)
            add(refreshButton)
            add(Box.createHorizontalStrut(20))
            add(JLabel("Status:"))
            add(statusLabel)
        }

        // Progress panel
        val progressPanel = JPanel(BorderLayout()).apply {
            add(JLabel("Download Progress:"), BorderLayout.WEST)
            add(progressBar, BorderLayout.CENTER)
            progressBar.setStringPainted(true)
        }

        // Add all panels
        panel.add(tablePanel, BorderLayout.CENTER)

        val bottomPanel = JPanel(BorderLayout())
        bottomPanel.add(buttonPanel, BorderLayout.NORTH)
        bottomPanel.add(progressPanel, BorderLayout.SOUTH)
        panel.add(bottomPanel, BorderLayout.SOUTH)

        // Setup listeners
        setupListeners()

        return panel
    }

    private fun setupTable() {
        // Setup columns
        tableModel.addColumn("Model ID")
        tableModel.addColumn("Name")
        tableModel.addColumn("Category")
        tableModel.addColumn("Size (MB)")
        tableModel.addColumn("Status")

        // Configure table
        table.selectionModel.selectionMode = ListSelectionModel.SINGLE_SELECTION
        table.setShowGrid(true)
        table.rowHeight = 25

        // Selection listener
        table.selectionModel.addListSelectionListener { event ->
            if (!event.valueIsAdjusting) {
                val selectedRow = table.selectedRow
                if (selectedRow >= 0) {
                    val modelId = tableModel.getValueAt(selectedRow, 0) as String
                    selectedModel = findModelById(modelId)
                    updateButtonStates()
                }
            }
        }
    }

    private fun setupListeners() {
        downloadButton.addActionListener {
            selectedModel?.let { model ->
                downloadModel(model)
            }
        }

        deleteButton.addActionListener {
            selectedModel?.let { model ->
                deleteModel(model)
            }
        }

        refreshButton.addActionListener {
            loadModels()
        }
    }

    private fun loadModels() {
        scope.launch {
            try {
                statusLabel.text = "Loading models..."

                val models = RunAnywhere.availableModels()
                val downloader = RunAnywhere.getModelDownloader()

                withContext(Dispatchers.Main) {
                    // Clear existing rows
                    tableModel.rowCount = 0

                    // Add models to table
                    models.forEach { model ->
                        val isDownloaded = downloader.isModelDownloaded(model)
                        val status = if (isDownloaded) "Downloaded" else "Available"
                        val sizeMB = (model.downloadSize ?: 0) / (1024 * 1024)

                        tableModel.addRow(arrayOf(
                            model.id,
                            model.name,
                            model.category.name,
                            sizeMB,
                            status
                        ))
                    }

                    statusLabel.text = "Loaded ${models.size} models"
                    updateButtonStates()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    statusLabel.text = "Error: ${e.message}"
                }
            }
        }
    }

    private fun downloadModel(model: ModelInfo) {
        scope.launch {
            try {
                withContext(Dispatchers.Main) {
                    downloadButton.isEnabled = false
                    statusLabel.text = "Downloading ${model.id}..."
                    progressBar.setValue(0)
                }

                RunAnywhere.downloadModel(model.id).collect { progress ->
                    withContext(Dispatchers.Main) {
                        val percentage = (progress * 100).toInt()
                        progressBar.setValue(percentage)
                        progressBar.string = "$percentage%"

                        if (progress >= 1.0f) {
                            statusLabel.text = "Download complete: ${model.id}"

                            // Auto-load STT models
                            if (model.category == ModelCategory.SPEECH_RECOGNITION) {
                                statusLabel.text = "Loading STT model..."
                                launch {
                                    RunAnywhere.loadSTTModel(model)
                                    withContext(Dispatchers.Main) {
                                        statusLabel.text = "Model loaded: ${model.id}"
                                    }
                                }
                            }

                            loadModels() // Refresh table
                        }
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    statusLabel.text = "Download failed: ${e.message}"
                    progressBar.setValue(0)
                }
            } finally {
                withContext(Dispatchers.Main) {
                    downloadButton.isEnabled = true
                    updateButtonStates()
                }
            }
        }
    }

    private fun deleteModel(model: ModelInfo) {
        val confirm = JOptionPane.showConfirmDialog(
            contentPane,
            "Delete model ${model.name}?",
            "Confirm Delete",
            JOptionPane.YES_NO_OPTION
        )

        if (confirm == JOptionPane.YES_OPTION) {
            scope.launch {
                try {
                    val downloader = RunAnywhere.getModelDownloader()
                    val deleted = downloader.deleteModel(model)

                    withContext(Dispatchers.Main) {
                        if (deleted) {
                            statusLabel.text = "Deleted: ${model.id}"
                            loadModels()
                        } else {
                            statusLabel.text = "Failed to delete: ${model.id}"
                        }
                    }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        statusLabel.text = "Delete error: ${e.message}"
                    }
                }
            }
        }
    }

    private fun updateButtonStates() {
        val model = selectedModel
        if (model != null) {
            val downloader = RunAnywhere.getModelDownloader()
            val isDownloaded = downloader.isModelDownloaded(model)

            downloadButton.isEnabled = !isDownloaded
            deleteButton.isEnabled = isDownloaded
        } else {
            downloadButton.isEnabled = false
            deleteButton.isEnabled = false
        }
    }

    private fun findModelById(modelId: String): ModelInfo? {
        return runBlocking {
            RunAnywhere.availableModels().find { it.id == modelId }
        }
    }

    override fun dispose() {
        scope.cancel()
        super.dispose()
    }
}
