package com.runanywhere.sdk.features.tts

import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.File
import java.lang.ProcessBuilder
import kotlin.random.Random

/**
 * JVM-specific audio format configuration for native TTS synthesis
 * This is different from the SDK's AudioFormat enum in TTSComponent.kt
 */
data class JvmAudioFormatConfig(
    val sampleRate: Float,
    val sampleSizeInBits: Int,
    val channels: Int,
    val signed: Boolean,
    val bigEndian: Boolean,
)

/**
 * JVM TTS Service implementation
 * Platform-specific TTS service for JVM platforms using system TTS engines
 * Aligned with iOS TTSService protocol patterns
 */
class JvmTTSService : TTSService {
    private val logger = SDKLogger("JvmTTSService")
    private var _isSynthesizing = false
    private var _isInitialized = false
    private var availableTTSVoices = mutableListOf<TTSVoice>()

    companion object {
        private val logger = SDKLogger("JvmTTSService")

        // Default voices for different platforms
        private val WINDOWS_VOICES =
            listOf(
                TTSVoice("david", "Microsoft David", "en-US", TTSGender.MALE),
                TTSVoice("zira", "Microsoft Zira", "en-US", TTSGender.FEMALE),
                TTSVoice("mark", "Microsoft Mark", "en-US", TTSGender.MALE),
            )

        private val MACOS_VOICES =
            listOf(
                TTSVoice("alex", "Alex", "en-US", TTSGender.MALE),
                TTSVoice("samantha", "Samantha", "en-US", TTSGender.FEMALE),
                TTSVoice("victoria", "Victoria", "en-US", TTSGender.FEMALE),
            )

        private val LINUX_VOICES =
            listOf(
                TTSVoice("espeak-default", "eSpeak Default", "en-US", TTSGender.NEUTRAL),
                TTSVoice("festival-male", "Festival Male", "en-US", TTSGender.MALE),
            )
    }

    override suspend fun initialize() {
        withContext(Dispatchers.IO) {
            try {
                logger.info("Initializing JVM TTS service")

                // Detect platform and available TTS engines
                detectAvailableVoices()

                _isInitialized = true
                logger.info("JVM TTS service initialized with ${availableTTSVoices.size} voices")
            } catch (e: Exception) {
                logger.error("Failed to initialize JVM TTS service", e)
                throw SDKError.ComponentFailure("TTS initialization failed: ${e.message}")
            }
        }
    }

    // iOS-style synthesize method
    override suspend fun synthesize(
        text: String,
        options: TTSOptions,
    ): ByteArray {
        if (!_isInitialized) {
            throw SDKError.ComponentNotReady("TTS service not initialized")
        }

        _isSynthesizing = true
        return try {
            withContext(Dispatchers.IO) {
                // Find voice by ID or use default
                val voice =
                    options.voice?.let { voiceId ->
                        availableTTSVoices.find { it.id == voiceId }
                    } ?: availableTTSVoices.firstOrNull() ?: TTSVoice.DEFAULT
                logger.debug("Synthesizing text: '${text.take(50)}...' with voice: ${voice.name}")

                when {
                    isMacOS() -> synthesizeWithMacOSSay(text, voice, options.rate, options.pitch, options.volume)
                    isWindows() -> synthesizeWithWindowsSAPI(text, voice, options.rate, options.pitch, options.volume)
                    isLinux() -> synthesizeWithLinuxTTS(text, voice, options.rate, options.pitch, options.volume)
                    else -> generateSilentAudio(text.length) // Fallback
                }
            }
        } finally {
            _isSynthesizing = false
        }
    }

    // KMP Flow-based streaming
    override fun synthesizeStream(
        text: String,
        options: TTSOptions,
    ): Flow<ByteArray> =
        flow {
            if (!_isInitialized) {
                throw SDKError.ComponentNotReady("TTS service not initialized")
            }

            _isSynthesizing = true
            try {
                logger.debug("Starting streaming synthesis")

                // For streaming, we'll split text into sentences and synthesize each
                val sentences = text.split(Regex("[.!?]+")).filter { it.trim().isNotEmpty() }

                for (sentence in sentences) {
                    val audioData = synthesize(sentence.trim(), options)
                    if (audioData.isNotEmpty()) {
                        emit(audioData)
                    }
                    // Small delay between sentences to allow for natural speech rhythm
                    delay(100)
                }
            } finally {
                _isSynthesizing = false
            }
        }

    // iOS-style callback streaming
    override suspend fun synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: suspend (ByteArray) -> Unit,
    ) {
        synthesizeStream(text, options).collect { chunk ->
            onChunk(chunk)
        }
    }

    override fun getAllVoices(): List<TTSVoice> = availableTTSVoices.toList()

    override val availableVoices: List<String>
        get() = availableTTSVoices.map { it.id }

    override val isSynthesizing: Boolean
        get() = _isSynthesizing

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // For system TTS, we don't load external models
        logger.info("Model loading not applicable for system TTS service")
    }

    override fun cancelCurrent() {
        _isSynthesizing = false
        logger.debug("TTS synthesis cancelled")
    }

    override fun stop() = cancelCurrent()

    override suspend fun cleanup() {
        _isSynthesizing = false
        _isInitialized = false
        availableTTSVoices.clear()
        logger.info("JVM TTS service cleaned up")
    }

    // MARK: - Platform Detection

    private fun isMacOS(): Boolean = System.getProperty("os.name").lowercase().contains("mac")

    private fun isWindows(): Boolean = System.getProperty("os.name").lowercase().contains("windows")

    private fun isLinux(): Boolean = System.getProperty("os.name").lowercase().contains("linux")

    // MARK: - Voice Detection

    private suspend fun detectAvailableVoices() {
        withContext(Dispatchers.IO) {
            availableTTSVoices.clear()

            when {
                isMacOS() -> {
                    // Check available macOS voices using 'say' command
                    if (checkCommandAvailable("say")) {
                        availableTTSVoices.addAll(detectMacOSVoices())
                    }
                }
                isWindows() -> {
                    // Add Windows SAPI voices
                    availableTTSVoices.addAll(WINDOWS_VOICES)
                }
                isLinux() -> {
                    // Check for espeak or festival
                    if (checkCommandAvailable("espeak")) {
                        availableTTSVoices.addAll(LINUX_VOICES.filter { it.id.startsWith("espeak") })
                    }
                    if (checkCommandAvailable("festival")) {
                        availableTTSVoices.addAll(LINUX_VOICES.filter { it.id.startsWith("festival") })
                    }
                }
            }

            // Always add default voice as fallback
            if (availableTTSVoices.isEmpty()) {
                availableTTSVoices.add(TTSVoice.DEFAULT)
            }

            logger.info("Detected ${availableTTSVoices.size} TTS voices")
        }
    }

    private fun detectMacOSVoices(): List<TTSVoice> =
        try {
            val process = ProcessBuilder("say", "-v", "?").start()
            val output = process.inputStream.bufferedReader().readText()
            process.waitFor()

            // Parse voice list from 'say -v ?' output
            val voices = mutableListOf<TTSVoice>()
            output.lines().forEach { line ->
                if (line.trim().isNotEmpty()) {
                    // Format: "VoiceName    language    # description"
                    val parts = line.trim().split("\\s+".toRegex())
                    if (parts.isNotEmpty()) {
                        val voiceName = parts[0]
                        val language = if (parts.size > 1) parts[1] else "en-US"
                        val gender = guessGenderFromName(voiceName)

                        voices.add(
                            TTSVoice(
                                id = voiceName.lowercase(),
                                name = voiceName,
                                language = language,
                                gender = gender,
                            ),
                        )
                    }
                }
            }

            if (voices.isEmpty()) MACOS_VOICES else voices
        } catch (e: Exception) {
            logger.warn("Failed to detect macOS voices, using defaults")
            MACOS_VOICES
        }

    private fun guessGenderFromName(name: String): TTSGender {
        val femaleName = listOf("samantha", "victoria", "allison", "susan", "zira", "hazel")
        val maleName = listOf("alex", "daniel", "david", "tom", "fred")

        return when {
            femaleName.any { name.lowercase().contains(it) } -> TTSGender.FEMALE
            maleName.any { name.lowercase().contains(it) } -> TTSGender.MALE
            else -> TTSGender.NEUTRAL
        }
    }

    private fun checkCommandAvailable(command: String): Boolean =
        try {
            val process = ProcessBuilder("which", command).start()
            process.waitFor() == 0
        } catch (e: Exception) {
            false
        }

    // MARK: - Platform-Specific Synthesis

    @Suppress("UNUSED_PARAMETER")
    private suspend fun synthesizeWithMacOSSay(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float,
    ): ByteArray =
        withContext(Dispatchers.IO) {
            try {
                val outputFile = createTempFile("tts_output", ".wav")

                // Build 'say' command with parameters
                val command =
                    buildList {
                        add("say")
                        add("-v")
                        add(voice.name)
                        add("-r")
                        add((rate * 200).toInt().toString()) // say uses words per minute
                        add("-o")
                        add(outputFile.absolutePath)
                        add(text)
                    }

                logger.debug("Executing: ${command.joinToString(" ")}")

                val process = ProcessBuilder(command).start()
                val exitCode = process.waitFor()

                if (exitCode == 0 && outputFile.exists() && outputFile.length() > 0) {
                    val audioData = outputFile.readBytes()
                    outputFile.delete()
                    audioData
                } else {
                    logger.warn("macOS say command failed with exit code: $exitCode")
                    generateSilentAudio(text.length)
                }
            } catch (e: Exception) {
                logger.error("Error in macOS TTS synthesis", e)
                generateSilentAudio(text.length)
            }
        }

    @Suppress("UNUSED_PARAMETER")
    private suspend fun synthesizeWithWindowsSAPI(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float,
    ): ByteArray {
        // For now, return silent audio as Windows SAPI integration requires COM interop
        // In a full implementation, you would use JNI or COM4J to access Windows SAPI
        logger.warn("Windows SAPI synthesis not implemented, returning silent audio")
        return generateSilentAudio(text.length)
    }

    @Suppress("UNUSED_PARAMETER")
    private suspend fun synthesizeWithLinuxTTS(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float,
    ): ByteArray =
        withContext(Dispatchers.IO) {
            try {
                when {
                    voice.id.startsWith("espeak") -> synthesizeWithEspeak(text, rate, pitch)
                    voice.id.startsWith("festival") -> synthesizeWithFestival(text)
                    else -> generateSilentAudio(text.length)
                }
            } catch (e: Exception) {
                logger.error("Error in Linux TTS synthesis", e)
                generateSilentAudio(text.length)
            }
        }

    private fun synthesizeWithEspeak(
        text: String,
        rate: Float,
        pitch: Float,
    ): ByteArray =
        try {
            val outputFile = createTempFile("espeak_output", ".wav")

            val command =
                listOf(
                    "espeak",
                    "-s",
                    (rate * 175).toInt().toString(), // Speed in words per minute
                    "-p",
                    (pitch * 50).toInt().toString(), // Pitch 0-99
                    "-w",
                    outputFile.absolutePath,
                    text,
                )

            val process = ProcessBuilder(command).start()
            val exitCode = process.waitFor()

            if (exitCode == 0 && outputFile.exists() && outputFile.length() > 0) {
                val audioData = outputFile.readBytes()
                outputFile.delete()
                audioData
            } else {
                generateSilentAudio(text.length)
            }
        } catch (e: Exception) {
            logger.error("Error with espeak synthesis", e)
            generateSilentAudio(text.length)
        }

    private fun synthesizeWithFestival(text: String): ByteArray =
        try {
            val outputFile = createTempFile("festival_output", ".wav")

            // Create festival script
            val scriptFile = createTempFile("festival_script", ".scm")
            scriptFile.writeText(
                """
                (voice_kal_diphone)
                (utt.save.wave (SayText "$text") "${outputFile.absolutePath}" 'riff)
                """.trimIndent(),
            )

            val command = listOf("festival", "-b", scriptFile.absolutePath)
            val process = ProcessBuilder(command).start()
            val exitCode = process.waitFor()

            scriptFile.delete()

            if (exitCode == 0 && outputFile.exists() && outputFile.length() > 0) {
                val audioData = outputFile.readBytes()
                outputFile.delete()
                audioData
            } else {
                generateSilentAudio(text.length)
            }
        } catch (e: Exception) {
            logger.error("Error with Festival synthesis", e)
            generateSilentAudio(text.length)
        }

    // MARK: - Utility Methods

    /**
     * Generate silent audio as fallback
     */
    private fun generateSilentAudio(textLength: Int): ByteArray {
        // Estimate duration based on text length (rough approximation)
        val estimatedDurationSeconds = (textLength / 15.0).coerceAtLeast(0.5) // ~15 chars per second
        val sampleRate = 16000
        val bytesPerSample = 2 // 16-bit
        val totalBytes = (estimatedDurationSeconds * sampleRate * bytesPerSample).toInt()

        // Generate some very quiet noise instead of pure silence to make it more realistic
        val audioData = ByteArray(totalBytes)
        val random = Random(System.currentTimeMillis())

        for (i in audioData.indices step 2) {
            val quietNoise = (random.nextDouble(-50.0, 50.0)).toInt().coerceIn(-128, 127)
            audioData[i] = (quietNoise and 0xFF).toByte()
            audioData[i + 1] = ((quietNoise shr 8) and 0xFF).toByte()
        }

        logger.debug("Generated ${audioData.size} bytes of silent audio for text length $textLength")
        return audioData
    }

    /**
     * Create temporary file with automatic cleanup
     */
    private fun createTempFile(
        prefix: String,
        suffix: String,
    ): java.io.File =
        kotlin.io.path.createTempFile(prefix, suffix).toFile().apply {
            deleteOnExit()
        }
}

/**
 * JVM TTS Service Provider for integration with ModuleRegistry
 */
class JvmTTSServiceProvider : com.runanywhere.sdk.core.TTSServiceProvider {
    override suspend fun synthesize(
        text: String,
        options: TTSOptions,
    ): ByteArray {
        val service = JvmTTSService()
        service.initialize()
        return service.synthesize(text = text, options = options)
    }

    override fun synthesizeStream(
        text: String,
        options: TTSOptions,
    ): Flow<ByteArray> {
        val service = JvmTTSService()
        return flow {
            service.initialize()
            service.synthesizeStream(text = text, options = options).collect { chunk ->
                emit(chunk)
            }
        }
    }

    override fun canHandle(modelId: String): Boolean {
        // JVM TTS can handle system TTS requests
        return modelId.startsWith("system") || modelId == "default"
    }

    override val name: String = "JvmTTSProvider"

    override val framework: com.runanywhere.sdk.models.enums.InferenceFramework =
        com.runanywhere.sdk.models.enums.InferenceFramework.SYSTEM_TTS
}
