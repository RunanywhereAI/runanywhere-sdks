package com.runanywhere.runanywhereai.llm.frameworks.native

import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.llm.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer

/**
 * Abstract base class for native LLM implementations
 *
 * This class provides common functionality for LLM services that use native code
 * including JNI bindings, memory management, and model loading utilities.
 *
 * Subclasses should implement the specific native methods and model handling
 * for their particular inference engine.
 */
abstract class NativeLLMService(
    protected val context: Context,
    protected val libraryName: String
) : LLMService {

    companion object {
        private const val TAG = "NativeLLMService"
    }

    protected var modelPtr: Long = 0L
    protected var modelInfo: ModelInfo? = null
    protected var nativeLibraryLoaded = false

    override var isInitialized: Boolean = false
        protected set

    init {
        loadNativeLibrary()
    }

    /**
     * Load the native library for this service
     */
    protected open fun loadNativeLibrary() {
        try {
            System.loadLibrary(libraryName)
            nativeLibraryLoaded = true
            Log.d(TAG, "Native library '$libraryName' loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "Native library '$libraryName' not found - ${name} functionality will be disabled", e)
            nativeLibraryLoaded = false
        }
    }

    /**
     * Validate that the native library is loaded
     */
    protected fun requireNativeLibrary() {
        if (!nativeLibraryLoaded) {
            throw IllegalStateException("Native library '$libraryName' is not loaded")
        }
    }

    /**
     * Validate model file exists and is readable
     */
    protected fun validateModelFile(modelPath: String): File {
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            throw IllegalArgumentException("Model file does not exist: $modelPath")
        }
        if (!modelFile.canRead()) {
            throw IllegalArgumentException("Cannot read model file: $modelPath")
        }
        return modelFile
    }

    /**
     * Get model file size in bytes
     */
    protected fun getModelSize(modelFile: File): Long {
        return modelFile.length()
    }

    /**
     * Load model into native memory
     * Subclasses should implement this to call their specific native loading method
     */
    protected abstract suspend fun loadNativeModel(modelPath: String): Long

    /**
     * Generate text using native implementation
     * Subclasses should implement this to call their specific native generation method
     */
    protected abstract suspend fun generateNative(
        prompt: String,
        options: GenerationOptions
    ): GenerationResult

    /**
     * Release native model resources
     * Subclasses should implement this to properly cleanup native memory
     */
    protected abstract suspend fun releaseNativeModel(modelPtr: Long)

    /**
     * Get native model information
     * Subclasses can override to provide more specific model details
     */
    protected open suspend fun getNativeModelInfo(modelPtr: Long): ModelInfo? {
        return modelInfo
    }

    override suspend fun initialize(modelPath: String) = withContext(Dispatchers.IO) {
        requireNativeLibrary()

        if (isInitialized) {
            Log.w(TAG, "$name is already initialized")
            return@withContext
        }

        val modelFile = validateModelFile(modelPath)

        try {
            Log.d(TAG, "Loading model: $modelPath")
            modelPtr = loadNativeModel(modelPath)

            if (modelPtr == 0L) {
                throw IllegalStateException("Failed to load model: native method returned null pointer")
            }

            // Create model info
            modelInfo = ModelInfo(
                name = modelFile.nameWithoutExtension,
                sizeBytes = getModelSize(modelFile),
                format = getModelFormat(modelFile),
                framework = getFramework()
            )

            isInitialized = true
            Log.d(TAG, "$name initialized successfully with model: ${modelFile.name}")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize $name", e)
            modelPtr = 0L
            modelInfo = null
            isInitialized = false
            throw IllegalStateException("Failed to initialize $name: ${e.message}", e)
        }
    }

    override suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult {
        if (!isInitialized) {
            throw IllegalStateException("$name is not initialized")
        }

        return generateNative(prompt, options)
    }

    override fun generateStream(prompt: String, options: GenerationOptions): Flow<GenerationResult> = flow {
        if (!isInitialized) {
            throw IllegalStateException("$name is not initialized")
        }

        // Default implementation: generate full result and emit as single chunk
        // Subclasses can override for true streaming
        val result = generateNative(prompt, options)
        emit(result)
    }

    override fun getModelInfo(): ModelInfo? = modelInfo

    override suspend fun release() = withContext(Dispatchers.IO) {
        if (isInitialized && modelPtr != 0L) {
            try {
                releaseNativeModel(modelPtr)
                Log.d(TAG, "$name released successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing $name", e)
            } finally {
                modelPtr = 0L
                modelInfo = null
                isInitialized = false
            }
        }
    }

    /**
     * Determine model format from file extension
     */
    protected open fun getModelFormat(modelFile: File): String {
        return when (modelFile.extension.lowercase()) {
            "gguf" -> "GGUF"
            "ggml" -> "GGML"
            "bin" -> "Binary"
            "pt" -> "PyTorch"
            "pte" -> "PyTorch Edge"
            "onnx" -> "ONNX"
            "tflite" -> "TensorFlow Lite"
            else -> "Unknown"
        }
    }

    /**
     * Get the LLM framework for this service
     */
    protected abstract fun getFramework(): LLMFramework
}

/**
 * Utility class for common native operations
 */
object NativeUtils {
    private const val TAG = "NativeUtils"

    /**
     * Load a binary file into a ByteBuffer for native processing
     */
    fun loadBinaryFile(filePath: String): ByteBuffer? {
        return try {
            val file = File(filePath)
            val bytes = file.readBytes()
            ByteBuffer.allocateDirect(bytes.size).apply {
                put(bytes)
                rewind()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load binary file: $filePath", e)
            null
        }
    }

    /**
     * Calculate memory usage for a model based on parameters and precision
     */
    fun estimateModelMemory(parameters: Long, precision: Int = 16): Long {
        // Rough estimation: parameters * bytes_per_parameter
        val bytesPerParam = when (precision) {
            4 -> 0.5 // Q4 quantization
            8 -> 1.0 // Q8 quantization
            16 -> 2.0 // FP16
            32 -> 4.0 // FP32
            else -> 2.0 // Default to FP16
        }
        return (parameters * bytesPerParam).toLong()
    }

    /**
     * Check if device has sufficient memory for model
     */
    fun hasSufficientMemory(context: Context, requiredMemoryBytes: Long): Boolean {
        val runtime = Runtime.getRuntime()
        val availableMemory = runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory())
        return availableMemory > requiredMemoryBytes * 1.2 // 20% buffer
    }
}
