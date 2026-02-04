package com.runanywhere.kotlin_starter_example.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.kotlin_starter_example.services.ModelService
import com.runanywhere.kotlin_starter_example.ui.components.ModelLoaderWidget
import com.runanywhere.kotlin_starter_example.ui.theme.*
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.transcribe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

// Audio recording helper class
private class AudioRecorder {
    private var audioRecord: AudioRecord? = null
    @Volatile
    private var isRecording = false
    private val audioData = ByteArrayOutputStream()
    
    companion object {
        const val SAMPLE_RATE = 16000 // 16kHz for STT
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }
    
    fun startRecording(): Boolean {
        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
            return false
        }
        
        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize * 2
            )
            
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord?.release()
                audioRecord = null
                return false
            }
            
            audioData.reset()
            audioRecord?.startRecording()
            isRecording = true
            
            // Start reading audio in a thread
            Thread {
                val buffer = ByteArray(bufferSize)
                while (isRecording) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (read > 0) {
                        synchronized(audioData) {
                            audioData.write(buffer, 0, read)
                        }
                    }
                }
            }.start()
            
            return true
        } catch (e: SecurityException) {
            audioRecord?.release()
            audioRecord = null
            return false
        }
    }
    
    fun stopRecording(): ByteArray {
        isRecording = false
        audioRecord?.let { record ->
            if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                record.stop()
            }
            record.release()
        }
        audioRecord = null
        
        synchronized(audioData) {
            return audioData.toByteArray()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpeechToTextScreen(
    onNavigateBack: () -> Unit,
    modelService: ModelService = viewModel(),
    modifier: Modifier = Modifier
) {
    var isRecording by remember { mutableStateOf(false) }
    var isTranscribing by remember { mutableStateOf(false) }
    var transcription by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var hasPermission by remember { mutableStateOf(false) }
    
    // Audio recorder instance
    val audioRecorder = remember { AudioRecorder() }

    // Clean up audio recorder when leaving the screen
    DisposableEffect(Unit) {
        onDispose {
            audioRecorder.stopRecording()
        }
    }

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    
    // Check permission
    LaunchedEffect(Unit) {
        hasPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        hasPermission = isGranted
        if (!isGranted) {
            errorMessage = "Microphone permission is required for speech recognition"
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Speech to Text") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = PrimaryDark
                )
            )
        },
        containerColor = PrimaryDark
    ) { padding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Model loader section
            if (!modelService.isSTTLoaded) {
                ModelLoaderWidget(
                    modelName = "Whisper Tiny",
                    isDownloading = modelService.isSTTDownloading,
                    isLoading = modelService.isSTTLoading,
                    isLoaded = modelService.isSTTLoaded,
                    downloadProgress = modelService.sttDownloadProgress,
                    onLoadClick = { modelService.downloadAndLoadSTT() }
                )
                Spacer(modifier = Modifier.height(24.dp))
            }
            
            // Permission check
            if (!hasPermission) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = "Microphone permission required",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onErrorContainer
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(
                            onClick = {
                                permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                            }
                        ) {
                            Text("Grant Permission")
                        }
                    }
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
            
            Spacer(modifier = Modifier.height(32.dp))
            
            // Recording button with animation
            if (modelService.isSTTLoaded && hasPermission) {
                RecordingButton(
                    isRecording = isRecording,
                    isTranscribing = isTranscribing,
                    onClick = {
                        if (!isRecording && !isTranscribing) {
                            // Start recording
                            scope.launch {
                                try {
                                    val started = withContext(Dispatchers.IO) {
                                        audioRecorder.startRecording()
                                    }
                                    if (started) {
                                        isRecording = true
                                        errorMessage = null
                                    } else {
                                        errorMessage = "Failed to start audio recording"
                                    }
                                } catch (e: Exception) {
                                    errorMessage = "Recording failed: ${e.message}"
                                }
                            }
                        } else if (isRecording) {
                            // Stop recording and transcribe
                            isRecording = false
                            isTranscribing = true
                            scope.launch {
                                try {
                                    // Stop recording and get audio data
                                    val audioData = withContext(Dispatchers.IO) {
                                        audioRecorder.stopRecording()
                                    }
                                    
                                    if (audioData.isEmpty()) {
                                        errorMessage = "No audio recorded"
                                        isTranscribing = false
                                        return@launch
                                    }
                                    
                                    // Transcribe using RunAnywhere SDK
                                    val result = withContext(Dispatchers.IO) {
                                        RunAnywhere.transcribe(audioData)
                                    }
                                    
                                    if (result.isNotBlank()) {
                                        transcription = result
                                        errorMessage = null
                                    } else {
                                        errorMessage = "No speech detected"
                                    }
                                } catch (e: Exception) {
                                    errorMessage = "Transcription failed: ${e.message}"
                                } finally {
                                    isTranscribing = false
                                }
                            }
                        }
                    }
                )
                
                Spacer(modifier = Modifier.height(16.dp))
                
                Text(
                    text = when {
                        isRecording -> "Tap to stop recording"
                        isTranscribing -> "Transcribing..."
                        else -> "Tap to start recording"
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    color = when {
                        isRecording -> AccentViolet
                        isTranscribing -> AccentCyan
                        else -> TextMuted
                    }
                )
            }
            
            Spacer(modifier = Modifier.height(32.dp))
            
            // Transcription result
            if (transcription.isNotEmpty()) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = SurfaceCard
                    )
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(20.dp)
                    ) {
                        Text(
                            text = "Transcription",
                            style = MaterialTheme.typography.titleMedium,
                            color = AccentCyan
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = transcription,
                            style = MaterialTheme.typography.bodyLarge,
                            color = TextPrimary
                        )
                    }
                }
            }
            
            // Error message
            errorMessage?.let { error ->
                Spacer(modifier = Modifier.height(16.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Text(
                        text = error,
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
            
            // Info card
            if (modelService.isSTTLoaded && hasPermission) {
                Spacer(modifier = Modifier.height(32.dp))
                InfoCard()
            }
        }
    }
}

@Composable
private fun RecordingButton(
    isRecording: Boolean,
    isTranscribing: Boolean,
    onClick: () -> Unit
) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = if (isRecording) 1.1f else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "scale"
    )
    
    Box(
        modifier = Modifier.size(120.dp),
        contentAlignment = Alignment.Center
    ) {
        // Outer glow effect when recording
        if (isRecording) {
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .scale(scale)
                    .background(
                        brush = Brush.radialGradient(
                            colors = listOf(
                                AccentViolet.copy(alpha = 0.3f),
                                Color.Transparent
                            )
                        ),
                        shape = CircleShape
                    )
            )
        }
        
        // Button
        FloatingActionButton(
            onClick = onClick,
            modifier = Modifier.size(80.dp),
            containerColor = when {
                isRecording -> AccentViolet
                isTranscribing -> AccentCyan
                else -> AccentCyan
            },
            contentColor = Color.White
        ) {
            if (isTranscribing) {
                CircularProgressIndicator(
                    modifier = Modifier.size(32.dp),
                    color = Color.White
                )
            } else {
                Icon(
                    imageVector = if (isRecording) Icons.Rounded.Stop else Icons.Rounded.Mic,
                    contentDescription = if (isRecording) "Stop" else "Record",
                    modifier = Modifier.size(32.dp)
                )
            }
        }
    }
}

@Composable
private fun InfoCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = SurfaceCard.copy(alpha = 0.5f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Text(
                text = "How it works",
                style = MaterialTheme.typography.titleMedium,
                color = TextPrimary
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "• Tap the microphone to start recording\n" +
                        "• Speak clearly into your device\n" +
                        "• Tap the stop button when finished\n" +
                        "• View your transcribed text below",
                style = MaterialTheme.typography.bodyMedium,
                color = TextMuted
            )
        }
    }
}
