package com.runanywhere.runanywhereai

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme
import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.WhisperSTTComponent
import com.runanywhere.sdk.components.stt.WhisperSTTConfig
import com.runanywhere.sdk.components.vad.VADConfig
import com.runanywhere.sdk.components.vad.WebRTCVADComponent
import com.runanywhere.sdk.models.WhisperModel
import com.runanywhere.sdk.services.ModelService
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : ComponentActivity() {

    private lateinit var modelService: ModelService
    private var sttComponent: WhisperSTTComponent? = null
    private var vadComponent: WebRTCVADComponent? = null

    private var audioRecord: AudioRecord? = null
    private var recordingJob: Job? = null

    // Audio recording parameters
    private val sampleRate = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

    // Permission launcher
    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted: Boolean ->
        if (!isGranted) {
            Toast.makeText(this, "Microphone permission is required for STT", Toast.LENGTH_LONG)
                .show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize model service
        modelService = ModelService(this)

        // Request microphone permission
        when {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED -> {
                // Permission already granted
                initializeSTT()
            }
            else -> {
                // Request permission
                requestPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
        }

        enableEdgeToEdge()
        setContent {
            RunAnywhereAITheme {
                STTDemoApp()
            }
        }
    }

    private fun initializeSTT() {
        GlobalScope.launch {
            try {
                // Initialize model service
                modelService.initialize()

                // Initialize VAD
                vadComponent = WebRTCVADComponent()
                vadComponent?.initialize(
                    VADConfig(
                        sampleRate = sampleRate,
                        frameSize = 320,  // 20ms at 16kHz
                        speechDurationMs = 100,
                        silenceDurationMs = 500
                    )
                )

                // Initialize Whisper STT
                sttComponent = WhisperSTTComponent()

                // Check if model is downloaded
                val whisperModel = WhisperModel(WhisperModel.ModelType.BASE, this@MainActivity)
                if (!whisperModel.isDownloaded()) {
                    // Download model
                    withContext(Dispatchers.Main) {
                        Toast.makeText(
                            this@MainActivity,
                            "Downloading Whisper model...",
                            Toast.LENGTH_LONG
                        ).show()
                    }

                    // For demo, we'll assume model is bundled or downloaded separately
                    // In production, implement download logic here
                }

                // Initialize with model path
                sttComponent?.initialize(whisperModel.getLocalPath())

            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        this@MainActivity,
                        "Failed to initialize STT: ${e.message}",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun STTDemoApp() {
        var isRecording by remember { mutableStateOf(false) }
        var transcriptionResult by remember { mutableStateOf("Press the microphone button to start recording") }
        var isProcessing by remember { mutableStateOf(false) }
        var vadStatus by remember { mutableStateOf("VAD: Inactive") }

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("RunAnywhere AI STT Demo") },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                        titleContentColor = MaterialTheme.colorScheme.primary
                    )
                )
            }
        ) { paddingValues ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                // SDK Status Card
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    )
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = "STT Engine Status",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold
                        )
                        Row {
                            Text(
                                text = "✓",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.primary
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "Whisper STT: ${if (sttComponent?.isReady == true) "Ready" else "Not Ready"}",
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                        Row {
                            Text(
                                text = "✓",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.primary
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = vadStatus,
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                        Text(
                            text = "Model: ${sttComponent?.currentModel ?: "Loading..."}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                // Transcription Result Card
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                    )
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.Top
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                text = "Transcription",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold
                            )
                            if (isProcessing) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = transcriptionResult,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }

                // Record Button
                FloatingActionButton(
                    onClick = {
                        if (sttComponent?.isReady != true) {
                            Toast.makeText(
                                this@MainActivity,
                                "STT not ready yet. Please wait...",
                                Toast.LENGTH_SHORT
                            ).show()
                            return@FloatingActionButton
                        }

                        isRecording = !isRecording
                        if (isRecording) {
                            startRecording(
                                onTranscription = { text ->
                                    transcriptionResult = text
                                    isProcessing = false
                                },
                                onVADStatus = { status ->
                                    vadStatus = status
                                },
                                onProcessing = {
                                    isProcessing = true
                                }
                            )
                        } else {
                            stopRecording()
                        }
                    },
                    modifier = Modifier.size(80.dp),
                    containerColor = if (isRecording)
                        MaterialTheme.colorScheme.error
                    else
                        MaterialTheme.colorScheme.primary
                ) {
                    Icon(
                        imageVector = if (isRecording) Icons.Filled.MicOff else Icons.Filled.Mic,
                        contentDescription = if (isRecording) "Stop Recording" else "Start Recording",
                        modifier = Modifier.size(40.dp)
                    )
                }

                // Features Info
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                    )
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = "Features",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            "• On-device Whisper Speech-to-Text",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Text(
                            "• WebRTC Voice Activity Detection",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Text(
                            "• Real-time transcription",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Text(
                            "• Multiple language support",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Text(
                            "• Privacy-focused (100% offline)",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        }
    }

    private fun startRecording(
        onTranscription: (String) -> Unit,
        onVADStatus: (String) -> Unit,
        onProcessing: () -> Unit
    ) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Toast.makeText(this, "Microphone permission required", Toast.LENGTH_SHORT).show()
            return
        }

        recordingJob = GlobalScope.launch(Dispatchers.IO) {
            try {
                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )

                audioRecord?.startRecording()

                val audioBuffer = ByteArray(bufferSize)
                val audioData = ByteArrayOutputStream()
                var speechDetected = false
                var silenceFrames = 0
                val maxSilenceFrames = 30 // About 600ms of silence at 20ms per frame

                while (isActive) {
                    val bytesRead = audioRecord?.read(audioBuffer, 0, bufferSize) ?: 0

                    if (bytesRead > 0) {
                        // Convert bytes to float array for VAD
                        val floatBuffer = FloatArray(bytesRead / 2)
                        val byteBuffer = ByteBuffer.wrap(audioBuffer, 0, bytesRead)
                        byteBuffer.order(ByteOrder.LITTLE_ENDIAN)

                        for (i in floatBuffer.indices) {
                            floatBuffer[i] = byteBuffer.getShort() / 32768.0f
                        }

                        // Check VAD
                        val vadResult = vadComponent?.processAudioChunk(floatBuffer)

                        withContext(Dispatchers.Main) {
                            if (vadResult?.isSpeech == true) {
                                onVADStatus("VAD: Speech detected (${(vadResult.confidence * 100).toInt()}%)")
                                speechDetected = true
                                silenceFrames = 0
                                audioData.write(audioBuffer, 0, bytesRead)
                            } else {
                                onVADStatus("VAD: Silence")
                                if (speechDetected) {
                                    silenceFrames++
                                    audioData.write(audioBuffer, 0, bytesRead)

                                    // Stop recording after sufficient silence
                                    if (silenceFrames >= maxSilenceFrames) {
                                        onProcessing()

                                        // Process the audio
                                        val audioBytes = audioData.toByteArray()
                                        if (audioBytes.isNotEmpty()) {
                                            processAudioData(audioBytes, onTranscription)
                                        }

                                        // Reset for next utterance
                                        audioData.reset()
                                        speechDetected = false
                                        silenceFrames = 0
                                    }
                                }
                            }
                        }
                    }

                    delay(20) // Small delay to prevent CPU overuse
                }

                // Process any remaining audio
                if (audioData.size() > 0) {
                    onProcessing()
                    processAudioData(audioData.toByteArray(), onTranscription)
                }

            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    onTranscription("Error: ${e.message}")
                }
            }
        }
    }

    private suspend fun processAudioData(audioBytes: ByteArray, onTranscription: (String) -> Unit) {
        try {
            val result = sttComponent?.transcribe(
                audioData = audioBytes,
                options = STTOptions(
                    language = "en",
                    enableTimestamps = true
                )
            )

            withContext(Dispatchers.Main) {
                if (result != null) {
                    val transcript = result.transcript
                    if (transcript.isNotBlank()) {
                        onTranscription(transcript)
                    } else {
                        onTranscription("(No speech detected)")
                    }
                } else {
                    onTranscription("(Unable to transcribe)")
                }
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                onTranscription("Transcription error: ${e.message}")
            }
        }
    }

    private fun stopRecording() {
        recordingJob?.cancel()
        audioRecord?.apply {
            stop()
            release()
        }
        audioRecord = null
    }

    override fun onDestroy() {
        super.onDestroy()

        stopRecording()

        // Cleanup SDK resources
        GlobalScope.launch {
            try {
                sttComponent?.cleanup()
                vadComponent?.cleanup()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
