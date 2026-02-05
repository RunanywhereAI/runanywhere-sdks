/**
 * KokoroQnnTTS - Kokoro TTS using ONNX Runtime with QNN Execution Provider
 *
 * This class provides Text-to-Speech synthesis using the Kokoro model
 * running on Qualcomm NPU via the QNN (Qualcomm Neural Network) backend.
 *
 * Model Format (HuggingFace ONNX):
 *   Inputs:
 *     - input_ids: [1, sequence_length] - token IDs
 *     - style: [1, 256] - voice style embedding
 *     - speed: [1] - speed multiplier
 *   Outputs:
 *     - waveform: [1, audio_length] - audio samples
 *
 * NPU Acceleration:
 *   - Uses ONNX Runtime QNN Execution Provider
 *   - Targets Qualcomm Hexagon HTP (Hexagon Tensor Processor)
 *   - Falls back to CPU if QNN not available
 *
 * Usage:
 * ```kotlin
 * val tts = KokoroQnnTTS.create(context, modelPath).getOrThrow()
 * val audio = tts.synthesize("Hello world", voice = "af_bella").getOrThrow()
 * // audio.samples contains Float32 PCM at 24000 Hz
 * tts.release()
 * ```
 */
package com.runanywhere.sdk.core.onnx.tts

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.OrtSession.SessionOptions
import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.IntBuffer
import java.nio.LongBuffer

/**
 * Result of TTS synthesis containing audio data.
 */
data class KokoroAudioResult(
    /** Audio samples as Float32 PCM */
    val samples: FloatArray,
    /** Sample rate in Hz (typically 24000) */
    val sampleRate: Int,
    /** Duration in seconds */
    val durationSeconds: Float,
    /** Inference time in milliseconds */
    val inferenceTimeMs: Long,
    /** Whether NPU was used */
    val usedNpu: Boolean
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as KokoroAudioResult
        return samples.contentEquals(other.samples) &&
            sampleRate == other.sampleRate
    }

    override fun hashCode(): Int {
        var result = samples.contentHashCode()
        result = 31 * result + sampleRate
        return result
    }
}

/**
 * Voice embedding for Kokoro TTS.
 * Contains a 256-dimensional style vector.
 */
data class VoiceEmbedding(
    val id: String,
    val name: String,
    val embedding: FloatArray  // 256-dim style vector
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as VoiceEmbedding
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}

/**
 * Model format configuration.
 * Different Kokoro exports use different input/output names and types.
 */
private data class ModelFormat(
    /** Input name for tokens ("input_ids" or "tokens") */
    val tokenInputName: String,
    /** Whether speed is INT32 (fixed models) or FLOAT (dynamic models) */
    val speedIsInt: Boolean,
    /** Fixed sequence length, or null for dynamic */
    val fixedSequenceLength: Int?,
    /** Output name for audio ("waveform" or "audio") */
    val audioOutputName: String
) {
    companion object {
        fun detect(session: OrtSession): ModelFormat {
            val inputNames = session.inputNames.toSet()
            val outputNames = session.outputNames.toSet()

            // Detect token input name
            val tokenInputName = when {
                "tokens" in inputNames -> "tokens"
                "input_ids" in inputNames -> "input_ids"
                else -> throw IllegalStateException("Unknown token input. Found: $inputNames")
            }

            // Detect speed type from model info
            val speedInfo = session.inputInfo["speed"]
            val speedIsInt = speedInfo?.toString()?.contains("INT") == true

            // Detect fixed sequence length from token input shape
            val tokenInfo = session.inputInfo[tokenInputName]
            val tokenShape = tokenInfo?.toString()
            val fixedLength = if (tokenShape != null) {
                // Parse shape like "shape=[1, 50]" or "shape=[1, -1]"
                val match = Regex("""\[1,\s*(\d+)]""").find(tokenShape)
                match?.groupValues?.get(1)?.toIntOrNull()
            } else null

            // Detect audio output name
            val audioOutputName = when {
                "audio" in outputNames -> "audio"
                "waveform" in outputNames -> "waveform"
                else -> outputNames.first() // Fallback to first output
            }

            return ModelFormat(
                tokenInputName = tokenInputName,
                speedIsInt = speedIsInt,
                fixedSequenceLength = fixedLength,
                audioOutputName = audioOutputName
            )
        }
    }
}

/**
 * Kokoro TTS with QNN NPU acceleration.
 */
class KokoroQnnTTS private constructor(
    private val env: OrtEnvironment,
    private val session: OrtSession,
    private val tokenizer: KokoroTokenizer,
    private val voiceEmbeddings: Map<String, VoiceEmbedding>,
    private val defaultVoice: VoiceEmbedding,
    private val usedNpu: Boolean,
    private val modelFormat: ModelFormat
) {
    companion object {
        private const val TAG = "KokoroQnnTTS"
        
        /** Default sample rate for Kokoro */
        const val SAMPLE_RATE = 24000
        
        /** Style embedding dimension */
        private const val STYLE_DIM = 256
        
        /**
         * Create a KokoroQnnTTS instance.
         *
         * @param context Android context
         * @param modelDir Directory containing model files (model.onnx, tokens.txt, voices folder or voices.bin)
         * @param preferNpu If true (default), prefer NPU acceleration; if false, use CPU
         * @return Result containing the TTS instance or an error
         */
        suspend fun create(
            context: Context,
            modelDir: String,
            preferNpu: Boolean = true
        ): Result<KokoroQnnTTS> = withContext(Dispatchers.IO) {
            runCatching {
                Log.i(TAG, "Creating KokoroQnnTTS from: $modelDir")
                
                val modelPath = findModelFile(modelDir)
                    ?: throw IllegalArgumentException("No .onnx model found in $modelDir")
                val tokensPath = File(modelDir, "tokens.txt")
                
                // Validate files exist
                require(File(modelPath).exists()) { "Model not found: $modelPath" }
                require(tokensPath.exists()) { "Tokens not found: ${tokensPath.absolutePath}" }
                
                Log.i(TAG, "Model: $modelPath")
                Log.i(TAG, "Tokens: ${tokensPath.absolutePath}")
                
                // Create ONNX environment
                val env = OrtEnvironment.getEnvironment()
                
                // Create session options with QNN if available
                val (sessionOptions, usedNpu) = createSessionOptions(context, preferNpu)
                
                Log.i(TAG, "Creating ONNX session (NPU: $usedNpu)...")
                val startTime = System.currentTimeMillis()
                val session = env.createSession(modelPath, sessionOptions)
                val loadTime = System.currentTimeMillis() - startTime
                Log.i(TAG, "Session created in ${loadTime}ms")
                
                // Log model info
                logModelInfo(session)
                
                // Load tokenizer
                val tokenizer = KokoroTokenizer.load(tokensPath.absolutePath)
                Log.i(TAG, "Tokenizer loaded: ${tokenizer.vocabSize} tokens")
                
                // Load voice embeddings
                val voiceEmbeddings = loadVoiceEmbeddings(modelDir)
                Log.i(TAG, "Voice embeddings loaded: ${voiceEmbeddings.size} voices")
                
                // Get or create default voice
                val defaultVoice = voiceEmbeddings["af_bella"]
                    ?: voiceEmbeddings.values.firstOrNull()
                    ?: createDefaultEmbedding()
                
                // Detect model format
                val modelFormat = ModelFormat.detect(session)
                Log.i(TAG, "Model format detected:")
                Log.i(TAG, "  - Token input: ${modelFormat.tokenInputName}")
                Log.i(TAG, "  - Speed type: ${if (modelFormat.speedIsInt) "INT32" else "FLOAT"}")
                Log.i(TAG, "  - Fixed length: ${modelFormat.fixedSequenceLength ?: "dynamic"}")
                Log.i(TAG, "  - Audio output: ${modelFormat.audioOutputName}")

                KokoroQnnTTS(env, session, tokenizer, voiceEmbeddings, defaultVoice, usedNpu, modelFormat)
            }
        }
        
        /**
         * Load voice embeddings from model directory.
         * Supports both individual .bin files in voices/ folder and single voices.bin
         */
        private fun loadVoiceEmbeddings(modelDir: String): Map<String, VoiceEmbedding> {
            val embeddings = mutableMapOf<String, VoiceEmbedding>()
            
            // Try voices/ directory first
            val voicesDir = File(modelDir, "voices")
            if (voicesDir.isDirectory) {
                voicesDir.listFiles()?.filter { it.extension == "bin" }?.forEach { file ->
                    try {
                        val embedding = loadEmbeddingFromFile(file)
                        if (embedding != null) {
                            val voiceId = file.nameWithoutExtension
                            embeddings[voiceId] = VoiceEmbedding(
                                id = voiceId,
                                name = voiceId.replace("_", " ").replaceFirstChar { it.uppercase() },
                                embedding = embedding
                            )
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to load voice: ${file.name}: ${e.message}")
                    }
                }
            }
            
            // Try single voices.bin file
            val voicesBin = File(modelDir, "voices.bin")
            if (embeddings.isEmpty() && voicesBin.exists()) {
                try {
                    val embedding = loadEmbeddingFromFile(voicesBin)
                    if (embedding != null) {
                        // Single voice file - use as default
                        embeddings["af_bella"] = VoiceEmbedding(
                            id = "af_bella",
                            name = "Bella",
                            embedding = embedding
                        )
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to load voices.bin: ${e.message}")
                }
            }
            
            // If no embeddings loaded, create defaults
            if (embeddings.isEmpty()) {
                Log.w(TAG, "No voice embeddings found, using zeros")
                embeddings["af_bella"] = createDefaultEmbedding()
            }
            
            return embeddings
        }
        
        /**
         * Load embedding from a .bin file.
         * The file contains float32 values. We take the mean across frames to get a 256-dim vector.
         */
        private fun loadEmbeddingFromFile(file: File): FloatArray? {
            val bytes = file.readBytes()
            val floatCount = bytes.size / 4
            
            if (floatCount < STYLE_DIM) {
                Log.w(TAG, "Voice file ${file.name} too small: $floatCount floats")
                return null
            }
            
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val floats = FloatArray(floatCount)
            buffer.asFloatBuffer().get(floats)
            
            // If exactly 256 floats, use directly
            if (floatCount == STYLE_DIM) {
                return floats
            }
            
            // Otherwise, compute mean across frames
            val numFrames = floatCount / STYLE_DIM
            val result = FloatArray(STYLE_DIM)
            
            for (i in 0 until STYLE_DIM) {
                var sum = 0f
                for (frame in 0 until numFrames) {
                    sum += floats[frame * STYLE_DIM + i]
                }
                result[i] = sum / numFrames
            }
            
            Log.d(TAG, "Loaded voice ${file.name}: $numFrames frames -> 256-dim mean")
            return result
        }
        
        private fun createDefaultEmbedding(): VoiceEmbedding {
            return VoiceEmbedding(
                id = "default",
                name = "Default",
                embedding = FloatArray(STYLE_DIM) { 0f }
            )
        }
        
        private fun findModelFile(modelDir: String): String? {
            val dir = File(modelDir)
            if (!dir.isDirectory) return null
            
            // Look for .onnx file
            return dir.listFiles()
                ?.firstOrNull { it.extension == "onnx" }
                ?.absolutePath
        }
        
        /**
         * Backend type for logging and result reporting.
         */
        private enum class QnnBackend(val libraryName: String, val displayName: String) {
            HTP("libQnnHtp.so", "NPU/HTP"),
            GPU("libQnnGpu.so", "GPU"),
            CPU("", "CPU")
        }

        /**
         * Result of session creation with backend info.
         */
        private data class SessionResult(
            val options: SessionOptions,
            val backend: QnnBackend,
            val contextCached: Boolean = false
        )

        private fun createSessionOptions(
            context: Context,
            preferNpu: Boolean
        ): Pair<SessionOptions, Boolean> {
            val result = createSessionOptionsWithBackend(context, preferNpu)
            return Pair(result.options, result.backend != QnnBackend.CPU)
        }

        private fun createSessionOptionsWithBackend(
            context: Context,
            preferNpu: Boolean
        ): SessionResult {
            val options = SessionOptions()

            if (!preferNpu) {
                Log.i(TAG, "NPU disabled by user, using CPU")
                return configureCpuOptions(options)
            }

            // Check if QNN libraries are available
            val qnnAvailable = isQnnAvailable(context)
            if (!qnnAvailable) {
                Log.w(TAG, "QNN libraries not found in APK, using CPU")
                return configureCpuOptions(options)
            }

            // Strategy: Try HTP first (fastest), then GPU (dynamic shape support), then CPU
            // Note: HTP requires static shapes, so it may fail for dynamic models

            // Try HTP (NPU) first - best performance if model has static shapes
            val htpResult = tryQnnBackend(options, context, QnnBackend.HTP)
            if (htpResult != null) {
                return htpResult
            }

            // Try GPU - supports dynamic shapes, good performance
            val gpuResult = tryQnnBackend(SessionOptions(), context, QnnBackend.GPU)
            if (gpuResult != null) {
                return gpuResult
            }

            // Fallback to CPU
            Log.i(TAG, "All QNN backends failed, falling back to CPU")
            return configureCpuOptions(SessionOptions())
        }

        private fun tryQnnBackend(
            options: SessionOptions,
            context: Context,
            backend: QnnBackend
        ): SessionResult? {
            try {
                Log.i(TAG, "Trying QNN ${backend.displayName} backend...")

                val qnnOptions = mutableMapOf<String, String>()
                qnnOptions["backend_path"] = backend.libraryName

                // Don't set soc_model - let ONNX Runtime auto-detect
                // This avoids "Invalid config values" errors from mismatched SoC IDs

                // Performance mode for HTP
                if (backend == QnnBackend.HTP) {
                    qnnOptions["htp_performance_mode"] = "high_performance"
                    // Enable FP16 precision for better NPU utilization
                    qnnOptions["enable_htp_fp16_precision"] = "1"
                }

                Log.d(TAG, "QNN ${backend.displayName} options: $qnnOptions")

                options.addQnn(qnnOptions)
                Log.i(TAG, "QNN ${backend.displayName} Execution Provider configured!")

                // Note: addQnn may succeed but actual initialization may fail later
                // when the session is created (for dynamic shape models on HTP)
                return SessionResult(options, backend)

            } catch (e: Exception) {
                Log.w(TAG, "Failed to configure QNN ${backend.displayName}: ${e.message}")
                return null
            }
        }

        private fun configureCpuOptions(options: SessionOptions): SessionResult {
            Log.i(TAG, "Configuring CPU execution with optimizations")
            options.setIntraOpNumThreads(4)
            options.setOptimizationLevel(SessionOptions.OptLevel.ALL_OPT)
            return SessionResult(options, QnnBackend.CPU)
        }
        
        private fun isQnnAvailable(context: Context): Boolean {
            // Check if QNN library exists
            val nativeLibDir = context.applicationInfo.nativeLibraryDir
            val qnnLib = File(nativeLibDir, "libQnnHtp.so")
            return qnnLib.exists().also {
                Log.d(TAG, "QNN library check: ${qnnLib.absolutePath} exists=$it")
            }
        }
        
        private fun logModelInfo(session: OrtSession) {
            Log.i(TAG, "Model inputs:")
            session.inputNames.forEach { name ->
                val info = session.inputInfo[name]
                Log.i(TAG, "  - $name: $info")
            }
            Log.i(TAG, "Model outputs:")
            session.outputNames.forEach { name ->
                val info = session.outputInfo[name]
                Log.i(TAG, "  - $name: $info")
            }
        }
    }
    
    /**
     * List available voices.
     */
    fun listVoices(): List<String> = voiceEmbeddings.keys.toList()
    
    /**
     * Synthesize speech from text.
     *
     * @param text Text to synthesize
     * @param voice Voice ID (e.g., "af_bella", "am_adam")
     * @param speed Speed multiplier (0.5 = half speed, 2.0 = double speed)
     * @return Result containing audio data or an error
     */
    suspend fun synthesize(
        text: String,
        voice: String = "af_bella",
        speed: Float = 1.0f
    ): Result<KokoroAudioResult> = withContext(Dispatchers.IO) {
        runCatching {
            Log.i(TAG, "Synthesizing: \"${text.take(50)}\" (voice=$voice, speed=$speed)")
            val startTime = System.currentTimeMillis()

            // Convert text to tokens
            var tokens = tokenizer.encode(text)
            Log.d(TAG, "Tokens: ${tokens.size} tokens")

            if (tokens.isEmpty()) {
                throw IllegalArgumentException("Failed to tokenize text")
            }

            // Handle fixed-length models: pad or truncate tokens
            val fixedLen = modelFormat.fixedSequenceLength
            if (fixedLen != null) {
                tokens = when {
                    tokens.size < fixedLen -> {
                        // Pad with zeros (PAD token)
                        Log.d(TAG, "Padding tokens from ${tokens.size} to $fixedLen")
                        tokens + List(fixedLen - tokens.size) { 0L }
                    }
                    tokens.size > fixedLen -> {
                        // Truncate (may lose content)
                        Log.w(TAG, "Truncating tokens from ${tokens.size} to $fixedLen (text may be cut)")
                        tokens.take(fixedLen)
                    }
                    else -> tokens
                }
            }

            // Get voice embedding - fall back to default if not found
            val voiceEmb = voiceEmbeddings[voice]
                ?: voiceEmbeddings[voice.lowercase()]
                ?: defaultVoice.also {
                    Log.w(TAG, "Unknown voice: $voice, using default: ${it.id}")
                }
            Log.d(TAG, "Using voice: ${voiceEmb.id}")

            // Prepare tokens tensor
            val tokensArray = tokens.toLongArray()
            val tokensTensor = OnnxTensor.createTensor(
                env,
                LongBuffer.wrap(tokensArray),
                longArrayOf(1, tokensArray.size.toLong())
            )

            // Prepare style tensor (256-dim voice embedding)
            val styleTensor = OnnxTensor.createTensor(
                env,
                FloatBuffer.wrap(voiceEmb.embedding),
                longArrayOf(1, STYLE_DIM.toLong())
            )

            // Prepare speed tensor - type depends on model format
            val speedTensor = if (modelFormat.speedIsInt) {
                // Fixed-shape models use INT32 speed (typically 1 = normal)
                val speedInt = speed.toInt().coerceIn(1, 2)
                OnnxTensor.createTensor(
                    env,
                    IntBuffer.wrap(intArrayOf(speedInt)),
                    longArrayOf(1)
                )
            } else {
                // Dynamic models use FLOAT speed
                OnnxTensor.createTensor(
                    env,
                    FloatBuffer.wrap(floatArrayOf(speed)),
                    longArrayOf(1)
                )
            }

            // Build inputs map using detected input names
            Log.d(TAG, "Model expects inputs: ${session.inputNames.toList()}")

            val inputs = mutableMapOf<String, OnnxTensor>(
                modelFormat.tokenInputName to tokensTensor,
                "style" to styleTensor,
                "speed" to speedTensor
            )

            Log.i(TAG, "Prepared inputs: ${inputs.keys.toList()}")
            Log.d(TAG, "  - ${modelFormat.tokenInputName} shape: [1, ${tokensArray.size}]")
            Log.d(TAG, "  - style shape: [1, ${voiceEmb.embedding.size}]")
            Log.d(TAG, "  - speed value: $speed (as ${if (modelFormat.speedIsInt) "INT32" else "FLOAT"})")

            // Verify all model inputs are provided
            val missingInputs = session.inputNames.filter { it !in inputs.keys }
            if (missingInputs.isNotEmpty()) {
                Log.e(TAG, "Missing required inputs: $missingInputs")
                throw IllegalStateException("Missing model inputs: $missingInputs")
            }

            // Run inference
            val inferenceStart = System.currentTimeMillis()
            val outputs = session.run(inputs)
            val inferenceTime = System.currentTimeMillis() - inferenceStart

            Log.i(TAG, "Inference completed in ${inferenceTime}ms (NPU: $usedNpu)")

            // Get audio output using detected output name
            // OrtSession.Result.get() returns Optional<OnnxValue>, need to extract the value
            val audioTensor = outputs.get(modelFormat.audioOutputName)?.orElse(null) as? OnnxTensor
                ?: outputs.firstOrNull()?.value as? OnnxTensor
                ?: throw IllegalStateException("No audio output from model")

            val audioBuffer = audioTensor.floatBuffer
            var samples = FloatArray(audioBuffer.remaining())
            audioBuffer.get(samples)

            // For fixed-output (padded) models, trim trailing silence
            // This happens when the model was converted to static shapes with padding
            if (modelFormat.fixedSequenceLength != null) {
                samples = trimTrailingSilence(samples)
                Log.d(TAG, "Trimmed padded output: ${audioBuffer.capacity()} -> ${samples.size} samples")
            }

            // Cleanup tensors
            tokensTensor.close()
            styleTensor.close()
            speedTensor.close()
            outputs.close()

            val totalTime = System.currentTimeMillis() - startTime
            val duration = samples.size.toFloat() / SAMPLE_RATE

            Log.i(TAG, "Synthesis complete: ${samples.size} samples, ${duration}s audio, ${totalTime}ms total")

            KokoroAudioResult(
                samples = samples,
                sampleRate = SAMPLE_RATE,
                durationSeconds = duration,
                inferenceTimeMs = inferenceTime,
                usedNpu = usedNpu
            )
        }
    }
    
    /**
     * Release resources.
     */
    fun release() {
        try {
            session.close()
            Log.i(TAG, "Session released")
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing session: ${e.message}")
        }
    }

    /**
     * Trim trailing silence (zeros) from audio samples.
     * Used for padded static-output models where output is fixed to max length.
     *
     * @param samples Audio samples that may have trailing zeros
     * @param threshold Amplitude threshold below which is considered silence (default: 1e-6)
     * @param minSamples Minimum samples to keep even if all silent
     * @return Trimmed audio samples
     */
    private fun trimTrailingSilence(
        samples: FloatArray,
        threshold: Float = 1e-6f,
        minSamples: Int = SAMPLE_RATE / 10  // At least 100ms
    ): FloatArray {
        // Find last non-silent sample
        var lastNonSilent = samples.size - 1
        while (lastNonSilent > minSamples && kotlin.math.abs(samples[lastNonSilent]) < threshold) {
            lastNonSilent--
        }

        // Add a small fade-out buffer (50ms) to avoid click
        val fadeBuffer = SAMPLE_RATE / 20  // 50ms
        val endIndex = minOf(lastNonSilent + fadeBuffer, samples.size)

        return if (endIndex < samples.size) {
            samples.copyOf(endIndex)
        } else {
            samples
        }
    }
}
