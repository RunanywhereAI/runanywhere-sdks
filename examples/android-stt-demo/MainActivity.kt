package com.example.runanywhere.demo

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.STTSDKConfig
import com.runanywhere.sdk.events.TranscriptionEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Main activity demonstrating RunAnywhere SDK usage
 */
class MainActivity : AppCompatActivity() {

    private lateinit var startButton: Button
    private lateinit var stopButton: Button
    private lateinit var transcriptionText: TextView
    private lateinit var statusText: TextView

    private var audioRecord: AudioRecord? = null
    private var isRecording = false

    companion object {
        private const val REQUEST_RECORD_AUDIO_PERMISSION = 200
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        private const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        initializeViews()
        requestPermissions()
        initializeSDK()
    }

    private fun initializeViews() {
        startButton = findViewById(R.id.startButton)
        stopButton = findViewById(R.id.stopButton)
        transcriptionText = findViewById(R.id.transcriptionText)
        statusText = findViewById(R.id.statusText)

        startButton.setOnClickListener {
            startRecording()
        }

        stopButton.setOnClickListener {
            stopRecording()
        }

        stopButton.isEnabled = false
    }

    private fun requestPermissions() {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQUEST_RECORD_AUDIO_PERMISSION
            )
        }
    }

    private fun initializeSDK() {
        lifecycleScope.launch {
            try {
                statusText.text = "Initializing SDK..."

                val config = STTSDKConfig(
                    modelId = "whisper-base",
                    enableVAD = true,
                    language = "en"
                )

                RunAnywhere.initialize(config)

                statusText.text = "SDK Ready"
                startButton.isEnabled = true
            } catch (e: Exception) {
                statusText.text = "SDK initialization failed: ${e.message}"
                Toast.makeText(this@MainActivity, "Failed to initialize SDK", Toast.LENGTH_LONG)
                    .show()
            }
        }
    }

    private fun startRecording() {
        if (isRecording) return

        lifecycleScope.launch {
            try {
                statusText.text = "Starting recording..."
                isRecording = true

                startButton.isEnabled = false
                stopButton.isEnabled = true

                val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, ENCODING)

                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    CHANNEL,
                    ENCODING,
                    bufferSize
                )

                audioRecord?.startRecording()
                statusText.text = "Recording... (Listening for speech)"

                // Create audio stream
                val audioStream = flow {
                    val buffer = ByteArray(bufferSize)
                    while (isRecording) {
                        val read = audioRecord?.read(buffer, 0, bufferSize) ?: 0
                        if (read > 0) {
                            emit(buffer.copyOf(read))
                        }
                    }
                }

                // Process with STT
                RunAnywhere.transcribeStream(audioStream).collect { event ->
                    withContext(Dispatchers.Main) {
                        when (event) {
                            is TranscriptionEvent.SpeechStart -> {
                                statusText.text = "Speech detected - Transcribing..."
                            }

                            is TranscriptionEvent.SpeechEnd -> {
                                statusText.text = "Speech ended"
                            }

                            is TranscriptionEvent.PartialTranscription -> {
                                transcriptionText.text = event.text
                            }

                            is TranscriptionEvent.FinalTranscription -> {
                                transcriptionText.append("\n${event.text}")
                                statusText.text = "Listening for speech..."
                            }

                            is TranscriptionEvent.Error -> {
                                statusText.text = "Error: ${event.error.message}"
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    statusText.text = "Recording error: ${e.message}"
                    Toast.makeText(this@MainActivity, "Recording failed", Toast.LENGTH_SHORT).show()
                    stopRecording()
                }
            }
        }
    }

    private fun stopRecording() {
        isRecording = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        startButton.isEnabled = true
        stopButton.isEnabled = false
        statusText.text = "Recording stopped"
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRecording()

        lifecycleScope.launch {
            RunAnywhere.cleanup()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == REQUEST_RECORD_AUDIO_PERMISSION) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Permission granted
                Toast.makeText(this, "Recording permission granted", Toast.LENGTH_SHORT).show()
            } else {
                // Permission denied
                Toast.makeText(this, "Recording permission is required", Toast.LENGTH_LONG).show()
                startButton.isEnabled = false
            }
        }
    }
}
