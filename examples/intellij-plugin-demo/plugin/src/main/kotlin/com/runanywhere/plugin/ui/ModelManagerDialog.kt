package com.runanywhere.plugin.ui

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBScrollPane
import com.intellij.ui.table.JBTable
import com.runanywhere.sdk.`public`.RunAnywhere
import com.runanywhere.sdk.`public`.extensions.availableModels
import com.runanywhere.sdk.`public`.extensions.Models.ModelInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.awt.*
import javax.swing.*
import javax.swing.table.DefaultTableModel

/**
 * Dialog for managing RunAnywhere models (view available models)
 */
class ModelManagerDialog(private val project: Project) : DialogWrapper(project, true) {

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

        val tablePanel = JPanel(BorderLayout())
        tablePanel.add(JBScrollPane(table), BorderLayout.CENTER)
        tablePanel.preferredSize = Dimension(800, 400)

        val buttonPanel = JPanel(FlowLayout(FlowLayout.LEFT)).apply {
            add(refreshButton)
            add(Box.createHorizontalStrut(20))
            add(JLabel("Status:"))
            add(statusLabel)
        }

        panel.add(tablePanel, BorderLayout.CENTER)
        panel.add(buttonPanel, BorderLayout.SOUTH)

        setupListeners()

        return panel
    }

    private fun setupTable() {
        tableModel.addColumn("Model ID")
        tableModel.addColumn("Name")
        tableModel.addColumn("Category")
        tableModel.addColumn("Size (MB)")
        tableModel.addColumn("Status")

        table.selectionModel.selectionMode = ListSelectionModel.SINGLE_SELECTION
        table.setShowGrid(true)
        table.rowHeight = 25
    }

    private fun setupListeners() {
        refreshButton.addActionListener { loadModels() }
    }

    private fun loadModels() {
        scope.launch {
            try {
                statusLabel.text = "Loading models..."
                println("[ModelManager] Fetching available models...")

                val models = try {
                    RunAnywhere.availableModels()
                } catch (e: Exception) {
                    println("[ModelManager] Failed to fetch models: ${e.message}")
                    ApplicationManager.getApplication().invokeLater {
                        statusLabel.text = "Failed to fetch models: ${e.message}"
                    }
                    return@launch
                }

                println("[ModelManager] Fetched ${models.size} models")

                ApplicationManager.getApplication().invokeLater {
                    tableModel.rowCount = 0

                    if (models.isEmpty()) {
                        statusLabel.text = "No models available"
                        com.intellij.openapi.ui.Messages.showWarningDialog(
                            "No models available. Please check SDK initialization.",
                            "No Models Available"
                        )
                        return@invokeLater
                    }

                    models.forEach { model ->
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
                println("[ModelManager] Error loading models: ${e.message}")
                ApplicationManager.getApplication().invokeLater {
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
