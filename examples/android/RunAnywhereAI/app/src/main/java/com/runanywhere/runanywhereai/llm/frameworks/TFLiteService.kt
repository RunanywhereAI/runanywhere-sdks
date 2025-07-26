package com.runanywhere.runanywhereai.llm.frameworks

import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.llm.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import org.tensorflow.lite.gpu.CompatibilityList
import org.tensorflow.lite.nnapi.NnApiDelegate
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * TensorFlow Lite service implementation for on-device LLM inference
 * 
 * Supports various delegate options for hardware acceleration:
 * - GPU delegate for devices with compatible GPUs
 * - NNAPI delegate for devices with Neural Processing Units
 * - CPU fallback with multi-threading
 */
class TFLiteService(private val context: Context) : LLMService {
    companion object {
        private const val TAG = "TFLiteService"
        private const val DEFAULT_NUM_THREADS = 4
        
        // Common TFLite model configurations
        private const val MAX_SEQUENCE_LENGTH = 512
        private const val VOCAB_SIZE = 32000
    }
    
    private var interpreter: Interpreter? = null
    private var delegate: org.tensorflow.lite.Delegate? = null
    private var modelInfo: ModelInfo? = null
    
    // Model-specific parameters (to be determined from model metadata)
    private var inputShape: IntArray? = null
    private var outputShape: IntArray? = null
    private var vocabSize: Int = VOCAB_SIZE
    private var maxSeqLength: Int = MAX_SEQUENCE_LENGTH
    
    override val name: String = "TensorFlow Lite"
    
    override val isInitialized: Boolean
        get() = interpreter != null
    
    override suspend fun initialize(modelPath: String) {
        withContext(Dispatchers.IO) {
            try {
                release() // Clean up any existing instance
                
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    throw IllegalArgumentException("Model file does not exist: $modelPath")
                }
                
                // Create interpreter options
                val options = Interpreter.Options().apply {
                    setNumThreads(DEFAULT_NUM_THREADS)
                    
                    // Try to use hardware acceleration
                    delegate = createBestDelegate()
                    delegate?.let { addDelegate(it) }
                }
                
                // Load the model
                interpreter = Interpreter(modelFile, options)
                
                // Get model details
                extractModelDetails()
                
                // Create model info
                modelInfo = ModelInfo(
                    name = modelFile.nameWithoutExtension,
                    sizeBytes = modelFile.length(),
                    parameters = estimateParameterCount(),
                    quantization = detectQuantization(),
                    format = "TFLite",
                    framework = LLMFramework.TFLITE
                )
                
                Log.d(TAG, "TFLite model loaded successfully with delegate: ${delegate?.javaClass?.simpleName ?: "CPU"}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize TFLite model", e)
                release()
                throw e
            }
        }
    }
    
    override suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult {
        return withContext(Dispatchers.Default) {
            val interp = interpreter ?: return@withContext GenerationResult(
                text = "",
                tokensGenerated = 0,
                timeMs = 0,
                tokensPerSecond = 0f
            )
            
            try {
                val startTime = System.currentTimeMillis()
                
                // For demonstration, we'll implement a simplified generation
                // In a real implementation, you'd need proper tokenization and decoding
                
                // Tokenize input (simplified - real implementation needs proper tokenizer)
                val inputTokens = tokenizeSimple(prompt)
                
                // Prepare input tensor
                val inputBuffer = prepareInputBuffer(inputTokens)
                
                // Prepare output buffer
                val outputBuffer = ByteBuffer.allocateDirect(4 * vocabSize).order(ByteOrder.nativeOrder())
                
                // Run inference
                interp.run(inputBuffer, outputBuffer)
                
                // Decode output (simplified)
                val outputTokens = decodeOutput(outputBuffer, options)
                
                // Convert tokens to text (simplified)
                val response = detokenizeSimple(outputTokens)
                
                val endTime = System.currentTimeMillis()
                val tokensPerSecond = outputTokens.size.toFloat() / ((endTime - startTime) / 1000f)
                
                GenerationResult(
                    text = response,
                    tokensGenerated = outputTokens.size,
                    timeMs = endTime - startTime,
                    tokensPerSecond = tokensPerSecond
                )
            } catch (e: Exception) {
                Log.e(TAG, "Generation failed", e)
                GenerationResult(
                    text = "",
                    tokensGenerated = 0,
                    timeMs = 0,
                    tokensPerSecond = 0f
                )
            }
        }
    }
    
    override fun generateStream(prompt: String, options: GenerationOptions): Flow<GenerationResult> = flow {
        val interp = interpreter ?: run {
            emit(GenerationResult(
                text = "",
                tokensGenerated = 0,
                timeMs = 0,
                tokensPerSecond = 0f
            ))
            return@flow
        }
        
        try {
            val startTime = System.currentTimeMillis()
            var tokenCount = 0
            
            // For streaming, we would generate token by token
            // This is a simplified implementation
            val fullResponse = generate(prompt, options)
            
            // If generation failed, emit the error result
            if (fullResponse.text.isEmpty()) {
                emit(fullResponse)
                return@flow
            }
            
            // Emit the response in chunks to simulate streaming
            val words = fullResponse.text.split(" ")
            words.forEach { word ->
                val chunk = "$word "
                tokenCount++
                
                val currentTime = System.currentTimeMillis()
                val tokensPerSecond = tokenCount.toFloat() / ((currentTime - startTime) / 1000f)
                
                emit(GenerationResult(
                    text = chunk,
                    tokensGenerated = tokenCount,
                    timeMs = currentTime - startTime,
                    tokensPerSecond = tokensPerSecond
                ))
                
                kotlinx.coroutines.delay(50) // Simulate generation delay
            }
        } catch (e: Exception) {
            Log.e(TAG, "Stream generation failed", e)
            emit(GenerationResult(
                text = "",
                tokensGenerated = 0,
                timeMs = 0,
                tokensPerSecond = 0f
            ))
        }
    }
    
    override fun getModelInfo(): ModelInfo? = modelInfo
    
    override suspend fun release() {
        withContext(Dispatchers.IO) {
            interpreter?.close()
            interpreter = null
            delegate?.close()
            delegate = null
            modelInfo = null
            Log.d(TAG, "TFLite resources released")
        }
    }
    
    /**
     * Create the best available delegate for hardware acceleration
     */
    private fun createBestDelegate(): org.tensorflow.lite.Delegate? {
        return try {
            // First, try GPU delegate
            val compatList = CompatibilityList()
            if (compatList.isDelegateSupportedOnThisDevice) {
                Log.d(TAG, "Using GPU delegate")
                GpuDelegate()
            } else {
                // Try NNAPI delegate
                createNnApiDelegate()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to create hardware delegate, falling back to CPU", e)
            null
        }
    }
    
    /**
     * Create NNAPI delegate if available
     */
    private fun createNnApiDelegate(): NnApiDelegate? {
        return try {
            Log.d(TAG, "Using NNAPI delegate")
            NnApiDelegate(
                NnApiDelegate.Options().apply {
                    setAllowFp16(true)
                    setUseNnapiCpu(false)
                }
            )
        } catch (e: Exception) {
            Log.w(TAG, "NNAPI not available", e)
            null
        }
    }
    
    /**
     * Extract model details from the interpreter
     */
    private fun extractModelDetails() {
        interpreter?.let { interp ->
            // Get input tensor details
            val inputTensor = interp.getInputTensor(0)
            inputShape = inputTensor.shape()
            
            // Get output tensor details
            val outputTensor = interp.getOutputTensor(0)
            outputShape = outputTensor.shape()
            
            // Update parameters based on actual model
            if (outputShape != null && outputShape!!.isNotEmpty()) {
                vocabSize = outputShape!![outputShape!!.size - 1]
            }
            
            Log.d(TAG, "Model input shape: ${inputShape?.contentToString()}")
            Log.d(TAG, "Model output shape: ${outputShape?.contentToString()}")
        }
    }
    
    /**
     * Estimate parameter count based on model size and quantization
     */
    private fun estimateParameterCount(): Long {
        val modelSize = modelInfo?.sizeBytes ?: 0L
        val quantization = detectQuantization()
        
        // Rough estimation based on quantization
        return when (quantization) {
            "INT8" -> modelSize * 1 // 1 byte per parameter
            "FLOAT16" -> modelSize / 2 // 2 bytes per parameter
            "FLOAT32" -> modelSize / 4 // 4 bytes per parameter
            else -> modelSize / 2 // Default assumption
        }
    }
    
    /**
     * Detect quantization type (simplified)
     */
    private fun detectQuantization(): String {
        return interpreter?.let { interp ->
            val inputType = interp.getInputTensor(0).dataType()
            when (inputType) {
                org.tensorflow.lite.DataType.UINT8 -> "INT8"
                org.tensorflow.lite.DataType.FLOAT32 -> "FLOAT32"
                else -> "UNKNOWN"
            }
        } ?: "UNKNOWN"
    }
    
    /**
     * Simple tokenization (replace with proper tokenizer)
     */
    private fun tokenizeSimple(text: String): List<Int> {
        // This is a placeholder - real implementation needs proper tokenizer
        return text.split(" ").map { it.hashCode() % vocabSize }
    }
    
    /**
     * Prepare input buffer for the model
     */
    private fun prepareInputBuffer(tokens: List<Int>): ByteBuffer {
        val bufferSize = 4 * maxSeqLength // Assuming FLOAT32 input
        val buffer = ByteBuffer.allocateDirect(bufferSize).order(ByteOrder.nativeOrder())
        val floatBuffer = buffer.asFloatBuffer()
        
        // Pad or truncate to max sequence length
        val paddedTokens = tokens.take(maxSeqLength).toMutableList()
        while (paddedTokens.size < maxSeqLength) {
            paddedTokens.add(0) // Padding token
        }
        
        // Convert to float and put in buffer
        paddedTokens.forEach { token ->
            floatBuffer.put(token.toFloat())
        }
        
        buffer.rewind()
        return buffer
    }
    
    /**
     * Decode output from the model
     */
    private fun decodeOutput(outputBuffer: ByteBuffer, options: GenerationOptions): List<Int> {
        outputBuffer.rewind()
        val floatBuffer = outputBuffer.asFloatBuffer()
        val logits = FloatArray(vocabSize)
        floatBuffer.get(logits)
        
        // Apply temperature and sampling
        val tokens = mutableListOf<Int>()
        repeat(options.maxTokens) {
            val sampledToken = sampleFromLogits(logits, options.temperature, options.topK)
            tokens.add(sampledToken)
            
            // Stop if we hit a stop token (simplified)
            if (sampledToken == 0) return@repeat
        }
        
        return tokens
    }
    
    /**
     * Sample from logits with temperature and top-k
     */
    private fun sampleFromLogits(logits: FloatArray, temperature: Float, topK: Int): Int {
        // Apply temperature
        val scaledLogits = logits.map { it / temperature }.toFloatArray()
        
        // Get top-k indices
        val topIndices = scaledLogits.indices
            .sortedByDescending { scaledLogits[it] }
            .take(topK)
        
        // Simple sampling - just take the highest probability
        // Real implementation would use proper sampling
        return topIndices.first()
    }
    
    /**
     * Simple detokenization (replace with proper tokenizer)
     */
    private fun detokenizeSimple(tokens: List<Int>): String {
        // This is a placeholder - real implementation needs proper tokenizer
        return "Generated text based on TFLite model inference. " +
               "Real implementation would decode tokens properly."
    }
}