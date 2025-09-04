package com.runanywhere.plugin.services

import com.intellij.openapi.Disposable
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project

/**
 * Service for managing voice capture and transcription
 */
@Service(Service.Level.PROJECT)
class VoiceService(private val project: Project) : Disposable {

    private var isInitialized = false
    private var isRecording = false

    init {
        println("VoiceService initialized for project: ${project.name}")
    }

    fun startVoiceCapture() {
        if (!isInitialized) {
            initialize()
        }

        isRecording = true
        println("Voice capture started")
        // TODO: Implement audio capture and STT pipeline
    }

    fun stopVoiceCapture() {
        isRecording = false
        println("Voice capture stopped")
    }

    private fun initialize() {
        // TODO: Initialize STT components
        println("Initializing STT components...")
        isInitialized = true
    }

    override fun dispose() {
        if (isRecording) {
            stopVoiceCapture()
        }
        println("VoiceService disposed")
    }
}
