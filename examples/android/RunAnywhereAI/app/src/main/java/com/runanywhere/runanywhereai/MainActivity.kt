package com.runanywhere.runanywhereai

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.lifecycle.lifecycleScope
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKVoiceEvent
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.files.FileManager
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private var isRecording by mutableStateOf(false)
    private var transcriptionText by mutableStateOf("")
    private var vadStatus by mutableStateOf("VAD: Inactive")
    private var sttStatus by mutableStateOf("Whisper STT: Not Ready")
    private var audioRecord: AudioRecord? = null

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            initializeSDK()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize FileManager with application context
        FileManager.initialize(applicationContext)

        // Check microphone permission
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        } else {
            initializeSDK()
        }

        // Subscribe to SDK events
        subscribeToEvents()

        setContent {
            RunAnywhereAITheme {
                MainScreen()
            }
        }
    }

    private fun initializeSDK() {
        lifecycleScope.launch {
            try {
                // Initialize SDK in development mode
                RunAnywhere.initialize(
                    apiKey = "dev-api-key",
                    environment = SDKEnvironment.DEVELOPMENT
                )

                sttStatus = "Whisper STT: Initializing..."

                // Load the whisper-base model
                RunAnywhere.loadModel("whisper-base")

                sttStatus = "Whisper STT: Ready"

                // Get available models
                val models = RunAnywhere.availableModels()
                models.forEach { model ->
                    println("Available model: ${model.name} (${model.id})")
                }
            } catch (e: Exception) {
                sttStatus = "STT: Error - ${e.message}"
                e.printStackTrace()
            }
        }
    }

    private fun subscribeToEvents() {
        lifecycleScope.launch {
            // Subscribe to voice events
            EventBus.shared.voiceEvents.collectLatest { event ->
                when (event) {
                    is SDKVoiceEvent.TranscriptionStarted -> {
                        vadStatus = "VAD: Processing..."
                    }

                    is SDKVoiceEvent.TranscriptionPartial -> {
                        transcriptionText = event.text
                    }

                    is SDKVoiceEvent.TranscriptionFinal -> {
                        transcriptionText = event.text
                        vadStatus = "VAD: Complete"
                    }

                    is SDKVoiceEvent.PipelineError -> {
                        transcriptionText = "Error: ${event.error.message}"
                        vadStatus = "VAD: Error"
                    }
                }
            }
        }
    }

    @Composable
    fun MainScreen() {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("RunAnywhere AI - STT Demo") },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    )
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Status Card
                Card(
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp)
                    ) {
                        Text(
                            text = "Status",
                            style = MaterialTheme.typography.headlineSmall
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(text = sttStatus)
                        Text(text = vadStatus)
                        RunAnywhere.currentSTTModel?.let { model ->
                            Text(text = "Model: ${model.name}")
                        }
                    }
                }

                // Result Card
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp)
                    ) {
                        Text(
                            text = "Transcription",
                            style = MaterialTheme.typography.headlineSmall
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = transcriptionText.ifEmpty {
                                "Press the microphone button to start recording"
                            },
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }

                // Record Button
                FloatingActionButton(
                    onClick = { toggleRecording() },
                    containerColor = if (isRecording)
                        MaterialTheme.colorScheme.error
                    else
                        MaterialTheme.colorScheme.primary
                ) {
                    Icon(
                        imageVector = if (isRecording) Icons.Filled.Stop else Icons.Filled.Mic,
                        contentDescription = if (isRecording) "Stop" else "Record"
                    )
                }
            }
        }
    }

    private fun toggleRecording() {
        if (isRecording) {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private fun startRecording() {
        lifecycleScope.launch {
            try {
                isRecording = true
                vadStatus = "VAD: Active"
                transcriptionText = "Recording..."

                // Setup audio recording
                val sampleRate = 16000
                val channelConfig = AudioFormat.CHANNEL_IN_MONO
                val audioFormat = AudioFormat.ENCODING_PCM_16BIT
                val bufferSize =
                    AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )

                audioRecord?.startRecording()

                // For demo purposes, record for 3 seconds
                val audioBuffer = ByteArray(sampleRate * 2 * 3) // 3 seconds of audio
                var totalRead = 0
                val startTime = System.currentTimeMillis()

                while (isRecording && totalRead < audioBuffer.size &&
                    (System.currentTimeMillis() - startTime) < 3000
                ) {
                    val read = audioRecord?.read(
                        audioBuffer,
                        totalRead,
                        minOf(bufferSize, audioBuffer.size - totalRead)
                    ) ?: 0
                    if (read > 0) {
                        totalRead += read
                    }
                }

                stopRecording()

                // Transcribe the audio
                vadStatus = "VAD: Processing..."
                val transcription =
                    RunAnywhere.transcribe(audioBuffer.sliceArray(0 until totalRead))
                transcriptionText = transcription
                vadStatus = "VAD: Complete"

            } catch (e: Exception) {
                transcriptionText = "Error: ${e.message}"
                vadStatus = "VAD: Error"
                e.printStackTrace()
                stopRecording()
            }
        }
    }

    private fun stopRecording() {
        isRecording = false
        vadStatus = "VAD: Inactive"
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRecording()
    }
}
