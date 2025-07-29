package com.runanywhere.runanywhereai.llm.frameworks

import ai.onnxruntime.*
import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.llm.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.LongBuffer
import kotlin.math.exp
import kotlin.random.Random

/**
 * ONNX Runtime service implementation for cross-platform model support
 */
class ONNXRuntimeService(private val context: Context) : LLMService {
    companion object {
        private const val TAG = "ONNXRuntimeService"
        private const val VOCAB_SIZE = 32000 // Default vocab size, should be configurable
    }
    
    private var ortEnvironment: OrtEnvironment? = null
    private var ortSession: OrtSession? = null
    private val tokenizer = SimpleTokenizer() // Simplified tokenizer
    private var modelPath: String? = null
    
    override val name: String = "ONNX Runtime"
    
    override val isInitialized: Boolean
        get() = ortSession != null
    
    override suspend fun initialize(modelPath: String) = withContext(Dispatchers.IO) {
        try {
            release() // Clean up any existing session
            
            this@ONNXRuntimeService.modelPath = modelPath
            
            // Create ORT environment
            ortEnvironment = OrtEnvironment.getEnvironment()
            
            // Create session options
            val sessionOptions = OrtSession.SessionOptions().apply {
                // Add execution providers
                addNnapi() // Android NNAPI
                
                // Optimization settings
                setInterOpNumThreads(4)
                setIntraOpNumThreads(4)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                
                // Memory optimization
                setMemoryPatternOptimization(true)
                setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL)
            }
            
            // Load model
            val modelBytes = context.assets.open(modelPath).use { it.readBytes() }
            ortSession = ortEnvironment?.createSession(modelBytes, sessionOptions)
            
            Log.d(TAG, "ONNX model loaded successfully")
            logModelInfo()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize ONNX model", e)
            throw e
        }
    }
    
    override suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult {
        return withContext(Dispatchers.Default) {
            val session = ortSession ?: return@withContext GenerationResult(
                text = "",
                tokensGenerated = 0,
                timeMs = 0,
                tokensPerSecond = 0f
            )
            
            try {
                val startTime = System.currentTimeMillis()
                val generatedTokens = mutableListOf<Long>()
                var inputIds = tokenizer.encode(prompt)
                
                for (i in 0 until options.maxTokens) {
                    // Prepare input tensor
                    val inputTensor = createInputTensor(inputIds)
                    
                    // Run inference
                    val outputs = session.run(mapOf("input_ids" to inputTensor))
                    
                    // Process output
                    val logits = outputs[0]?.value as? Array<Array<FloatArray>>
                        ?: throw IllegalStateException("Invalid output format")
                    
                    val lastLogits = logits[0][inputIds.size - 1]
                    
                    // Sample next token
                    val nextToken = sampleToken(lastLogits, options.temperature, options.topK, options.topP)
                    generatedTokens.add(nextToken)
                    
                    // Check for EOS or stop sequences
                    if (nextToken == tokenizer.eosTokenId) break
                    
                    val decodedToken = tokenizer.decode(listOf(nextToken))
                    if (options.stopSequences.any { decodedToken.contains(it) }) break
                    
                    // Update input
                    inputIds = inputIds + nextToken
                    
                    // Clean up tensors
                    inputTensor.close()
                }
                
                val response = tokenizer.decode(generatedTokens)
                val endTime = System.currentTimeMillis()
                val tokensPerSecond = generatedTokens.size.toFloat() / ((endTime - startTime) / 1000f)
                
                GenerationResult(
                    text = response,
                    tokensGenerated = generatedTokens.size,
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
        val session = ortSession ?: run {
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
            var inputIds = tokenizer.encode(prompt)
            var tokenCount = 0
            
            repeat(options.maxTokens) {
                val inputTensor = createInputTensor(inputIds)
                val outputs = session.run(mapOf("input_ids" to inputTensor))
                
                val logits = outputs[0]?.value as? Array<Array<FloatArray>>
                    ?: throw IllegalStateException("Invalid output format")
                
                val nextToken = sampleToken(logits[0].last(), options.temperature, options.topK, options.topP)
                
                if (nextToken == tokenizer.eosTokenId) return@flow
                
                tokenCount++
                val text = tokenizer.decode(listOf(nextToken))
                
                val currentTime = System.currentTimeMillis()
                val tokensPerSecond = tokenCount.toFloat() / ((currentTime - startTime) / 1000f)
                
                emit(GenerationResult(
                    text = text,
                    tokensGenerated = tokenCount,
                    timeMs = currentTime - startTime,
                    tokensPerSecond = tokensPerSecond
                ))
                
                if (options.stopSequences.any { text.contains(it) }) return@flow
                
                inputIds = inputIds + nextToken
                
                // Clean up
                inputTensor.close()
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
    
    override fun getModelInfo(): ModelInfo? {
        return modelPath?.let { path ->
            ModelInfo(
                name = path.substringAfterLast("/"),
                sizeBytes = 0, // Would need to check actual file size
                parameters = null,
                quantization = "FP16",
                format = "ONNX",
                framework = LLMFramework.ONNX_RUNTIME
            )
        }
    }
    
    override suspend fun release() {
        withContext(Dispatchers.IO) {
            ortSession?.close()
            ortSession = null
            ortEnvironment?.close()
            ortEnvironment = null
        }
    }
    
    private fun createInputTensor(tokens: List<Long>): OnnxTensor {
        val env = ortEnvironment ?: throw IllegalStateException("Environment not initialized")
        val shape = longArrayOf(1, tokens.size.toLong())
        val buffer = LongBuffer.allocate(tokens.size)
        buffer.put(tokens.toLongArray())
        buffer.rewind()
        
        return OnnxTensor.createTensor(env, buffer, shape)
    }
    
    private fun sampleToken(logits: FloatArray, temperature: Float, topK: Int, topP: Float): Long {
        // Apply temperature
        val scaledLogits = logits.map { it / temperature }.toFloatArray()
        
        // Top-K filtering
        val topKIndices = scaledLogits.indices
            .sortedByDescending { scaledLogits[it] }
            .take(topK)
        
        // Softmax on top-K
        val maxLogit = topKIndices.maxOfOrNull { scaledLogits[it] } ?: 0f
        val expValues = topKIndices.map { idx ->
            idx to exp(scaledLogits[idx] - maxLogit)
        }
        val sumExp = expValues.sumOf { it.second.toDouble() }.toFloat()
        val probs = expValues.map { (idx, exp) ->
            idx to exp / sumExp
        }
        
        // Top-P (nucleus) sampling
        val sortedProbs = probs.sortedByDescending { it.second }
        var cumulativeProb = 0f
        val nucleus = mutableListOf<Pair<Int, Float>>()
        
        for (pair in sortedProbs) {
            nucleus.add(pair)
            cumulativeProb += pair.second
            if (cumulativeProb >= topP) break
        }
        
        // Sample from nucleus
        val random = Random.nextFloat()
        var cumulative = 0f
        
        for ((idx, prob) in nucleus) {
            cumulative += prob
            if (cumulative >= random) {
                return idx.toLong()
            }
        }
        
        return nucleus.first().first.toLong()
    }
    
    private fun logModelInfo() {
        val session = ortSession ?: return
        
        Log.d(TAG, "Model inputs:")
        session.inputNames?.forEach { name ->
            Log.d(TAG, "  $name")
        }
        
        Log.d(TAG, "Model outputs:")
        session.outputNames?.forEach { name ->
            Log.d(TAG, "  $name")
        }
    }
    
    /**
     * Simple tokenizer implementation (should be replaced with proper tokenizer)
     */
    private class SimpleTokenizer {
        val eosTokenId = 2L
        private val vocab = mutableMapOf<String, Long>()
        private val reverseVocab = mutableMapOf<Long, String>()
        
        init {
            // Initialize with basic tokens
            vocab["<pad>"] = 0L
            vocab["<s>"] = 1L
            vocab["</s>"] = 2L
            vocab["<unk>"] = 3L
            
            reverseVocab[0L] = "<pad>"
            reverseVocab[1L] = "<s>"
            reverseVocab[2L] = "</s>"
            reverseVocab[3L] = "<unk>"
        }
        
        fun encode(text: String): List<Long> {
            // Simple space-based tokenization
            val tokens = mutableListOf(1L) // Start token
            text.split(" ").forEach { word ->
                tokens.add(vocab[word] ?: 3L) // Unknown token
            }
            return tokens
        }
        
        fun decode(tokens: List<Long>): String {
            return tokens.mapNotNull { reverseVocab[it] }
                .filter { it !in listOf("<pad>", "<s>", "</s>", "<unk>") }
                .joinToString(" ")
        }
    }
}