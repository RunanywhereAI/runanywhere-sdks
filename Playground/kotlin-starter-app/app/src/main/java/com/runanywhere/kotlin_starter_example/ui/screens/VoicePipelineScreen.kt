package com.runanywhere.kotlin_starter_example.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
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
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionConfig
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionEvent
import com.runanywhere.sdk.public.extensions.streamVoiceSession
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.*

/**
 * Voice Pipeline Screen - Full STT → LLM → TTS with automatic silence detection
 * 
 * This screen demonstrates the simplest way to use RunAnywhere's voice pipeline.
 * All the business logic (silence detection, STT→LLM→TTS orchestration) is handled
 * by the SDK's streamVoiceSession API.
 * 
 * The app only needs to:
 * 1. Capture audio and provide it as a Flow<ByteArray>
 * 2. Collect VoiceSessionEvent to update UI
 * 3. Play audio when TurnCompleted event is received
 */

enum class VoiceSessionState {
    IDLE,
    LISTENING,
    SPEECH_DETECTED,
    PROCESSING,
    SPEAKING
}

data class VoiceMessage(
    val text: String,
    val type: String, // "user", "ai", "status"
    val timestamp: Long = System.currentTimeMillis()
)

/**
 * Simple audio capture that emits chunks as a Flow.
 * This is all the app needs to provide - the SDK handles everything else.
 */
private class AudioCaptureService {
    private var audioRecord: AudioRecord? = null
    
    @Volatile
    private var isCapturing = false
    
    companion object {
        const val SAMPLE_RATE = 16000
        const val CHUNK_SIZE_MS = 100 // Emit chunks every 100ms
    }
    
    fun startCapture(): Flow<ByteArray> = callbackFlow {
        val bufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val chunkSize = (SAMPLE_RATE * 2 * CHUNK_SIZE_MS) / 1000
        
        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(bufferSize, chunkSize * 2)
            )
            
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                close(IllegalStateException("AudioRecord initialization failed"))
                return@callbackFlow
            }
            
            audioRecord?.startRecording()
            isCapturing = true
            
            val readJob = launch(Dispatchers.IO) {
                val buffer = ByteArray(chunkSize)
                while (isActive && isCapturing) {
                    val bytesRead = audioRecord?.read(buffer, 0, chunkSize) ?: -1
                    if (bytesRead > 0) {
                        trySend(buffer.copyOf(bytesRead))
                    }
                }
            }
            
            awaitClose {
                readJob.cancel()
                stopCapture()
            }
        } catch (e: Exception) {
            stopCapture()
            close(e)
        }
    }
    
    fun stopCapture() {
        isCapturing = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
    }
}

/**
 * Play WAV audio using AudioTrack
 */
private suspend fun playWavAudio(wavData: ByteArray) = withContext(Dispatchers.IO) {
    if (wavData.size < 44) return@withContext

    // Parse WAV header to extract audio parameters
    val isWav = wavData[0] == 'R'.code.toByte() && wavData[1] == 'I'.code.toByte() &&
                wavData[2] == 'F'.code.toByte() && wavData[3] == 'F'.code.toByte()

    val sampleRate: Int
    val numChannels: Int
    val bitsPerSample: Int
    val pcmData: ByteArray

    if (isWav) {
        val buffer = java.nio.ByteBuffer.wrap(wavData).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        buffer.position(22)
        numChannels = buffer.short.toInt()
        sampleRate = buffer.int
        buffer.int // byteRate
        buffer.short // blockAlign
        bitsPerSample = buffer.short.toInt()

        // Find data chunk
        var dataOffset = 36
        while (dataOffset < wavData.size - 8) {
            if (wavData[dataOffset].toInt().toChar() == 'd' &&
                wavData[dataOffset + 1].toInt().toChar() == 'a' &&
                wavData[dataOffset + 2].toInt().toChar() == 't' &&
                wavData[dataOffset + 3].toInt().toChar() == 'a') {
                break
            }
            dataOffset++
        }
        dataOffset += 8 // Skip "data" and size
        if (dataOffset >= wavData.size) return@withContext
        pcmData = wavData.copyOfRange(dataOffset, wavData.size)
    } else {
        // Fallback for raw PCM data
        sampleRate = 22050
        numChannels = 1
        bitsPerSample = 16
        pcmData = wavData
    }

    val channelConfig = if (numChannels == 1)
        AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
    val encoding = if (bitsPerSample == 16)
        AudioFormat.ENCODING_PCM_16BIT else AudioFormat.ENCODING_PCM_8BIT

    val bufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, encoding)

    val audioTrack = AudioTrack.Builder()
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        .setAudioFormat(
            AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setEncoding(encoding)
                .setChannelMask(channelConfig)
                .build()
        )
        .setBufferSizeInBytes(maxOf(bufferSize, pcmData.size))
        .setTransferMode(AudioTrack.MODE_STATIC)
        .build()

    audioTrack.write(pcmData, 0, pcmData.size)
    audioTrack.play()

    val durationMs = (pcmData.size.toLong() * 1000) / (sampleRate * numChannels * (bitsPerSample / 8))
    delay(durationMs + 100)

    audioTrack.stop()
    audioTrack.release()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoicePipelineScreen(
    onNavigateBack: () -> Unit,
    modelService: ModelService = viewModel(),
    modifier: Modifier = Modifier
) {
    var sessionState by remember { mutableStateOf(VoiceSessionState.IDLE) }
    var messages by remember { mutableStateOf(listOf<VoiceMessage>()) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var hasPermission by remember { mutableStateOf(false) }
    var audioLevel by remember { mutableFloatStateOf(0f) }
    
    val audioCaptureService = remember { AudioCaptureService() }
    
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    
    // Voice session job
    var sessionJob by remember { mutableStateOf<Job?>(null) }
    
    // Check permission
    LaunchedEffect(Unit) {
        hasPermission = ContextCompat.checkSelfPermission(
            context, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        hasPermission = isGranted
        if (isGranted) {
            errorMessage = null
        } else {
            errorMessage = "Microphone permission is required"
        }
    }
    
    /**
     * Start voice session using the SDK's streamVoiceSession API.
     * 
     * This is the key integration point - the SDK handles all the business logic:
     * - Silence detection
     * - STT → LLM → TTS orchestration
     * - Continuous conversation mode
     */
    fun startSession() {
        sessionState = VoiceSessionState.LISTENING
        errorMessage = null
        messages = messages + VoiceMessage("Listening... speak and pause to send", "status")
        scope.launch {
            if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
        }
        
        // Get audio capture flow
        val audioFlow = audioCaptureService.startCapture()
        
        // Configure voice session
        val config = VoiceSessionConfig(
            silenceDuration = 1.5,      // 1.5 seconds of silence triggers processing
            speechThreshold = 0.1f,      // Audio level threshold for speech detection
            autoPlayTTS = false,         // We'll handle playback ourselves
            continuousMode = true        // Auto-resume listening after each turn
        )
        
        // Start the SDK voice session - all business logic is handled by the SDK
        sessionJob = scope.launch {
            try {
                RunAnywhere.streamVoiceSession(audioFlow, config).collect { event ->
                    when (event) {
                        is VoiceSessionEvent.Started -> {
                            sessionState = VoiceSessionState.LISTENING
                        }
                        
                        is VoiceSessionEvent.Listening -> {
                            audioLevel = event.audioLevel
                        }
                        
                        is VoiceSessionEvent.SpeechStarted -> {
                            sessionState = VoiceSessionState.SPEECH_DETECTED
                        }
                        
                        is VoiceSessionEvent.Processing -> {
                            sessionState = VoiceSessionState.PROCESSING
                            audioLevel = 0f
                        }
                        
                        is VoiceSessionEvent.Transcribed -> {
                            messages = messages + VoiceMessage(event.text, "user")
                            if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
                        }

                        is VoiceSessionEvent.Responded -> {
                            messages = messages + VoiceMessage(event.text, "ai")
                            if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
                        }
                        
                        is VoiceSessionEvent.Speaking -> {
                            sessionState = VoiceSessionState.SPEAKING
                        }
                        
                        is VoiceSessionEvent.TurnCompleted -> {
                            // Play the synthesized audio
                            event.audio?.let { audio ->
                                sessionState = VoiceSessionState.SPEAKING
                                playWavAudio(audio)
                            }
                            // Resume listening state
                            sessionState = VoiceSessionState.LISTENING
                            audioLevel = 0f
                        }
                        
                        is VoiceSessionEvent.Stopped -> {
                            sessionState = VoiceSessionState.IDLE
                            audioLevel = 0f
                        }
                        
                        is VoiceSessionEvent.Error -> {
                            errorMessage = event.message
                            sessionState = VoiceSessionState.IDLE
                        }
                    }
                }
            } catch (e: CancellationException) {
                // Expected when stopping
            } catch (e: Exception) {
                errorMessage = "Session error: ${e.message}"
                sessionState = VoiceSessionState.IDLE
            }
        }
    }
    
    /**
     * Stop voice session
     */
    fun stopSession() {
        sessionJob?.cancel()
        sessionJob = null
        audioCaptureService.stopCapture()
        sessionState = VoiceSessionState.IDLE
        audioLevel = 0f
    }
    
    // Cleanup on dispose
    DisposableEffect(Unit) {
        onDispose {
            sessionJob?.cancel()
            audioCaptureService.stopCapture()
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Voice Pipeline") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = PrimaryDark)
            )
        },
        containerColor = PrimaryDark
    ) { padding ->
        Column(modifier = modifier.fillMaxSize().padding(padding)) {
            val allModelsLoaded = modelService.isLLMLoaded && 
                                 modelService.isSTTLoaded && 
                                 modelService.isTTSLoaded
            
            // Model loader section
            if (!allModelsLoaded) {
                ModelLoaderSection(modelService)
            }
            
            // Permission check
            if (!hasPermission && allModelsLoaded) {
                PermissionCard { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) }
            }
            
            // Main content
            if (allModelsLoaded && hasPermission) {
                // Messages list
                LazyColumn(
                    state = listState,
                    modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    contentPadding = PaddingValues(vertical = 16.dp)
                ) {
                    if (messages.isEmpty()) {
                        item { EmptyStateMessage() }
                    }
                    items(messages) { message -> VoiceMessageBubble(message) }
                }
                
                // Control section
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(SurfaceCard.copy(alpha = 0.8f))
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // Audio level indicator (when listening)
                    if (sessionState == VoiceSessionState.LISTENING || sessionState == VoiceSessionState.SPEECH_DETECTED) {
                        AudioLevelIndicator(audioLevel, sessionState == VoiceSessionState.SPEECH_DETECTED)
                        Spacer(modifier = Modifier.height(16.dp))
                    }
                    
                    StatusIndicator(sessionState)
                    Spacer(modifier = Modifier.height(24.dp))
                    
                    VoiceButton(
                        sessionState = sessionState,
                        onClick = {
                            when (sessionState) {
                                VoiceSessionState.IDLE -> startSession()
                                else -> stopSession()
                            }
                        }
                    )
                    
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = getStatusText(sessionState),
                        style = MaterialTheme.typography.bodyLarge,
                        color = getStatusColor(sessionState)
                    )
                }
            }
            
            // Error message
            errorMessage?.let { ErrorCard(it) }
        }
    }
}

@Composable
private fun ModelLoaderSection(modelService: ModelService) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Voice Pipeline requires all models", style = MaterialTheme.typography.titleMedium, color = TextPrimary)
        
        ModelLoaderWidget(
            modelName = "SmolLM2 (LLM)",
            isDownloading = modelService.isLLMDownloading,
            isLoading = modelService.isLLMLoading,
            isLoaded = modelService.isLLMLoaded,
            downloadProgress = modelService.llmDownloadProgress,
            onLoadClick = { modelService.downloadAndLoadLLM() }
        )
        
        ModelLoaderWidget(
            modelName = "Whisper (STT)",
            isDownloading = modelService.isSTTDownloading,
            isLoading = modelService.isSTTLoading,
            isLoaded = modelService.isSTTLoaded,
            downloadProgress = modelService.sttDownloadProgress,
            onLoadClick = { modelService.downloadAndLoadSTT() }
        )
        
        ModelLoaderWidget(
            modelName = "Piper (TTS)",
            isDownloading = modelService.isTTSDownloading,
            isLoading = modelService.isTTSLoading,
            isLoaded = modelService.isTTSLoaded,
            downloadProgress = modelService.ttsDownloadProgress,
            onLoadClick = { modelService.downloadAndLoadTTS() }
        )
        
        Button(onClick = { modelService.downloadAndLoadAllModels() }, modifier = Modifier.fillMaxWidth()) {
            Text("Load All Models")
        }
    }
}

@Composable
private fun AudioLevelIndicator(audioLevel: Float, isSpeechDetected: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        // Recording badge
        Row(
            modifier = Modifier
                .background(if (isSpeechDetected) AccentGreen.copy(alpha = 0.2f) else Color.Red.copy(alpha = 0.1f), RoundedCornerShape(4.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            // Pulsing dot
            val infiniteTransition = rememberInfiniteTransition(label = "pulse")
            val pulseAlpha by infiniteTransition.animateFloat(
                initialValue = 1f, targetValue = 0.5f,
                animationSpec = infiniteRepeatable(tween(500), RepeatMode.Reverse),
                label = "dot"
            )
            Box(
                modifier = Modifier.size(8.dp).background(
                    if (isSpeechDetected) AccentGreen.copy(alpha = pulseAlpha) else Color.Red.copy(alpha = pulseAlpha),
                    CircleShape
                )
            )
            Text(
                text = if (isSpeechDetected) "SPEECH DETECTED" else "LISTENING",
                style = MaterialTheme.typography.labelSmall,
                color = if (isSpeechDetected) AccentGreen else Color.Red
            )
        }
        
        Spacer(modifier = Modifier.height(8.dp))
        
        // Audio level bars
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            repeat(10) { index ->
                val isActive = index < (audioLevel * 10).toInt()
                Box(
                    modifier = Modifier
                        .width(25.dp)
                        .height(8.dp)
                        .background(
                            if (isActive) AccentGreen else TextMuted.copy(alpha = 0.3f),
                            RoundedCornerShape(2.dp)
                        )
                )
            }
        }
    }
}

@Composable
private fun PermissionCard(onRequestPermission: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Microphone permission required", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))
            Button(onClick = onRequestPermission) { Text("Grant Permission") }
        }
    }
}

@Composable
private fun ErrorCard(error: String) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)
    ) {
        Text(error, modifier = Modifier.padding(16.dp), style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun StatusIndicator(state: VoiceSessionState) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        StatusDot("Listen", state == VoiceSessionState.LISTENING || state == VoiceSessionState.SPEECH_DETECTED, AccentCyan)
        StatusDot("Process", state == VoiceSessionState.PROCESSING, AccentViolet)
        StatusDot("Speak", state == VoiceSessionState.SPEAKING, AccentPink)
    }
}

@Composable
private fun StatusDot(label: String, isActive: Boolean, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(60.dp)) {
        Box(modifier = Modifier.size(12.dp).background(if (isActive) color else TextMuted.copy(alpha = 0.3f), CircleShape))
        Spacer(modifier = Modifier.height(4.dp))
        Text(label, style = MaterialTheme.typography.bodySmall, color = if (isActive) color else TextMuted)
    }
}

@Composable
private fun VoiceButton(sessionState: VoiceSessionState, onClick: () -> Unit) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = if (sessionState != VoiceSessionState.IDLE) 1.1f else 1f,
        animationSpec = infiniteRepeatable(tween(1000, easing = FastOutSlowInEasing), RepeatMode.Reverse),
        label = "scale"
    )
    
    Box(modifier = Modifier.size(120.dp), contentAlignment = Alignment.Center) {
        if (sessionState != VoiceSessionState.IDLE) {
            Box(
                modifier = Modifier.size(120.dp).scale(scale).background(
                    brush = Brush.radialGradient(listOf(AccentGreen.copy(alpha = 0.3f), Color.Transparent)),
                    shape = CircleShape
                )
            )
        }
        
        FloatingActionButton(
            onClick = onClick,
            modifier = Modifier.size(80.dp),
            containerColor = when (sessionState) {
                VoiceSessionState.IDLE -> AccentGreen
                VoiceSessionState.LISTENING, VoiceSessionState.SPEECH_DETECTED -> AccentViolet
                else -> AccentCyan
            },
            contentColor = Color.White
        ) {
            when (sessionState) {
                VoiceSessionState.PROCESSING -> CircularProgressIndicator(Modifier.size(32.dp), Color.White)
                VoiceSessionState.SPEAKING -> Icon(Icons.Rounded.VolumeUp, "Speaking", Modifier.size(32.dp))
                VoiceSessionState.IDLE -> Icon(Icons.Rounded.Mic, "Start", Modifier.size(32.dp))
                else -> Icon(Icons.Rounded.Stop, "Stop", Modifier.size(32.dp))
            }
        }
    }
}

@Composable
private fun EmptyStateMessage() {
    Column(modifier = Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Rounded.AutoAwesome, null, tint = AccentGreen, modifier = Modifier.size(64.dp))
        Spacer(modifier = Modifier.height(16.dp))
        Text("Voice Pipeline Ready", style = MaterialTheme.typography.titleLarge, color = TextPrimary)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Tap mic to start. Speak, then pause - it auto-detects silence and processes.",
            style = MaterialTheme.typography.bodyMedium,
            color = TextMuted
        )
    }
}

@Composable
private fun VoiceMessageBubble(message: VoiceMessage) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = when (message.type) {
            "user" -> Arrangement.End
            "status" -> Arrangement.Center
            else -> Arrangement.Start
        }
    ) {
        if (message.type == "ai") {
            Icon(Icons.Rounded.SmartToy, null, tint = AccentCyan, modifier = Modifier.size(32.dp).padding(top = 4.dp))
            Spacer(modifier = Modifier.width(8.dp))
        }
        
        Card(
            modifier = Modifier.widthIn(max = if (message.type == "status") 300.dp else 280.dp),
            shape = RoundedCornerShape(
                topStart = if (message.type == "user") 16.dp else 4.dp,
                topEnd = if (message.type == "user") 4.dp else 16.dp,
                bottomStart = 16.dp, bottomEnd = 16.dp
            ),
            colors = CardDefaults.cardColors(
                containerColor = when (message.type) {
                    "user" -> AccentCyan
                    "status" -> SurfaceCard.copy(alpha = 0.5f)
                    else -> SurfaceCard
                }
            )
        ) {
            Text(message.text, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium,
                color = if (message.type == "user") Color.White else TextPrimary)
        }
        
        if (message.type == "user") {
            Spacer(modifier = Modifier.width(8.dp))
            Icon(Icons.Rounded.Person, null, tint = AccentViolet, modifier = Modifier.size(32.dp).padding(top = 4.dp))
        }
    }
}

private fun getStatusText(state: VoiceSessionState) = when (state) {
    VoiceSessionState.IDLE -> "Tap to start"
    VoiceSessionState.LISTENING -> "Listening... pause to send"
    VoiceSessionState.SPEECH_DETECTED -> "Speaking detected..."
    VoiceSessionState.PROCESSING -> "Processing..."
    VoiceSessionState.SPEAKING -> "Speaking..."
}

private fun getStatusColor(state: VoiceSessionState) = when (state) {
    VoiceSessionState.IDLE -> TextMuted
    VoiceSessionState.LISTENING -> AccentCyan
    VoiceSessionState.SPEECH_DETECTED -> AccentGreen
    VoiceSessionState.PROCESSING -> AccentViolet
    VoiceSessionState.SPEAKING -> AccentPink
}
