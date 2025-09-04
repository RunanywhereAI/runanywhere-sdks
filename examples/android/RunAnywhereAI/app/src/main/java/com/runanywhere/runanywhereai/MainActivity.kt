package com.runanywhere.runanywhereai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme
import com.runanywhere.sdk.public.RunAnywhereSTT
import com.runanywhere.sdk.public.STTSDKConfig
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize the SDK
        GlobalScope.launch {
            try {
                val config = STTSDKConfig(
                    modelId = "whisper-base",
                    enableVAD = true,
                    language = "en"
                )
                RunAnywhereSTT.initialize(config)
            } catch (e: Exception) {
                // Handle initialization error
                e.printStackTrace()
            }
        }

        enableEdgeToEdge()
        setContent {
            RunAnywhereAITheme {
                SimpleDemoApp()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        // Cleanup SDK resources
        GlobalScope.launch {
            try {
                RunAnywhereSTT.cleanup()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SimpleDemoApp() {
    var isRecording by remember { mutableStateOf(false) }
    var transcriptionResult by remember { mutableStateOf("Press the button to start recording") }

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
                        text = "SDK Status",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = " RunAnywhere STT SDK v1.0.0",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = "Model: Whisper Base",
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
                    Text(
                        text = "Transcription",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = transcriptionResult,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
            }

            // Record Button
            Button(
                onClick = {
                    isRecording = !isRecording
                    if (isRecording) {
                        transcriptionResult = "Recording... (Mock implementation)"
                        // TODO: Implement actual recording
                    } else {
                        transcriptionResult =
                            "Recording stopped. This is a mock transcription result."
                        // TODO: Stop recording and get actual transcription
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isRecording)
                        MaterialTheme.colorScheme.error
                    else
                        MaterialTheme.colorScheme.primary
                )
            ) {
                Text(
                    text = if (isRecording) "Stop Recording" else "Start Recording",
                    style = MaterialTheme.typography.labelLarge
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
                    Text("• On-device Speech-to-Text", style = MaterialTheme.typography.bodySmall)
                    Text("• Voice Activity Detection", style = MaterialTheme.typography.bodySmall)
                    Text("• Real-time transcription", style = MaterialTheme.typography.bodySmall)
                    Text("• Privacy-focused", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
