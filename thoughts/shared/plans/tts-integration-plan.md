# Text-to-Speech (TTS) Integration Plan for RunAnywhere KMP SDK

## Executive Summary

This document outlines the comprehensive implementation plan for integrating Text-to-Speech (TTS) functionality into the RunAnywhere Kotlin Multiplatform SDK for JVM and Android platforms. The implementation follows the existing modular architecture pattern and service provider approach established in the SDK.

## Current State Analysis

### Existing TTS Infrastructure
- **TTSComponent**: Basic structure exists in `commonMain` with placeholder implementations
- **TTSService Interface**: Defined with synthesize, synthesizeStream, and voice management methods
- **TTSServiceProvider**: Interface exists in ModuleRegistry for plugin-based architecture
- **Data Models**: TTSOptions, TTSVoice, TTSGender, TTSStyle, TTSOutputFormat defined
- **Integration Pattern**: Uses BaseComponent pattern with provider registry system

### Architecture Alignment
The existing TTS structure follows the modular architecture described in MODULAR-ARCHITECTURE.md:
- Service provider pattern for platform-specific implementations
- ModuleRegistry integration for optional dependencies
- Clean separation between common interfaces and platform implementations
- Component lifecycle management through BaseComponent

## Implementation Plan

## Phase 1: Android TTS Implementation (Week 1-2)

### 1.1 Android TTS Service Implementation

**File: `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/components/tts/AndroidTTSService.kt`**

```kotlin
class AndroidTTSService(
    private val context: Context,
    private val configuration: TTSConfiguration
) : TTSService {

    private var textToSpeech: TextToSpeech? = null
    private var isInitialized = false
    private val initializationLatch = CountDownLatch(1)
    private var availableVoices: List<TTSVoice> = emptyList()

    override suspend fun initialize() {
        withContext(Dispatchers.Main) {
            textToSpeech = TextToSpeech(context) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    setupTTSEngine()
                    loadAvailableVoices()
                    isInitialized = true
                } else {
                    throw SDKError.initializationFailed("Android TTS initialization failed: $status")
                }
                initializationLatch.countDown()
            }
        }

        // Wait for initialization to complete
        withContext(Dispatchers.IO) {
            initializationLatch.await(10, TimeUnit.SECONDS)
        }

        if (!isInitialized) {
            throw SDKError.initializationFailed("TTS initialization timeout")
        }
    }

    private fun setupTTSEngine() {
        textToSpeech?.apply {
            language = Locale.forLanguageTag(configuration.defaultVoice.language)
            setPitch(configuration.defaultPitch)
            setSpeechRate(configuration.defaultRate)
        }
    }

    private fun loadAvailableVoices() {
        textToSpeech?.voices?.let { androidVoices ->
            availableVoices = androidVoices.map { voice ->
                TTSVoice(
                    id = voice.name,
                    name = voice.name,
                    language = voice.locale.toLanguageTag(),
                    gender = mapAndroidGenderToTTSGender(voice.features),
                    style = TTSStyle.NEUTRAL
                )
            }
        }
    }

    override suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray = withContext(Dispatchers.Main) {

        ensureInitialized()

        // Configure TTS parameters
        textToSpeech?.apply {
            setVoice(findAndroidVoice(voice))
            setPitch(pitch)
            setSpeechRate(rate)
        }

        // Create audio file for synthesis
        val audioFile = createTempAudioFile()
        val utteranceId = "synthesis_${System.currentTimeMillis()}"
        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        }

        val synthesisResult = suspendCancellableCoroutine<Int> { continuation ->
            textToSpeech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String) {}

                override fun onDone(utteranceId: String) {
                    continuation.resume(TextToSpeech.SUCCESS)
                }

                override fun onError(utteranceId: String) {
                    continuation.resume(TextToSpeech.ERROR)
                }
            })

            val result = textToSpeech?.synthesizeToFile(text, params, audioFile, utteranceId)
            if (result != TextToSpeech.SUCCESS) {
                continuation.resume(result ?: TextToSpeech.ERROR)
            }
        }

        if (synthesisResult != TextToSpeech.SUCCESS) {
            throw SDKError.synthesisError("TTS synthesis failed: $synthesisResult")
        }

        // Read synthesized audio file
        audioFile.readBytes().also {
            audioFile.delete()
        }
    }

    override fun synthesizeStream(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): Flow<ByteArray> = flow {
        // Android TTS doesn't support native streaming, so we chunk the text
        val chunks = chunkText(text, maxChunkSize = 4000) // Android TTS limit

        for (chunk in chunks) {
            val audioData = synthesize(chunk, voice, rate, pitch, volume)
            emit(audioData)
        }
    }

    override fun getAvailableVoices(): List<TTSVoice> = availableVoices

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Android TTS uses system-installed voices
        // This could be extended to support downloadable voice data
    }

    override fun cancelCurrent() {
        textToSpeech?.stop()
    }

    private fun ensureInitialized() {
        if (!isInitialized) {
            throw SDKError.notInitialized("Android TTS service not initialized")
        }
    }

    private fun findAndroidVoice(ttsVoice: TTSVoice): Voice? {
        return textToSpeech?.voices?.find { voice ->
            voice.locale.toLanguageTag() == ttsVoice.language &&
            voice.name.contains(ttsVoice.name, ignoreCase = true)
        }
    }

    private fun mapAndroidGenderToTTSGender(features: Set<String>): TTSGender {
        return when {
            features.contains(Voice.FEATURE_NOT_INSTALLED) -> TTSGender.NEUTRAL
            features.contains("male") -> TTSGender.MALE
            features.contains("female") -> TTSGender.FEMALE
            else -> TTSGender.NEUTRAL
        }
    }

    private fun chunkText(text: String, maxChunkSize: Int): List<String> {
        if (text.length <= maxChunkSize) return listOf(text)

        val sentences = text.split(Regex("[.!?]+\\s*"))
        val chunks = mutableListOf<String>()
        var currentChunk = ""

        for (sentence in sentences) {
            if (currentChunk.length + sentence.length <= maxChunkSize) {
                currentChunk += "$sentence. "
            } else {
                if (currentChunk.isNotEmpty()) {
                    chunks.add(currentChunk.trim())
                    currentChunk = "$sentence. "
                } else {
                    // Handle very long sentences by force-chunking
                    chunks.addAll(sentence.chunked(maxChunkSize))
                }
            }
        }

        if (currentChunk.isNotEmpty()) {
            chunks.add(currentChunk.trim())
        }

        return chunks
    }

    private fun createTempAudioFile(): File {
        return File.createTempFile("tts_synthesis", ".wav", context.cacheDir)
    }

    fun cleanup() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        isInitialized = false
    }
}
```

### 1.2 Android TTS Service Provider

**File: `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/components/tts/AndroidTTSServiceProvider.kt`**

```kotlin
class AndroidTTSServiceProvider(
    private val context: Context
) : TTSServiceProvider {

    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        val service = createService()
        return service.synthesize(
            text = text,
            voice = options.voice,
            rate = options.rate,
            pitch = options.pitch,
            volume = options.volume
        )
    }

    override fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray> {
        val service = createService()
        return service.synthesizeStream(
            text = text,
            voice = options.voice,
            rate = options.rate,
            pitch = options.pitch,
            volume = options.volume
        )
    }

    override fun canHandle(modelId: String): Boolean {
        return modelId.startsWith("android-tts") || modelId == "system-tts"
    }

    override val name: String = "Android TTS"

    private fun createService(): AndroidTTSService {
        return AndroidTTSService(context, TTSConfiguration())
    }
}
```

### 1.3 SSML Support for Android

**File: `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/components/tts/AndroidSSMLProcessor.kt`**

```kotlin
class AndroidSSMLProcessor {

    fun processSSML(ssml: String): String {
        // Android TTS has limited SSML support
        return ssml
            .replace(Regex("<speak[^>]*>"), "")
            .replace("</speak>", "")
            .replace(Regex("<break\\s+time=[\"']([^\"']+)[\"']\\s*/>")) { matchResult ->
                // Convert SSML breaks to pauses
                val timeValue = matchResult.groupValues[1]
                val seconds = parseTimeToSeconds(timeValue)
                " ... " // Simple pause representation
            }
            .replace(Regex("<prosody[^>]*rate=[\"']([^\"']+)[\"'][^>]*>(.*?)</prosody>", RegexOption.DOT_MATCHES_ALL)) { matchResult ->
                // Extract text from prosody tags - rate will be handled at TTS level
                matchResult.groupValues[2]
            }
            .replace(Regex("<[^>]*>"), "") // Remove any remaining tags
            .trim()
    }

    private fun parseTimeToSeconds(timeValue: String): Float {
        return when {
            timeValue.endsWith("s") -> timeValue.dropLast(1).toFloatOrNull() ?: 1.0f
            timeValue.endsWith("ms") -> (timeValue.dropLast(2).toFloatOrNull() ?: 1000f) / 1000f
            else -> timeValue.toFloatOrNull() ?: 1.0f
        }
    }

    fun extractProsodyAttributes(ssml: String): TTSOptions {
        var rate = 1.0f
        var pitch = 1.0f
        var volume = 1.0f

        val prosodyPattern = Regex("<prosody[^>]*>")
        prosodyPattern.findAll(ssml).forEach { match ->
            val prosodyTag = match.value

            // Extract rate
            Regex("rate=[\"']([^\"']+)[\"']").find(prosodyTag)?.let { rateMatch ->
                rate = parseProsodyValue(rateMatch.groupValues[1])
            }

            // Extract pitch
            Regex("pitch=[\"']([^\"']+)[\"']").find(prosodyTag)?.let { pitchMatch ->
                pitch = parseProsodyValue(pitchMatch.groupValues[1])
            }

            // Extract volume
            Regex("volume=[\"']([^\"']+)[\"']").find(prosodyTag)?.let { volumeMatch ->
                volume = parseProsodyValue(volumeMatch.groupValues[1])
            }
        }

        return TTSOptions(rate = rate, pitch = pitch, volume = volume)
    }

    private fun parseProsodyValue(value: String): Float {
        return when {
            value.endsWith("%") -> {
                val percentage = value.dropLast(1).toFloatOrNull() ?: 100f
                percentage / 100f
            }
            value == "slow" -> 0.7f
            value == "fast" -> 1.3f
            value == "x-slow" -> 0.5f
            value == "x-fast" -> 1.5f
            value == "medium" -> 1.0f
            value == "low" -> 0.8f
            value == "high" -> 1.2f
            value == "x-low" -> 0.6f
            value == "x-high" -> 1.4f
            else -> value.toFloatOrNull() ?: 1.0f
        }
    }
}
```

## Phase 2: JVM TTS Implementation (Week 3-4)

### 2.1 JVM TTS Service with MaryTTS

**File: `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/components/tts/JvmTTSService.kt`**

```kotlin
class JvmTTSService(
    private val configuration: TTSConfiguration
) : TTSService {

    private var maryTTS: MaryInterface? = null
    private var isInitialized = false
    private var availableVoices: List<TTSVoice> = emptyList()

    companion object {
        private const val DEFAULT_AUDIO_FORMAT = "WAVE"
        private const val SAMPLE_RATE = 16000
    }

    override suspend fun initialize() = withContext(Dispatchers.IO) {
        try {
            // Initialize MaryTTS
            maryTTS = Mary.createMaryInterface().apply {
                // Set default locale if available
                val locale = Locale.forLanguageTag(configuration.defaultVoice.language)
                if (availableLocales.contains(locale)) {
                    this.locale = locale
                }

                // Set audio format
                audioType = DEFAULT_AUDIO_FORMAT
            }

            loadAvailableVoices()
            isInitialized = true

        } catch (e: Exception) {
            throw SDKError.initializationFailed("MaryTTS initialization failed", e)
        }
    }

    private fun loadAvailableVoices() {
        maryTTS?.let { mary ->
            availableVoices = mary.availableVoices.map { voice ->
                TTSVoice(
                    id = voice.name(),
                    name = voice.name(),
                    language = voice.locale.toLanguageTag(),
                    gender = mapMaryGenderToTTSGender(voice.gender()),
                    style = TTSStyle.NEUTRAL
                )
            }
        }
    }

    override suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray = withContext(Dispatchers.IO) {

        ensureInitialized()

        try {
            // Configure voice if available
            maryTTS?.let { mary ->
                val maryVoice = findMaryVoice(voice)
                if (maryVoice != null) {
                    mary.voice = maryVoice
                }
            }

            // Apply prosody modifications via SSML if needed
            val processedText = if (rate != 1.0f || pitch != 1.0f) {
                wrapWithProsody(text, rate, pitch, volume)
            } else {
                text
            }

            // Synthesize audio
            maryTTS?.generateAudio(processedText)
                ?: throw SDKError.synthesisError("MaryTTS instance not available")

        } catch (e: Exception) {
            throw SDKError.synthesisError("TTS synthesis failed", e)
        }
    }

    override fun synthesizeStream(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): Flow<ByteArray> = flow {
        // MaryTTS doesn't support native streaming, so we implement chunked synthesis
        val sentences = splitIntoSentences(text)

        for (sentence in sentences) {
            if (sentence.isNotBlank()) {
                val audioChunk = synthesize(sentence, voice, rate, pitch, volume)
                emit(audioChunk)
            }
        }
    }

    override fun getAvailableVoices(): List<TTSVoice> = availableVoices

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // MaryTTS uses installed voice models
        // This could be extended to support downloading additional voice packages
        when (modelInfo.format) {
            ModelFormat.MARYTTS -> {
                // Load MaryTTS-specific voice model
                loadMaryTTSVoice(modelInfo)
            }
            else -> {
                throw SDKError.unsupportedFormat("Unsupported model format: ${modelInfo.format}")
            }
        }
    }

    override fun cancelCurrent() {
        // MaryTTS doesn't support cancellation of ongoing synthesis
        // This would require implementing a more complex streaming architecture
    }

    private fun ensureInitialized() {
        if (!isInitialized) {
            throw SDKError.notInitialized("JVM TTS service not initialized")
        }
    }

    private fun findMaryVoice(ttsVoice: TTSVoice): Voice? {
        return maryTTS?.availableVoices?.find { voice ->
            voice.name() == ttsVoice.id ||
            voice.locale.toLanguageTag() == ttsVoice.language
        }
    }

    private fun mapMaryGenderToTTSGender(gender: Gender): TTSGender {
        return when (gender) {
            Gender.MALE -> TTSGender.MALE
            Gender.FEMALE -> TTSGender.FEMALE
            else -> TTSGender.NEUTRAL
        }
    }

    private fun wrapWithProsody(text: String, rate: Float, pitch: Float, volume: Float): String {
        return buildString {
            append("<prosody")
            if (rate != 1.0f) append(" rate=\"${rate * 100}%\"")
            if (pitch != 1.0f) append(" pitch=\"${if (pitch > 1.0f) "+" else ""}${(pitch - 1.0f) * 50}%\"")
            if (volume != 1.0f) append(" volume=\"${volume * 100}%\"")
            append(">")
            append(text)
            append("</prosody>")
        }
    }

    private fun splitIntoSentences(text: String): List<String> {
        return text.split(Regex("[.!?]+\\s*")).filter { it.isNotBlank() }
    }

    private suspend fun loadMaryTTSVoice(modelInfo: ModelInfo) = withContext(Dispatchers.IO) {
        // Implementation for loading additional MaryTTS voices
        // This would involve downloading and installing voice packages
        try {
            // Voice loading logic here
            loadAvailableVoices() // Refresh available voices
        } catch (e: Exception) {
            throw SDKError.modelLoadingFailed("Failed to load MaryTTS voice: ${modelInfo.id}", e)
        }
    }
}
```

### 2.2 JVM Fallback TTS Service (System TTS)

**File: `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/components/tts/SystemTTSService.kt`**

```kotlin
class SystemTTSService(
    private val configuration: TTSConfiguration
) : TTSService {

    private var isInitialized = false
    private val operatingSystem = System.getProperty("os.name").lowercase()

    override suspend fun initialize() = withContext(Dispatchers.IO) {
        isInitialized = when {
            operatingSystem.contains("windows") -> initializeWindowsTTS()
            operatingSystem.contains("mac") -> initializeMacOSTTS()
            operatingSystem.contains("linux") -> initializeLinuxTTS()
            else -> false
        }

        if (!isInitialized) {
            throw SDKError.initializationFailed("System TTS not available on $operatingSystem")
        }
    }

    override suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray = withContext(Dispatchers.IO) {

        ensureInitialized()

        when {
            operatingSystem.contains("windows") -> synthesizeWindows(text, voice, rate, pitch, volume)
            operatingSystem.contains("mac") -> synthesizeMacOS(text, voice, rate, pitch, volume)
            operatingSystem.contains("linux") -> synthesizeLinux(text, voice, rate, pitch, volume)
            else -> throw SDKError.synthesisError("Unsupported operating system: $operatingSystem")
        }
    }

    override fun synthesizeStream(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): Flow<ByteArray> = flow {
        // System TTS usually doesn't support streaming, so we chunk
        val chunks = chunkText(text)
        for (chunk in chunks) {
            val audioData = synthesize(chunk, voice, rate, pitch, volume)
            emit(audioData)
        }
    }

    override fun getAvailableVoices(): List<TTSVoice> {
        return when {
            operatingSystem.contains("windows") -> getWindowsVoices()
            operatingSystem.contains("mac") -> getMacOSVoices()
            operatingSystem.contains("linux") -> getLinuxVoices()
            else -> listOf(TTSVoice.DEFAULT)
        }
    }

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // System TTS doesn't support model loading
    }

    override fun cancelCurrent() {
        // Implementation depends on platform
    }

    private fun initializeWindowsTTS(): Boolean {
        return try {
            // Check if Windows Speech API is available
            val process = ProcessBuilder("powershell", "-Command", "Add-Type -AssemblyName System.Speech").start()
            process.waitFor() == 0
        } catch (e: Exception) {
            false
        }
    }

    private fun initializeMacOSTTS(): Boolean {
        return try {
            // Check if 'say' command is available
            val process = ProcessBuilder("which", "say").start()
            process.waitFor() == 0
        } catch (e: Exception) {
            false
        }
    }

    private fun initializeLinuxTTS(): Boolean {
        return try {
            // Check if espeak or festival is available
            val espeakProcess = ProcessBuilder("which", "espeak").start()
            val festivalProcess = ProcessBuilder("which", "festival").start()
            espeakProcess.waitFor() == 0 || festivalProcess.waitFor() == 0
        } catch (e: Exception) {
            false
        }
    }

    private suspend fun synthesizeWindows(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray = withContext(Dispatchers.IO) {

        val tempFile = File.createTempFile("tts_windows", ".wav")
        try {
            val rateParam = (rate * 100).toInt().coerceIn(0, 200)
            val volumeParam = (volume * 100).toInt().coerceIn(0, 100)

            val script = """
                Add-Type -AssemblyName System.Speech
                ${"$"}synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
                ${"$"}synth.Rate = $rateParam
                ${"$"}synth.Volume = $volumeParam
                ${"$"}synth.SetOutputToWaveFile('${tempFile.absolutePath}')
                ${"$"}synth.Speak('$text')
                ${"$"}synth.Dispose()
            """.trimIndent()

            val process = ProcessBuilder(
                "powershell", "-Command", script
            ).start()

            if (process.waitFor() != 0) {
                throw SDKError.synthesisError("Windows TTS synthesis failed")
            }

            tempFile.readBytes()
        } finally {
            tempFile.delete()
        }
    }

    private suspend fun synthesizeMacOS(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray = withContext(Dispatchers.IO) {

        val tempFile = File.createTempFile("tts_macos", ".aiff")
        try {
            val rateParam = (rate * 200).toInt().coerceIn(50, 500)

            val process = ProcessBuilder(
                "say",
                "-o", tempFile.absolutePath,
                "-r", rateParam.toString(),
                text
            ).start()

            if (process.waitFor() != 0) {
                throw SDKError.synthesisError("macOS TTS synthesis failed")
            }

            tempFile.readBytes()
        } finally {
            tempFile.delete()
        }
    }

    private suspend fun synthesizeLinux(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray = withContext(Dispatchers.IO) {

        val tempFile = File.createTempFile("tts_linux", ".wav")
        try {
            // Try espeak first
            val espeakAvailable = ProcessBuilder("which", "espeak").start().waitFor() == 0

            if (espeakAvailable) {
                val rateParam = (rate * 175).toInt().coerceIn(80, 450)
                val pitchParam = (pitch * 50).toInt().coerceIn(0, 100)

                val process = ProcessBuilder(
                    "espeak",
                    "-w", tempFile.absolutePath,
                    "-s", rateParam.toString(),
                    "-p", pitchParam.toString(),
                    text
                ).start()

                if (process.waitFor() != 0) {
                    throw SDKError.synthesisError("Linux TTS synthesis failed")
                }
            } else {
                throw SDKError.synthesisError("No suitable TTS engine found on Linux")
            }

            tempFile.readBytes()
        } finally {
            tempFile.delete()
        }
    }

    private fun getWindowsVoices(): List<TTSVoice> {
        // Windows SAPI voices would be queried here
        return listOf(TTSVoice.DEFAULT.copy(id = "windows-default", name = "Windows Default"))
    }

    private fun getMacOSVoices(): List<TTSVoice> {
        // macOS voices would be queried via 'say -v ?' command
        return listOf(TTSVoice.DEFAULT.copy(id = "macos-default", name = "macOS Default"))
    }

    private fun getLinuxVoices(): List<TTSVoice> {
        // Linux voices would be queried from espeak/festival
        return listOf(TTSVoice.DEFAULT.copy(id = "linux-default", name = "Linux Default"))
    }

    private fun chunkText(text: String, maxChunkSize: Int = 500): List<String> {
        if (text.length <= maxChunkSize) return listOf(text)

        return text.split(Regex("[.!?]+\\s*"))
            .filter { it.isNotBlank() }
            .fold(mutableListOf<String>()) { chunks, sentence ->
                if (chunks.isEmpty() || chunks.last().length + sentence.length > maxChunkSize) {
                    chunks.add(sentence)
                } else {
                    chunks[chunks.lastIndex] = "${chunks.last()}. $sentence"
                }
                chunks
            }
    }

    private fun ensureInitialized() {
        if (!isInitialized) {
            throw SDKError.notInitialized("System TTS service not initialized")
        }
    }
}
```

### 2.3 JVM TTS Service Provider

**File: `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/components/tts/JvmTTSServiceProvider.kt`**

```kotlin
class JvmTTSServiceProvider : TTSServiceProvider {

    private var preferredEngine: TTSEngine = TTSEngine.AUTO

    enum class TTSEngine {
        AUTO,
        MARYTTS,
        SYSTEM
    }

    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        val service = createOptimalService()
        return service.synthesize(
            text = text,
            voice = options.voice,
            rate = options.rate,
            pitch = options.pitch,
            volume = options.volume
        )
    }

    override fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray> {
        val service = createOptimalService()
        return service.synthesizeStream(
            text = text,
            voice = options.voice,
            rate = options.rate,
            pitch = options.pitch,
            volume = options.volume
        )
    }

    override fun canHandle(modelId: String): Boolean {
        return modelId.startsWith("jvm-") ||
               modelId.startsWith("marytts-") ||
               modelId.startsWith("system-") ||
               modelId == "desktop-tts"
    }

    override val name: String = "JVM TTS"

    private fun createOptimalService(): TTSService {
        return when (preferredEngine) {
            TTSEngine.AUTO -> createAutoDetectedService()
            TTSEngine.MARYTTS -> createMaryTTSService()
            TTSEngine.SYSTEM -> createSystemService()
        }
    }

    private fun createAutoDetectedService(): TTSService {
        return try {
            // Try MaryTTS first for better quality
            createMaryTTSService()
        } catch (e: Exception) {
            // Fall back to system TTS
            createSystemService()
        }
    }

    private fun createMaryTTSService(): TTSService {
        return JvmTTSService(TTSConfiguration())
    }

    private fun createSystemService(): TTSService {
        return SystemTTSService(TTSConfiguration())
    }

    fun setPreferredEngine(engine: TTSEngine) {
        preferredEngine = engine
    }
}
```

## Phase 3: Enhanced SSML Support (Week 5)

### 3.1 Advanced SSML Processor

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/tts/SSMLProcessor.kt`**

```kotlin
class SSMLProcessor {

    fun processSSML(ssml: String, platform: TTSPlatform): ProcessedSSML {
        val document = parseSSMLDocument(ssml)
        return when (platform) {
            TTSPlatform.ANDROID -> processForAndroid(document)
            TTSPlatform.MARYTTS -> processForMaryTTS(document)
            TTSPlatform.SYSTEM -> processForSystem(document)
        }
    }

    private fun parseSSMLDocument(ssml: String): SSMLDocument {
        // Parse SSML into structured format
        return SSMLDocument(
            elements = parseElements(ssml),
            globalAttributes = extractGlobalAttributes(ssml)
        )
    }

    private fun processForAndroid(document: SSMLDocument): ProcessedSSML {
        return ProcessedSSML(
            text = document.elements.joinToString(" ") { element ->
                when (element) {
                    is SSMLText -> element.content
                    is SSMLBreak -> " ... " // Android limitation
                    is SSMLProsody -> element.content
                    else -> element.toString()
                }
            },
            ttsOptions = extractTTSOptionsFromDocument(document)
        )
    }

    private fun processForMaryTTS(document: SSMLDocument): ProcessedSSML {
        // MaryTTS supports more complete SSML
        return ProcessedSSML(
            text = reconstructSSMLForMaryTTS(document),
            ttsOptions = TTSOptions() // MaryTTS handles prosody natively
        )
    }

    private fun processForSystem(document: SSMLDocument): ProcessedSSML {
        // Most system TTS engines have limited SSML support
        return ProcessedSSML(
            text = stripSSMLTags(document),
            ttsOptions = extractTTSOptionsFromDocument(document)
        )
    }

    private fun parseElements(ssml: String): List<SSMLElement> {
        val elements = mutableListOf<SSMLElement>()
        var currentPos = 0

        val tagPattern = Regex("<([^>]+)>")
        val matches = tagPattern.findAll(ssml)

        for (match in matches) {
            // Add text before tag
            if (match.range.first > currentPos) {
                val textContent = ssml.substring(currentPos, match.range.first)
                if (textContent.isNotBlank()) {
                    elements.add(SSMLText(textContent.trim()))
                }
            }

            // Parse tag
            val tagContent = match.groupValues[1]
            elements.add(parseSSMLTag(tagContent))

            currentPos = match.range.last + 1
        }

        // Add remaining text
        if (currentPos < ssml.length) {
            val textContent = ssml.substring(currentPos)
            if (textContent.isNotBlank()) {
                elements.add(SSMLText(textContent.trim()))
            }
        }

        return elements
    }

    private fun parseSSMLTag(tagContent: String): SSMLElement {
        val parts = tagContent.split("\\s+".toRegex())
        val tagName = parts[0].lowercase()
        val attributes = parseAttributes(parts.drop(1).joinToString(" "))

        return when (tagName) {
            "break" -> SSMLBreak(
                time = attributes["time"] ?: "1s",
                strength = attributes["strength"] ?: "medium"
            )
            "prosody" -> SSMLProsody(
                rate = attributes["rate"],
                pitch = attributes["pitch"],
                volume = attributes["volume"],
                content = "" // Will be filled by content parser
            )
            "voice" -> SSMLVoice(
                name = attributes["name"],
                gender = attributes["gender"],
                age = attributes["age"],
                content = ""
            )
            "emphasis" -> SSMLEmphasis(
                level = attributes["level"] ?: "moderate",
                content = ""
            )
            "say-as" -> SSMLSayAs(
                interpretAs = attributes["interpret-as"] ?: "text",
                format = attributes["format"],
                detail = attributes["detail"],
                content = ""
            )
            else -> SSMLText(tagContent)
        }
    }

    private fun parseAttributes(attributeString: String): Map<String, String> {
        val attributes = mutableMapOf<String, String>()
        val attributePattern = Regex("""(\w+)=["']([^"']+)["']""")

        attributePattern.findAll(attributeString).forEach { match ->
            attributes[match.groupValues[1]] = match.groupValues[2]
        }

        return attributes
    }

    private fun extractGlobalAttributes(ssml: String): Map<String, String> {
        val speakTagPattern = Regex("<speak[^>]*>")
        val match = speakTagPattern.find(ssml)
        return if (match != null) {
            parseAttributes(match.value)
        } else {
            emptyMap()
        }
    }

    private fun extractTTSOptionsFromDocument(document: SSMLDocument): TTSOptions {
        var rate = 1.0f
        var pitch = 1.0f
        var volume = 1.0f
        var voice: TTSVoice? = null

        document.elements.forEach { element ->
            when (element) {
                is SSMLProsody -> {
                    element.rate?.let { rate = parseProsodyValue(it) }
                    element.pitch?.let { pitch = parseProsodyValue(it) }
                    element.volume?.let { volume = parseProsodyValue(it) }
                }
                is SSMLVoice -> {
                    element.name?.let { name ->
                        voice = TTSVoice(
                            id = name,
                            name = name,
                            language = "en-US", // Default, could be extracted from global attributes
                            gender = parseGender(element.gender)
                        )
                    }
                }
            }
        }

        return TTSOptions(
            voice = voice ?: TTSVoice.DEFAULT,
            rate = rate,
            pitch = pitch,
            volume = volume
        )
    }

    private fun parseProsodyValue(value: String): Float {
        return when {
            value.endsWith("%") -> {
                val percentage = value.dropLast(1).toFloatOrNull() ?: 100f
                percentage / 100f
            }
            value == "x-slow" -> 0.5f
            value == "slow" -> 0.7f
            value == "medium" -> 1.0f
            value == "fast" -> 1.3f
            value == "x-fast" -> 1.5f
            value == "x-low" -> 0.6f
            value == "low" -> 0.8f
            value == "high" -> 1.2f
            value == "x-high" -> 1.4f
            else -> value.toFloatOrNull() ?: 1.0f
        }
    }

    private fun parseGender(gender: String?): TTSGender {
        return when (gender?.lowercase()) {
            "male" -> TTSGender.MALE
            "female" -> TTSGender.FEMALE
            else -> TTSGender.NEUTRAL
        }
    }

    private fun reconstructSSMLForMaryTTS(document: SSMLDocument): String {
        // Reconstruct SSML that MaryTTS can understand
        return buildString {
            append("<speak")
            document.globalAttributes.forEach { (key, value) ->
                append(" $key=\"$value\"")
            }
            append(">")

            document.elements.forEach { element ->
                append(element.toSSML())
            }

            append("</speak>")
        }
    }

    private fun stripSSMLTags(document: SSMLDocument): String {
        return document.elements.joinToString(" ") { element ->
            when (element) {
                is SSMLText -> element.content
                is SSMLProsody -> element.content
                is SSMLVoice -> element.content
                is SSMLEmphasis -> element.content
                is SSMLSayAs -> element.content
                is SSMLBreak -> " ... "
                else -> element.toString()
            }
        }.trim()
    }
}

data class ProcessedSSML(
    val text: String,
    val ttsOptions: TTSOptions
)

data class SSMLDocument(
    val elements: List<SSMLElement>,
    val globalAttributes: Map<String, String>
)

sealed class SSMLElement {
    abstract fun toSSML(): String
}

data class SSMLText(val content: String) : SSMLElement() {
    override fun toSSML(): String = content
}

data class SSMLBreak(val time: String, val strength: String) : SSMLElement() {
    override fun toSSML(): String = "<break time=\"$time\" strength=\"$strength\"/>"
}

data class SSMLProsody(
    val rate: String?,
    val pitch: String?,
    val volume: String?,
    val content: String
) : SSMLElement() {
    override fun toSSML(): String {
        val attrs = mutableListOf<String>()
        rate?.let { attrs.add("rate=\"$it\"") }
        pitch?.let { attrs.add("pitch=\"$it\"") }
        volume?.let { attrs.add("volume=\"$it\"") }

        return "<prosody ${attrs.joinToString(" ")}>$content</prosody>"
    }
}

data class SSMLVoice(
    val name: String?,
    val gender: String?,
    val age: String?,
    val content: String
) : SSMLElement() {
    override fun toSSML(): String {
        val attrs = mutableListOf<String>()
        name?.let { attrs.add("name=\"$it\"") }
        gender?.let { attrs.add("gender=\"$it\"") }
        age?.let { attrs.add("age=\"$it\"") }

        return "<voice ${attrs.joinToString(" ")}>$content</voice>"
    }
}

data class SSMLEmphasis(val level: String, val content: String) : SSMLElement() {
    override fun toSSML(): String = "<emphasis level=\"$level\">$content</emphasis>"
}

data class SSMLSayAs(
    val interpretAs: String,
    val format: String?,
    val detail: String?,
    val content: String
) : SSMLElement() {
    override fun toSSML(): String {
        val attrs = mutableListOf("interpret-as=\"$interpretAs\"")
        format?.let { attrs.add("format=\"$it\"") }
        detail?.let { attrs.add("detail=\"$it\"") }

        return "<say-as ${attrs.joinToString(" ")}>$content</say-as>"
    }
}

enum class TTSPlatform {
    ANDROID,
    MARYTTS,
    SYSTEM
}
```

## Phase 4: Audio Format and Streaming Support (Week 6)

### 4.1 Audio Format Converter

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/tts/AudioFormatConverter.kt`**

```kotlin
class AudioFormatConverter {

    fun convertAudioFormat(
        inputData: ByteArray,
        inputFormat: TTSOutputFormat,
        targetFormat: TTSOutputFormat
    ): ByteArray {
        if (inputFormat == targetFormat) return inputData

        return when (targetFormat) {
            TTSOutputFormat.PCM_16KHZ -> convertToPCM16(inputData, inputFormat)
            TTSOutputFormat.PCM_24KHZ -> convertToPCM24(inputData, inputFormat)
            TTSOutputFormat.PCM_48KHZ -> convertToPCM48(inputData, inputFormat)
            TTSOutputFormat.MP3 -> convertToMP3(inputData, inputFormat)
            TTSOutputFormat.OGG_VORBIS -> convertToOgg(inputData, inputFormat)
            TTSOutputFormat.OPUS -> convertToOpus(inputData, inputFormat)
            else -> inputData
        }
    }

    private fun convertToPCM16(data: ByteArray, sourceFormat: TTSOutputFormat): ByteArray {
        return when (sourceFormat.sampleRate) {
            16000 -> data // Already correct sample rate
            else -> resampleAudio(data, sourceFormat.sampleRate, 16000)
        }
    }

    private fun convertToPCM24(data: ByteArray, sourceFormat: TTSOutputFormat): ByteArray {
        return when (sourceFormat.sampleRate) {
            24000 -> data
            else -> resampleAudio(data, sourceFormat.sampleRate, 24000)
        }
    }

    private fun convertToPCM48(data: ByteArray, sourceFormat: TTSOutputFormat): ByteArray {
        return when (sourceFormat.sampleRate) {
            48000 -> data
            else -> resampleAudio(data, sourceFormat.sampleRate, 48000)
        }
    }

    private fun convertToMP3(data: ByteArray, sourceFormat: TTSOutputFormat): ByteArray {
        // This would require a MP3 encoder library
        // For now, return original data - implement with actual encoder
        return data
    }

    private fun convertToOgg(data: ByteArray, sourceFormat: TTSOutputFormat): ByteArray {
        // This would require an OGG Vorbis encoder
        return data
    }

    private fun convertToOpus(data: ByteArray, sourceFormat: TTSOutputFormat): ByteArray {
        // This would require an Opus encoder
        return data
    }

    private fun resampleAudio(data: ByteArray, sourceSampleRate: Int, targetSampleRate: Int): ByteArray {
        if (sourceSampleRate == targetSampleRate) return data

        // Simple linear interpolation resampling
        val ratio = targetSampleRate.toDouble() / sourceSampleRate
        val inputSamples = data.size / 2 // Assuming 16-bit samples
        val outputSamples = (inputSamples * ratio).toInt()
        val output = ByteArray(outputSamples * 2)

        for (i in 0 until outputSamples) {
            val sourceIndex = (i / ratio).toInt()
            val sampleIndex = sourceIndex * 2

            if (sampleIndex + 1 < data.size) {
                // Copy 16-bit sample (little-endian)
                output[i * 2] = data[sampleIndex]
                output[i * 2 + 1] = data[sampleIndex + 1]
            }
        }

        return output
    }

    fun addWaveHeader(pcmData: ByteArray, sampleRate: Int): ByteArray {
        val header = ByteArray(44)
        val totalDataLen = pcmData.size + 36
        val bitRate = 16
        val channels = 1
        val byteRate = sampleRate * channels * bitRate / 8

        // WAV header construction
        header[0] = 'R'.code.toByte()  // RIFF
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()

        // File size
        header[4] = (totalDataLen and 0xff).toByte()
        header[5] = ((totalDataLen shr 8) and 0xff).toByte()
        header[6] = ((totalDataLen shr 16) and 0xff).toByte()
        header[7] = ((totalDataLen shr 24) and 0xff).toByte()

        header[8] = 'W'.code.toByte()  // WAVE
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()

        header[12] = 'f'.code.toByte() // fmt
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()

        header[16] = 16 // fmt chunk size
        header[17] = 0
        header[18] = 0
        header[19] = 0

        header[20] = 1 // PCM format
        header[21] = 0

        header[22] = channels.toByte()
        header[23] = 0

        // Sample rate
        header[24] = (sampleRate and 0xff).toByte()
        header[25] = ((sampleRate shr 8) and 0xff).toByte()
        header[26] = ((sampleRate shr 16) and 0xff).toByte()
        header[27] = ((sampleRate shr 24) and 0xff).toByte()

        // Byte rate
        header[28] = (byteRate and 0xff).toByte()
        header[29] = ((byteRate shr 8) and 0xff).toByte()
        header[30] = ((byteRate shr 16) and 0xff).toByte()
        header[31] = ((byteRate shr 24) and 0xff).toByte()

        header[32] = (channels * bitRate / 8).toByte() // Block align
        header[33] = 0

        header[34] = bitRate.toByte() // Bits per sample
        header[35] = 0

        header[36] = 'd'.code.toByte() // data
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()

        // Data size
        header[40] = (pcmData.size and 0xff).toByte()
        header[41] = ((pcmData.size shr 8) and 0xff).toByte()
        header[42] = ((pcmData.size shr 16) and 0xff).toByte()
        header[43] = ((pcmData.size shr 24) and 0xff).toByte()

        return header + pcmData
    }
}
```

### 4.2 Streaming Audio Buffer

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/tts/StreamingAudioBuffer.kt`**

```kotlin
class StreamingAudioBuffer(
    private val bufferSizeMs: Long = 500,
    private val sampleRate: Int = 16000
) {
    private val bufferSizeBytes = ((bufferSizeMs * sampleRate * 2) / 1000).toInt() // 16-bit samples
    private val audioBuffer = mutableListOf<ByteArray>()
    private val mutex = Mutex()
    private var isComplete = false

    suspend fun addAudioChunk(chunk: ByteArray) {
        mutex.withLock {
            audioBuffer.add(chunk)
        }
    }

    suspend fun markComplete() {
        mutex.withLock {
            isComplete = true
        }
    }

    fun getAudioStream(): Flow<ByteArray> = flow {
        var currentBuffer = ByteArray(0)
        var bufferIndex = 0

        while (true) {
            val availableChunks = mutex.withLock {
                audioBuffer.drop(bufferIndex).toList()
            }

            // Add new chunks to current buffer
            for (chunk in availableChunks) {
                currentBuffer += chunk
                bufferIndex++
            }

            // Emit buffers when we have enough data
            while (currentBuffer.size >= bufferSizeBytes) {
                val bufferToEmit = currentBuffer.take(bufferSizeBytes).toByteArray()
                currentBuffer = currentBuffer.drop(bufferSizeBytes).toByteArray()
                emit(bufferToEmit)
            }

            // Check if we're done
            val complete = mutex.withLock { isComplete }
            if (complete) {
                // Emit remaining buffer if any
                if (currentBuffer.isNotEmpty()) {
                    emit(currentBuffer)
                }
                break
            }

            // Wait a bit before checking for more data
            delay(50)
        }
    }

    suspend fun clear() {
        mutex.withLock {
            audioBuffer.clear()
            isComplete = false
        }
    }
}
```

## Phase 5: Voice Management and Language Support (Week 7)

### 5.1 Voice Manager

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/tts/VoiceManager.kt`**

```kotlin
class VoiceManager(
    private val ttsService: TTSService
) {
    private var cachedVoices: List<TTSVoice>? = null
    private val voiceCache = mutableMapOf<String, TTSVoice>()

    suspend fun getAvailableVoices(): List<TTSVoice> {
        return cachedVoices ?: run {
            val voices = ttsService.getAvailableVoices()
            cachedVoices = voices
            voices.forEach { voice ->
                voiceCache[voice.id] = voice
            }
            voices
        }
    }

    fun getVoiceById(voiceId: String): TTSVoice? {
        return voiceCache[voiceId]
    }

    suspend fun getVoicesByLanguage(languageTag: String): List<TTSVoice> {
        return getAvailableVoices().filter { voice ->
            voice.language == languageTag ||
            voice.language.startsWith(languageTag.split("-")[0])
        }
    }

    suspend fun getVoicesByGender(gender: TTSGender): List<TTSVoice> {
        return getAvailableVoices().filter { it.gender == gender }
    }

    suspend fun getVoicesByStyle(style: TTSStyle): List<TTSVoice> {
        return getAvailableVoices().filter { it.style == style }
    }

    suspend fun getBestVoiceFor(
        language: String? = null,
        gender: TTSGender? = null,
        style: TTSStyle? = null
    ): TTSVoice {
        val availableVoices = getAvailableVoices()

        if (availableVoices.isEmpty()) {
            return TTSVoice.DEFAULT
        }

        // Filter by language
        val languageFiltered = language?.let { lang ->
            availableVoices.filter { voice ->
                voice.language == lang || voice.language.startsWith(lang.split("-")[0])
            }
        } ?: availableVoices

        if (languageFiltered.isEmpty()) {
            return availableVoices.first()
        }

        // Filter by gender
        val genderFiltered = gender?.let { g ->
            languageFiltered.filter { it.gender == g }
        } ?: languageFiltered

        if (genderFiltered.isEmpty()) {
            return languageFiltered.first()
        }

        // Filter by style
        val styleFiltered = style?.let { s ->
            genderFiltered.filter { it.style == s }
        } ?: genderFiltered

        return styleFiltered.firstOrNull() ?: genderFiltered.first()
    }

    fun refreshVoiceCache() {
        cachedVoices = null
        voiceCache.clear()
    }

    suspend fun downloadVoice(voiceId: String, modelInfo: ModelInfo) {
        try {
            ttsService.loadModel(modelInfo)
            refreshVoiceCache() // Refresh cache after downloading new voice
        } catch (e: Exception) {
            throw SDKError.voiceDownloadFailed("Failed to download voice $voiceId", e)
        }
    }

    fun getLanguageSupport(): Map<String, List<TTSVoice>> {
        return cachedVoices?.groupBy { it.language } ?: emptyMap()
    }

    fun getSupportedLanguages(): List<String> {
        return cachedVoices?.map { it.language }?.distinct() ?: emptyList()
    }
}
```

### 5.2 Language Detection and Localization

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/tts/LanguageDetector.kt`**

```kotlin
class LanguageDetector {

    private val languagePatterns = mapOf(
        "en" to listOf(
            Regex("\\b(the|and|is|are|was|were|have|has|had|will|would|could|should)\\b", RegexOption.IGNORE_CASE)
        ),
        "es" to listOf(
            Regex("\\b(el|la|los|las|de|en|y|es|que|se|por|para|con)\\b", RegexOption.IGNORE_CASE)
        ),
        "fr" to listOf(
            Regex("\\b(le|la|les|de|du|des|et|est|que|se|pour|avec|dans)\\b", RegexOption.IGNORE_CASE)
        ),
        "de" to listOf(
            Regex("\\b(der|die|das|und|ist|sind|war|waren|haben|hat|hatte)\\b", RegexOption.IGNORE_CASE)
        ),
        "it" to listOf(
            Regex("\\b(il|la|le|gli|di|in|e|è|che|si|per|con|da)\\b", RegexOption.IGNORE_CASE)
        ),
        "pt" to listOf(
            Regex("\\b(o|a|os|as|de|em|e|é|que|se|por|para|com)\\b", RegexOption.IGNORE_CASE)
        ),
        "ru" to listOf(
            Regex("\\b(и|в|не|на|я|быть|он|с|а|как|что|это|все)\\b", RegexOption.IGNORE_CASE)
        ),
        "zh" to listOf(
            Regex("[\\u4e00-\\u9fff]+") // Chinese characters
        ),
        "ja" to listOf(
            Regex("[\\u3040-\\u309f\\u30a0-\\u30ff\\u4e00-\\u9faf]+") // Hiragana, Katakana, Kanji
        ),
        "ko" to listOf(
            Regex("[\\uac00-\\ud7af]+") // Hangul
        ),
        "ar" to listOf(
            Regex("[\\u0600-\\u06ff]+") // Arabic
        ),
        "hi" to listOf(
            Regex("[\\u0900-\\u097f]+") // Devanagari
        )
    )

    fun detectLanguage(text: String): LanguageDetectionResult {
        val scores = mutableMapOf<String, Double>()
        val words = text.split(Regex("\\s+")).filter { it.isNotBlank() }
        val totalWords = words.size.toDouble()

        if (totalWords == 0) {
            return LanguageDetectionResult("en", 0.0, emptyMap())
        }

        for ((language, patterns) in languagePatterns) {
            var matches = 0
            for (pattern in patterns) {
                matches += pattern.findAll(text).count()
            }
            scores[language] = matches / totalWords
        }

        val bestMatch = scores.maxByOrNull { it.value }
        return LanguageDetectionResult(
            detectedLanguage = bestMatch?.key ?: "en",
            confidence = bestMatch?.value ?: 0.0,
            allScores = scores
        )
    }

    fun getLanguageFromLocale(locale: String): String {
        return locale.split("-", "_")[0].lowercase()
    }

    fun expandToFullLocale(languageCode: String): String {
        return when (languageCode.lowercase()) {
            "en" -> "en-US"
            "es" -> "es-ES"
            "fr" -> "fr-FR"
            "de" -> "de-DE"
            "it" -> "it-IT"
            "pt" -> "pt-BR"
            "ru" -> "ru-RU"
            "zh" -> "zh-CN"
            "ja" -> "ja-JP"
            "ko" -> "ko-KR"
            "ar" -> "ar-SA"
            "hi" -> "hi-IN"
            else -> "$languageCode-US" // Default to US variant
        }
    }

    fun isRightToLeft(languageCode: String): Boolean {
        return languageCode.lowercase() in listOf("ar", "he", "fa", "ur")
    }

    fun requiresSpecialProcessing(languageCode: String): Boolean {
        return languageCode.lowercase() in listOf("zh", "ja", "ko", "th", "vi")
    }
}

data class LanguageDetectionResult(
    val detectedLanguage: String,
    val confidence: Double,
    val allScores: Map<String, Double>
)
```

## Phase 6: Module Integration and Registration (Week 8)

### 6.1 TTS Module Auto-Registration

**File: `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/components/tts/AndroidTTSModule.kt`**

```kotlin
object AndroidTTSModule : AutoRegisteringModule {

    override fun register() {
        val context = AndroidPlatformContext.applicationContext
            ?: throw SDKError.initializationFailed("Android context not available for TTS module")

        ModuleRegistry.shared.registerTTS(AndroidTTSServiceProvider(context))
    }

    override val isAvailable: Boolean
        get() = try {
            AndroidPlatformContext.applicationContext != null
        } catch (e: Exception) {
            false
        }
}
```

**File: `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/components/tts/JvmTTSModule.kt`**

```kotlin
object JvmTTSModule : AutoRegisteringModule {

    override fun register() {
        ModuleRegistry.shared.registerTTS(JvmTTSServiceProvider())
    }

    override val isAvailable: Boolean
        get() = try {
            // Check if we're running on a platform that supports TTS
            when (System.getProperty("os.name").lowercase()) {
                "windows", "mac os x", "linux" -> true
                else -> false
            }
        } catch (e: Exception) {
            false
        }
}
```

### 6.2 Enhanced TTSComponent Integration

**Update to existing file: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/TTSComponent.kt`**

```kotlin
// Add these methods to the existing TTSComponent class:

/**
 * Synthesize with SSML markup and platform-specific processing
 */
suspend fun synthesizeSSMLAdvanced(
    ssml: String,
    options: TTSOptions = TTSOptions()
): ByteArray {
    ensureReady()

    val platform = detectPlatform()
    val ssmlProcessor = SSMLProcessor()
    val processedSSML = ssmlProcessor.processSSML(ssml, platform)

    return synthesize(
        text = processedSSML.text,
        options = processedSSML.ttsOptions.copy(
            rate = options.rate.takeIf { it != 1.0f } ?: processedSSML.ttsOptions.rate,
            pitch = options.pitch.takeIf { it != 1.0f } ?: processedSSML.ttsOptions.pitch,
            volume = options.volume.takeIf { it != 1.0f } ?: processedSSML.ttsOptions.volume
        )
    )
}

/**
 * Get voice manager for advanced voice operations
 */
fun getVoiceManager(): VoiceManager {
    ensureReady()
    return VoiceManager(service!!)
}

/**
 * Auto-detect best voice for given text
 */
suspend fun synthesizeWithAutoLanguageDetection(
    text: String,
    options: TTSOptions = TTSOptions()
): ByteArray {
    ensureReady()

    val languageDetector = LanguageDetector()
    val detectionResult = languageDetector.detectLanguage(text)
    val fullLocale = languageDetector.expandToFullLocale(detectionResult.detectedLanguage)

    val voiceManager = getVoiceManager()
    val bestVoice = voiceManager.getBestVoiceFor(
        language = fullLocale,
        gender = options.voice.gender,
        style = options.voice.style
    )

    return synthesize(
        text = text,
        options = options.copy(voice = bestVoice)
    )
}

/**
 * Synthesize with audio format conversion
 */
suspend fun synthesizeWithFormat(
    text: String,
    options: TTSOptions = TTSOptions(),
    outputFormat: TTSOutputFormat = TTSOutputFormat.PCM_16KHZ
): ByteArray {
    val audioData = synthesize(text, options)

    return if (outputFormat != options.outputFormat) {
        val converter = AudioFormatConverter()
        converter.convertAudioFormat(audioData, options.outputFormat, outputFormat)
    } else {
        audioData
    }
}

/**
 * Synthesize with streaming buffer control
 */
fun synthesizeStreamWithBuffer(
    text: String,
    options: TTSOptions = TTSOptions(),
    bufferSizeMs: Long = 500
): Flow<ByteArray> {
    ensureReady()

    val streamingBuffer = StreamingAudioBuffer(bufferSizeMs, options.outputFormat.sampleRate)

    return flow {
        // Start synthesis in background
        val synthesisJob = launch {
            synthesizeStream(text, options).collect { chunk ->
                streamingBuffer.addAudioChunk(chunk)
            }
            streamingBuffer.markComplete()
        }

        // Emit buffered audio
        streamingBuffer.getAudioStream().collect { bufferedChunk ->
            emit(bufferedChunk)
        }

        synthesisJob.join()
    }
}

private fun detectPlatform(): TTSPlatform {
    return when {
        service is AndroidTTSServiceAdapter -> TTSPlatform.ANDROID
        service is JvmTTSServiceAdapter -> TTSPlatform.MARYTTS
        else -> TTSPlatform.SYSTEM
    }
}
```

## Phase 7: Error Handling and Testing Framework (Week 9)

### 7.1 TTS Error Handling

**File: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/tts/TTSErrorHandler.kt`**

```kotlin
class TTSErrorHandler {

    fun handleTTSError(error: Throwable): SDKError {
        return when (error) {
            is SDKError -> error
            is SecurityException -> SDKError.permissionDenied("TTS permission denied", error)
            is IllegalStateException -> SDKError.notInitialized("TTS service not properly initialized", error)
            is UnsupportedOperationException -> SDKError.unsupportedOperation("TTS operation not supported", error)
            is OutOfMemoryError -> SDKError.memoryError("Insufficient memory for TTS operation", error)
            else -> SDKError.synthesisError("Unexpected TTS error", error)
        }
    }

    fun createRetryPolicy(): RetryPolicy {
        return RetryPolicy(
            maxRetries = 3,
            backoffStrategy = BackoffStrategy.EXPONENTIAL,
            retryableErrors = setOf(
                SDKError.ErrorType.NETWORK_ERROR,
                SDKError.ErrorType.TEMPORARY_FAILURE,
                SDKError.ErrorType.SERVICE_UNAVAILABLE
            )
        )
    }

    suspend fun <T> withRetry(
        retryPolicy: RetryPolicy = createRetryPolicy(),
        operation: suspend () -> T
    ): T {
        var lastException: Throwable? = null
        var delay = retryPolicy.initialDelay

        repeat(retryPolicy.maxRetries + 1) { attempt ->
            try {
                return operation()
            } catch (e: Exception) {
                val sdkError = handleTTSError(e)
                lastException = sdkError

                if (attempt == retryPolicy.maxRetries ||
                    sdkError.type !in retryPolicy.retryableErrors) {
                    throw sdkError
                }

                delay(delay)
                delay = when (retryPolicy.backoffStrategy) {
                    BackoffStrategy.EXPONENTIAL -> delay * 2
                    BackoffStrategy.LINEAR -> delay + retryPolicy.initialDelay
                    BackoffStrategy.FIXED -> delay
                }
            }
        }

        throw lastException ?: SDKError.unknown("Retry failed without exception")
    }
}

data class RetryPolicy(
    val maxRetries: Int = 3,
    val initialDelay: Long = 1000,
    val backoffStrategy: BackoffStrategy = BackoffStrategy.EXPONENTIAL,
    val retryableErrors: Set<SDKError.ErrorType>
)

enum class BackoffStrategy {
    FIXED,
    LINEAR,
    EXPONENTIAL
}
```

### 7.2 TTS Testing Framework

**File: `sdk/runanywhere-kotlin/src/commonTest/kotlin/com/runanywhere/sdk/components/tts/TTSTestFramework.kt`**

```kotlin
class TTSTestFramework {

    fun createMockTTSService(): MockTTSService {
        return MockTTSService()
    }

    fun createTestAudioData(durationMs: Long, sampleRate: Int = 16000): ByteArray {
        val samplesCount = (durationMs * sampleRate / 1000).toInt()
        val audioData = ByteArray(samplesCount * 2) // 16-bit samples

        // Generate simple sine wave test data
        for (i in 0 until samplesCount) {
            val sample = (sin(2.0 * PI * 440.0 * i / sampleRate) * Short.MAX_VALUE).toInt().toShort()
            audioData[i * 2] = (sample.toInt() and 0xFF).toByte()
            audioData[i * 2 + 1] = ((sample.toInt() shr 8) and 0xFF).toByte()
        }

        return audioData
    }

    suspend fun testTTSServiceBasicFunctionality(service: TTSService) {
        // Test initialization
        service.initialize()

        // Test synthesis
        val testText = "Hello, this is a test."
        val audioData = service.synthesize(
            text = testText,
            voice = TTSVoice.DEFAULT,
            rate = 1.0f,
            pitch = 1.0f,
            volume = 1.0f
        )

        assert(audioData.isNotEmpty()) { "Audio data should not be empty" }

        // Test voice availability
        val voices = service.getAvailableVoices()
        assert(voices.isNotEmpty()) { "Should have at least one voice available" }

        // Test streaming
        val streamChunks = mutableListOf<ByteArray>()
        service.synthesizeStream(
            text = testText,
            voice = TTSVoice.DEFAULT,
            rate = 1.0f,
            pitch = 1.0f,
            volume = 1.0f
        ).collect { chunk ->
            streamChunks.add(chunk)
        }

        assert(streamChunks.isNotEmpty()) { "Should produce streaming chunks" }
    }

    suspend fun testSSMLProcessing(text: String, expectedOutputPattern: Regex) {
        val processor = SSMLProcessor()
        val result = processor.processSSML(text, TTSPlatform.ANDROID)

        assert(expectedOutputPattern.matches(result.text)) {
            "SSML processing result doesn't match expected pattern: ${result.text}"
        }
    }

    fun testVoiceManager(voiceManager: VoiceManager) {
        runBlocking {
            val voices = voiceManager.getAvailableVoices()
            assert(voices.isNotEmpty()) { "Voice manager should return available voices" }

            val englishVoices = voiceManager.getVoicesByLanguage("en-US")
            assert(englishVoices.all { it.language.startsWith("en") }) {
                "English voices should have English language code"
            }

            val bestVoice = voiceManager.getBestVoiceFor("en-US", TTSGender.FEMALE)
            assert(bestVoice.language.startsWith("en")) {
                "Best voice for English should have English language code"
            }
        }
    }

    fun testAudioFormatConversion() {
        val converter = AudioFormatConverter()
        val testData = createTestAudioData(1000) // 1 second

        // Test PCM format conversion
        val convertedData = converter.convertAudioFormat(
            testData,
            TTSOutputFormat.PCM_16KHZ,
            TTSOutputFormat.PCM_24KHZ
        )

        assert(convertedData.isNotEmpty()) { "Converted data should not be empty" }

        // Test WAV header addition
        val wavData = converter.addWaveHeader(testData, 16000)
        assert(wavData.size > testData.size) { "WAV data should be larger due to header" }
        assert(wavData.take(4).toByteArray().contentEquals("RIFF".toByteArray())) {
            "WAV header should start with RIFF"
        }
    }
}

class MockTTSService : TTSService {

    var isInitialized = false
    var synthesisDelay = 100L
    var shouldThrowError = false
    var customVoices = listOf(TTSVoice.DEFAULT)

    override suspend fun initialize() {
        delay(50) // Simulate initialization delay
        isInitialized = true
    }

    override suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray {
        if (shouldThrowError) {
            throw SDKError.synthesisError("Mock synthesis error")
        }

        delay(synthesisDelay)
        return TTSTestFramework().createTestAudioData(1000) // 1 second of audio
    }

    override fun synthesizeStream(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): Flow<ByteArray> = flow {
        if (shouldThrowError) {
            throw SDKError.synthesisError("Mock stream synthesis error")
        }

        val chunks = 5
        val chunkSize = 1000 / chunks

        repeat(chunks) {
            delay(synthesisDelay / chunks)
            emit(TTSTestFramework().createTestAudioData(chunkSize.toLong()))
        }
    }

    override fun getAvailableVoices(): List<TTSVoice> = customVoices

    override suspend fun loadModel(modelInfo: ModelInfo) {
        delay(100)
        // Mock model loading
    }

    override fun cancelCurrent() {
        // Mock cancellation
    }
}
```

## Phase 8: Integration Examples and Documentation (Week 10)

### 8.1 Basic Usage Example

**File: `examples/tts-integration/BasicTTSExample.kt`**

```kotlin
/**
 * Basic TTS Integration Example
 * Demonstrates simple text-to-speech synthesis
 */
class BasicTTSExample {

    private lateinit var sdk: RunAnywhere

    suspend fun initializeSDK() {
        sdk = RunAnywhere.initialize {
            apiKey = "your-api-key"

            // Optional: Register custom TTS provider
            // ModuleRegistry.shared.registerTTS(CustomTTSProvider())
        }
    }

    suspend fun basicTextSynthesis() {
        val text = "Hello, this is a basic text-to-speech example."

        // Simple synthesis
        val audioData = sdk.ttsComponent.synthesize(text)
        println("Generated ${audioData.size} bytes of audio")

        // Save to file
        saveAudioToFile(audioData, "basic_example.wav")
    }

    suspend fun synthesisWithOptions() {
        val text = "This example demonstrates TTS with custom options."

        val options = TTSOptions(
            voice = TTSVoice(
                id = "en-US-female-1",
                name = "Sarah",
                language = "en-US",
                gender = TTSGender.FEMALE
            ),
            rate = 1.2f,      // Slightly faster speech
            pitch = 1.1f,     // Slightly higher pitch
            volume = 0.9f,    // Slightly quieter
            outputFormat = TTSOutputFormat.PCM_16KHZ
        )

        val audioData = sdk.ttsComponent.synthesize(text, options)
        saveAudioToFile(audioData, "custom_options_example.wav")
    }

    suspend fun streamingSynthesis() {
        val longText = """
            This is a long text that will be synthesized using streaming.
            Streaming allows playback to start before the entire text is processed.
            This improves user experience by reducing perceived latency.
            The audio is generated in chunks and can be played progressively.
        """.trimIndent()

        // Collect streaming audio
        val audioChunks = mutableListOf<ByteArray>()
        sdk.ttsComponent.synthesizeStream(longText).collect { chunk ->
            audioChunks.add(chunk)
            println("Received audio chunk of ${chunk.size} bytes")

            // In a real app, you would play this chunk immediately
            playAudioChunk(chunk)
        }

        println("Streaming synthesis complete. Total chunks: ${audioChunks.size}")
    }

    suspend fun voiceManagement() {
        val voiceManager = sdk.ttsComponent.getVoiceManager()

        // Get all available voices
        val allVoices = voiceManager.getAvailableVoices()
        println("Available voices: ${allVoices.size}")
        allVoices.forEach { voice ->
            println("- ${voice.name} (${voice.language}, ${voice.gender})")
        }

        // Find English voices
        val englishVoices = voiceManager.getVoicesByLanguage("en-US")
        println("English voices: ${englishVoices.size}")

        // Find female voices
        val femaleVoices = voiceManager.getVoicesByGender(TTSGender.FEMALE)
        println("Female voices: ${femaleVoices.size}")

        // Get best voice for requirements
        val bestVoice = voiceManager.getBestVoiceFor(
            language = "en-US",
            gender = TTSGender.MALE,
            style = TTSStyle.FRIENDLY
        )
        println("Best voice: ${bestVoice.name}")
    }

    private fun saveAudioToFile(audioData: ByteArray, filename: String) {
        val converter = AudioFormatConverter()
        val wavData = converter.addWaveHeader(audioData, 16000)
        File(filename).writeBytes(wavData)
        println("Audio saved to $filename")
    }

    private fun playAudioChunk(chunk: ByteArray) {
        // Implementation depends on platform and audio framework
        println("Playing audio chunk...")
    }
}
```

### 8.2 Advanced SSML Example

**File: `examples/tts-integration/SSMLExample.kt`**

```kotlin
/**
 * SSML Integration Example
 * Demonstrates Speech Synthesis Markup Language usage
 */
class SSMLExample {

    private lateinit var sdk: RunAnywhere

    suspend fun initializeSDK() {
        sdk = RunAnywhere.initialize {
            apiKey = "your-api-key"
        }
    }

    suspend fun basicSSMLSynthesis() {
        val ssmlText = """
            <speak>
                <prosody rate="slow" pitch="low">
                    Hello, this is spoken slowly and with a low pitch.
                </prosody>
                <break time="1s"/>
                <prosody rate="fast" pitch="high">
                    And this is spoken quickly with a high pitch!
                </prosody>
            </speak>
        """.trimIndent()

        val audioData = sdk.ttsComponent.synthesizeSSMLAdvanced(ssmlText)
        saveAudioToFile(audioData, "ssml_basic.wav")
    }

    suspend fun complexSSMLExample() {
        val ssmlText = """
            <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">
                <voice name="en-US-AriaNeural">
                    <prosody rate="medium" pitch="medium">
                        Welcome to the weather forecast.
                    </prosody>
                    <break time="500ms"/>

                    <prosody rate="fast" volume="loud">
                        <emphasis level="strong">Breaking news!</emphasis>
                    </prosody>

                    Today's temperature will be
                    <say-as interpret-as="cardinal">25</say-as>
                    degrees Celsius, or
                    <say-as interpret-as="cardinal">77</say-as>
                    degrees Fahrenheit.

                    <break time="1s"/>

                    <prosody rate="slow" pitch="low">
                        The forecast was brought to you by RunAnywhere TTS.
                    </prosody>
                </voice>
            </speak>
        """.trimIndent()

        val audioData = sdk.ttsComponent.synthesizeSSMLAdvanced(ssmlText)
        saveAudioToFile(audioData, "ssml_complex.wav")
    }

    suspend fun multiLanguageSSML() {
        val ssmlText = """
            <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis">
                <voice xml:lang="en-US">
                    Hello, I can speak multiple languages.
                </voice>
                <break time="1s"/>

                <voice xml:lang="es-ES">
                    Hola, puedo hablar varios idiomas.
                </voice>
                <break time="1s"/>

                <voice xml:lang="fr-FR">
                    Bonjour, je peux parler plusieurs langues.
                </voice>
            </speak>
        """.trimIndent()

        val audioData = sdk.ttsComponent.synthesizeSSMLAdvanced(ssmlText)
        saveAudioToFile(audioData, "ssml_multilingual.wav")
    }

    suspend fun emotionalSpeechSSML() {
        val ssmlText = """
            <speak>
                <prosody rate="medium" pitch="medium">
                    Let me demonstrate different speaking styles.
                </prosody>
                <break time="1s"/>

                <prosody rate="fast" pitch="high" volume="loud">
                    <emphasis level="strong">
                        This is exciting and energetic!
                    </emphasis>
                </prosody>
                <break time="500ms"/>

                <prosody rate="slow" pitch="low" volume="soft">
                    This is calm and soothing...
                </prosody>
                <break time="500ms"/>

                <prosody rate="x-slow" pitch="x-low">
                    And this is very slow and deep.
                </prosody>
            </speak>
        """.trimIndent()

        val audioData = sdk.ttsComponent.synthesizeSSMLAdvanced(ssmlText)
        saveAudioToFile(audioData, "ssml_emotional.wav")
    }

    private fun saveAudioToFile(audioData: ByteArray, filename: String) {
        val converter = AudioFormatConverter()
        val wavData = converter.addWaveHeader(audioData, 16000)
        File(filename).writeBytes(wavData)
        println("Audio saved to $filename")
    }
}
```

### 8.3 Multi-Platform Integration Example

**File: `examples/tts-integration/MultiPlatformTTSExample.kt`**

```kotlin
/**
 * Multi-Platform TTS Example
 * Demonstrates platform-specific optimizations and fallbacks
 */
class MultiPlatformTTSExample {

    private lateinit var sdk: RunAnywhere

    suspend fun initializeSDK() {
        sdk = RunAnywhere.initialize {
            apiKey = "your-api-key"

            // Configure platform-specific TTS providers
            configurePlatformProviders()
        }
    }

    private fun configurePlatformProviders() {
        when (getCurrentPlatform()) {
            Platform.ANDROID -> {
                // Android-specific TTS configuration
                println("Configuring Android TTS...")
                // AndroidTTSModule will auto-register
            }
            Platform.JVM -> {
                // JVM-specific TTS configuration
                println("Configuring JVM TTS...")
                val jvmProvider = JvmTTSServiceProvider()
                jvmProvider.setPreferredEngine(JvmTTSServiceProvider.TTSEngine.MARYTTS)
                ModuleRegistry.shared.registerTTS(jvmProvider)
            }
        }
    }

    suspend fun synthesizeWithPlatformOptimization() {
        val text = "This text will be synthesized using platform-optimized settings."

        val platformOptimizedOptions = when (getCurrentPlatform()) {
            Platform.ANDROID -> TTSOptions(
                // Android works well with moderate settings
                rate = 1.0f,
                pitch = 1.0f,
                outputFormat = TTSOutputFormat.PCM_16KHZ
            )
            Platform.JVM -> TTSOptions(
                // JVM/MaryTTS can handle higher quality
                rate = 1.0f,
                pitch = 1.0f,
                outputFormat = TTSOutputFormat.PCM_24KHZ
            )
        }

        val audioData = sdk.ttsComponent.synthesize(text, platformOptimizedOptions)
        val filename = "platform_optimized_${getCurrentPlatform().name.lowercase()}.wav"
        saveAudioToFile(audioData, filename)
    }

    suspend fun handlePlatformDifferences() {
        // Test SSML support across platforms
        val ssmlText = """
            <speak>
                <prosody rate="slow">This text uses SSML prosody controls.</prosody>
                <break time="1s"/>
                <emphasis level="strong">This text is emphasized.</emphasis>
            </speak>
        """.trimIndent()

        try {
            val audioData = when (getCurrentPlatform()) {
                Platform.ANDROID -> {
                    // Android has limited SSML support
                    println("Using Android TTS with limited SSML...")
                    sdk.ttsComponent.synthesizeSSMLAdvanced(ssmlText)
                }
                Platform.JVM -> {
                    // MaryTTS has better SSML support
                    println("Using MaryTTS with full SSML support...")
                    sdk.ttsComponent.synthesizeSSMLAdvanced(ssmlText)
                }
            }

            val filename = "ssml_${getCurrentPlatform().name.lowercase()}.wav"
            saveAudioToFile(audioData, filename)

        } catch (e: SDKError) {
            println("Platform-specific error: ${e.message}")
            handleTTSError(e)
        }
    }

    suspend fun demonstrateAutoLanguageDetection() {
        val multilingualTexts = listOf(
            "Hello, how are you today?",                    // English
            "Hola, ¿cómo estás hoy?",                      // Spanish
            "Bonjour, comment allez-vous aujourd'hui?",     // French
            "Hallo, wie geht es dir heute?",               // German
            "こんにちは、今日はどうですか？"                      // Japanese
        )

        for ((index, text) in multilingualTexts.withIndex()) {
            try {
                println("Processing text: $text")

                val audioData = sdk.ttsComponent.synthesizeWithAutoLanguageDetection(text)
                val filename = "auto_lang_$index.wav"
                saveAudioToFile(audioData, filename)

                println("Successfully synthesized multilingual text $index")

            } catch (e: SDKError) {
                println("Failed to synthesize text $index: ${e.message}")
                // Try with default English voice as fallback
                val fallbackAudio = sdk.ttsComponent.synthesize(text)
                saveAudioToFile(fallbackAudio, "fallback_$index.wav")
            }
        }
    }

    suspend fun testStreamingPerformance() {
        val longText = generateLongText(1000) // 1000 words

        println("Testing streaming performance on ${getCurrentPlatform()}...")
        val startTime = System.currentTimeMillis()
        var chunkCount = 0
        var totalBytes = 0L

        sdk.ttsComponent.synthesizeStreamWithBuffer(
            text = longText,
            bufferSizeMs = when (getCurrentPlatform()) {
                Platform.ANDROID -> 300 // Smaller buffer for mobile
                Platform.JVM -> 500     // Larger buffer for desktop
            }
        ).collect { chunk ->
            chunkCount++
            totalBytes += chunk.size

            if (chunkCount % 10 == 0) {
                println("Processed $chunkCount chunks, ${totalBytes} total bytes")
            }
        }

        val endTime = System.currentTimeMillis()
        val duration = endTime - startTime

        println("Streaming completed:")
        println("- Platform: ${getCurrentPlatform()}")
        println("- Duration: ${duration}ms")
        println("- Chunks: $chunkCount")
        println("- Total bytes: $totalBytes")
        println("- Average chunk size: ${totalBytes / chunkCount}")
        println("- Throughput: ${totalBytes / duration * 1000} bytes/second")
    }

    private fun getCurrentPlatform(): Platform {
        return try {
            Class.forName("android.os.Build")
            Platform.ANDROID
        } catch (e: ClassNotFoundException) {
            Platform.JVM
        }
    }

    private fun generateLongText(wordCount: Int): String {
        val words = listOf(
            "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
            "speech", "synthesis", "technology", "enables", "computers", "to",
            "convert", "written", "text", "into", "spoken", "words", "using",
            "various", "algorithms", "and", "techniques"
        )

        return (1..wordCount).map { words.random() }.joinToString(" ")
    }

    private fun handleTTSError(error: SDKError) {
        when (error.type) {
            SDKError.ErrorType.SYNTHESIS_ERROR -> {
                println("Synthesis failed, trying with fallback settings...")
                // Implement fallback logic
            }
            SDKError.ErrorType.NOT_INITIALIZED -> {
                println("TTS not initialized, reinitializing...")
                // Implement reinitialization
            }
            else -> {
                println("Unhandled TTS error: ${error.message}")
            }
        }
    }

    private fun saveAudioToFile(audioData: ByteArray, filename: String) {
        val converter = AudioFormatConverter()
        val wavData = converter.addWaveHeader(audioData, 16000)
        File(filename).writeBytes(wavData)
        println("Audio saved to $filename (${wavData.size} bytes)")
    }

    enum class Platform {
        ANDROID,
        JVM
    }
}
```

## Dependencies and Build Configuration

### Gradle Dependencies

Add these dependencies to the appropriate `build.gradle.kts` files:

**Android-specific dependencies:**
```kotlin
// In androidMain dependencies
implementation("androidx.core:core-ktx:1.12.0")
```

**JVM-specific dependencies:**
```kotlin
// In jvmMain dependencies
implementation("de.dfki.mary:marytts-runtime:5.2.1") // For MaryTTS
implementation("de.dfki.mary:marytts-lang-en:5.2.1") // English language support
```

### Gradle Module Configuration

**For modular architecture (if following MODULAR-ARCHITECTURE.md):**

```kotlin
// modules/runanywhere-tts/build.gradle.kts
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
}

kotlin {
    jvm()
    androidTarget()

    sourceSets {
        commonMain {
            dependencies {
                api(project(":modules:runanywhere-core"))
                implementation(libs.kotlinx.coroutines.core)
            }
        }

        androidMain {
            dependencies {
                implementation(libs.androidx.core.ktx)
            }
        }

        jvmMain {
            dependencies {
                implementation("de.dfki.mary:marytts-runtime:5.2.1")
                implementation("de.dfki.mary:marytts-lang-en:5.2.1")
            }
        }
    }
}
```

## Testing Strategy

### Unit Tests
- **TTSComponent** functionality testing
- **SSML processing** accuracy tests
- **Voice management** operations
- **Audio format conversion** validation
- **Language detection** accuracy tests

### Integration Tests
- **Platform-specific TTS engines** integration
- **Module registration** and discovery
- **Error handling** and recovery
- **Streaming performance** benchmarks

### Manual Testing
- **Voice quality** assessment across platforms
- **SSML compliance** testing with various engines
- **Memory usage** profiling during long synthesis
- **Multi-language** synthesis validation

## Performance Considerations

### Memory Management
- **Streaming synthesis** to reduce memory footprint
- **Voice model caching** strategies
- **Audio buffer management** for optimal playback
- **Garbage collection** optimization for audio data

### Latency Optimization
- **Chunked text processing** for faster startup
- **Background model loading** when possible
- **Audio format selection** based on platform capabilities
- **Network optimization** for cloud-based engines

## Security Considerations

### Data Privacy
- **Local processing** preference over cloud APIs
- **Secure key management** for cloud services
- **Audio data encryption** for sensitive content
- **User consent** for voice data processing

### Permission Management
- **Android RECORD_AUDIO** permission handling
- **File system access** for model storage
- **Network permissions** for cloud engines
- **Background processing** permissions

## Conclusion

This comprehensive TTS integration plan provides:

1. **Complete platform coverage** for Android and JVM with native system integration
2. **Advanced SSML support** with intelligent platform-specific processing
3. **Streaming audio synthesis** for improved user experience
4. **Robust voice management** with automatic language detection
5. **Modular architecture** following SDK patterns for easy maintenance
6. **Comprehensive error handling** and retry mechanisms
7. **Format conversion** support for different audio requirements
8. **Testing framework** for quality assurance
9. **Performance optimization** strategies for production use
10. **Security considerations** for enterprise deployment

The implementation follows the existing SDK architecture patterns, integrates seamlessly with the ModuleRegistry system, and provides a foundation for future TTS engine additions. The plan can be executed incrementally over 10 weeks with clear deliverables and testing milestones.
