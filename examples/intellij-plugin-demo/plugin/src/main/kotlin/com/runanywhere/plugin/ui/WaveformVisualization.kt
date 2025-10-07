package com.runanywhere.plugin.ui

import java.awt.*
import java.awt.geom.Path2D
import javax.swing.JComponent
import javax.swing.Timer

/**
 * Simple waveform visualization component for audio energy levels
 */
class WaveformVisualization : JComponent() {

    private val energyValues = mutableListOf<Float>()
    private val maxValues = 200 // Number of energy values to display
    private var currentEnergy = 0.0f

    // UI colors
    private val backgroundColor = Color(45, 45, 45)
    private val waveformColor = Color(100, 200, 100)
    private val energyColor = Color(255, 100, 100)
    private val gridColor = Color(80, 80, 80)

    init {
        preferredSize = Dimension(400, 100)
        minimumSize = Dimension(200, 60)

        // Repaint timer for smooth animation
        val repaintTimer = Timer(16) { // ~60 FPS
            repaint()
        }
        repaintTimer.start()
    }

    /**
     * Update the waveform with new audio energy level
     * @param energy Energy level from 0.0 to 1.0
     */
    fun updateEnergy(energy: Float) {
        currentEnergy = energy

        // Add to history
        energyValues.add(energy)

        // Keep only the last maxValues
        if (energyValues.size > maxValues) {
            energyValues.removeAt(0)
        }
    }

    /**
     * Clear the waveform
     */
    fun clear() {
        energyValues.clear()
        currentEnergy = 0.0f
        repaint()
    }

    override fun paintComponent(g: Graphics) {
        super.paintComponent(g)

        val g2d = g as Graphics2D
        g2d.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)

        val width = width.toFloat()
        val height = height.toFloat()

        // Clear background
        g2d.color = backgroundColor
        g2d.fillRect(0, 0, width.toInt(), height.toInt())

        // Draw grid lines
        drawGrid(g2d, width, height)

        // Draw waveform if we have data
        if (energyValues.isNotEmpty()) {
            drawWaveform(g2d, width, height)
        }

        // Draw current energy indicator
        drawEnergyIndicator(g2d, width, height)

        // Draw labels
        drawLabels(g2d, width, height)
    }

    private fun drawGrid(g2d: Graphics2D, width: Float, height: Float) {
        g2d.color = gridColor
        g2d.stroke = BasicStroke(1f)

        // Horizontal center line
        val centerY = height / 2
        g2d.drawLine(0, centerY.toInt(), width.toInt(), centerY.toInt())

        // Quarter lines
        val quarterY = height / 4
        g2d.drawLine(0, quarterY.toInt(), width.toInt(), quarterY.toInt())
        g2d.drawLine(0, (height - quarterY).toInt(), width.toInt(), (height - quarterY).toInt())
    }

    private fun drawWaveform(g2d: Graphics2D, width: Float, height: Float) {
        if (energyValues.size < 2) return

        g2d.color = waveformColor
        g2d.stroke = BasicStroke(2f)

        val path = Path2D.Float()
        val stepX = width / maxValues
        val centerY = height / 2

        // Start path
        val firstEnergy = energyValues[0]
        val firstY = centerY - (firstEnergy * centerY * 0.8f) // 80% of half height
        path.moveTo(0f, firstY)

        // Draw the waveform line
        for (i in 1 until energyValues.size) {
            val x = i * stepX
            val energy = energyValues[i]
            val y = centerY - (energy * centerY * 0.8f)
            path.lineTo(x, y)
        }

        g2d.draw(path)

        // Fill area under the curve for better visualization
        g2d.color = Color(waveformColor.red, waveformColor.green, waveformColor.blue, 50)
        val fillPath = Path2D.Float(path)
        fillPath.lineTo((energyValues.size - 1) * stepX, centerY)
        fillPath.lineTo(0f, centerY)
        fillPath.closePath()
        g2d.fill(fillPath)
    }

    private fun drawEnergyIndicator(g2d: Graphics2D, width: Float, height: Float) {
        // Current energy level bar on the right
        val barWidth = 20f
        val barX = width - barWidth - 10f
        val barY = 10f
        val barHeight = height - 20f

        // Background of energy bar
        g2d.color = Color(60, 60, 60)
        g2d.fillRect(barX.toInt(), barY.toInt(), barWidth.toInt(), barHeight.toInt())

        // Energy level fill
        val energyHeight = barHeight * currentEnergy
        val energyY = barY + barHeight - energyHeight

        // Color based on energy level
        val energyBarColor = when {
            currentEnergy > 0.7f -> Color(255, 100, 100) // Red for loud
            currentEnergy > 0.3f -> Color(255, 200, 100) // Orange for medium
            else -> Color(100, 200, 100) // Green for quiet
        }

        g2d.color = energyBarColor
        g2d.fillRect(barX.toInt(), energyY.toInt(), barWidth.toInt(), energyHeight.toInt())

        // Border
        g2d.color = Color.WHITE
        g2d.stroke = BasicStroke(1f)
        g2d.drawRect(barX.toInt(), barY.toInt(), barWidth.toInt(), barHeight.toInt())
    }

    private fun drawLabels(g2d: Graphics2D, width: Float, height: Float) {
        g2d.color = Color.LIGHT_GRAY
        g2d.font = Font("Arial", Font.PLAIN, 10)

        // Energy level text
        val energyText = String.format("%.3f", currentEnergy)
        g2d.drawString("Energy: $energyText", 10, 15)

        // Time axis label
        g2d.drawString("Time →", 10, height.toInt() - 5)

        // Amplitude axis label
        g2d.drawString("Level", width.toInt() - 60, height.toInt() - 5)
    }
}
