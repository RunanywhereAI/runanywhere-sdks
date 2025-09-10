package com.runanywhere.plugin.ui

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBScrollPane
import com.intellij.ui.table.JBTable
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.*
import java.awt.*
import javax.swing.*
import javax.swing.table.DefaultTableModel

/**
 * Dialog for managing RunAnywhere models (view available models)
 */
class ModelManagerDialog(private val project: Project) : DialogWrapper(project, true) {

    private val logger = com.runanywhere.sdk.foundation.SDKLogger("ModelManagerDialog")
    private val tableModel = DefaultTableModel()
    private val table = JBTable(tableModel)
    private val statusLabel = JBLabel("Ready")
    private val refreshButton = JButton("Refresh")

    private val scope = CoroutineScope(Dispatchers.IO)

    init {
        title = "RunAnywhere Model Manager"
        setOKButtonText("Close")

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
            add(refreshButton)
            add(Box.createHorizontalStrut(20))
            add(JLabel("Status:"))
            add(statusLabel)
        }

        // Add all panels
        panel.add(tablePanel, BorderLayout.CENTER)
        panel.add(buttonPanel, BorderLayout.SOUTH)

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
    }

    private fun setupListeners() {
        refreshButton.addActionListener {
            loadModels()
        }
    }

    private fun loadModels() {
        scope.launch {
            try {
                statusLabel.text = "Loading models..."

                logger.info("Fetching available models...")

                val models = try {
                    RunAnywhere.availableModels()
                } catch (e: Exception) {
                    logger.error("Failed to fetch models", e)
                    ApplicationManager.getApplication().invokeLater {
                        statusLabel.text = "Failed to fetch models: ${e.message}"
                    }
                    return@launch
                }

                logger.info("Fetched ${models.size} models")

                ApplicationManager.getApplication().invokeLater {
                    // Clear existing rows
                    tableModel.rowCount = 0

                    if (models.isEmpty()) {
                        statusLabel.text = "No models available"
                        logger.warn("No models returned from RunAnywhere.availableModels()")

                        // Add a message row to help debug
                        com.intellij.openapi.ui.Messages.showWarningDialog(
                            "No models available. Please check SDK initialization.",
                            "No Models Available"
                        )
                        return@invokeLater
                    }

                    // Add models to table
                    models.forEach { model ->
                        logger.info("Adding model to table: ${model.id}")

                        val sizeMB = (model.downloadSize ?: 0) / (1024 * 1024)

                        tableModel.addRow(arrayOf<Any>(
                            model.id,
                            model.name,
                            model.category.name,
                            sizeMB,
                            "Available"
                        ))
                    }

                    statusLabel.text = "Loaded ${models.size} models"
                }
            } catch (e: Exception) {
                logger.error("Error loading models", e)
                withContext(Dispatchers.Main) {
                    statusLabel.text = "Error: ${e.message}"
                }
            }
        }
    }

    override fun dispose() {
        scope.cancel()
        super.dispose()
    }
}
