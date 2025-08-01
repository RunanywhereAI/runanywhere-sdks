package com.runanywhere.runanywhereai.llm.frameworks.native

import android.content.Context
import android.util.Log
import java.io.File
import java.nio.ByteBuffer

/**
 * Utilities for JNI operations and native memory management
 *
 * This class provides common functionality for working with native code
 * including memory allocation, buffer management, and native library utilities.
 */
object JNIUtils {
    private const val TAG = "JNIUtils"

    /**
     * Allocate direct ByteBuffer for native memory sharing
     */
    fun allocateDirectBuffer(sizeBytes: Int): ByteBuffer {
        return ByteBuffer.allocateDirect(sizeBytes)
    }

    /**
     * Load file content into direct ByteBuffer for native processing
     */
    fun loadFileToDirectBuffer(filePath: String): ByteBuffer? {
        return try {
            val file = File(filePath)
            if (!file.exists() || !file.canRead()) {
                Log.e(TAG, "Cannot read file: $filePath")
                return null
            }

            val bytes = file.readBytes()
            val buffer = ByteBuffer.allocateDirect(bytes.size)
            buffer.put(bytes)
            buffer.rewind()
            buffer
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load file to buffer: $filePath", e)
            null
        }
    }

    /**
     * Copy data from ByteBuffer to byte array
     */
    fun bufferToByteArray(buffer: ByteBuffer): ByteArray {
        val array = ByteArray(buffer.remaining())
        buffer.get(array)
        return array
    }

    /**
     * Copy byte array to direct ByteBuffer
     */
    fun byteArrayToDirectBuffer(array: ByteArray): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(array.size)
        buffer.put(array)
        buffer.rewind()
        return buffer
    }

    /**
     * Check if native library exists in APK
     */
    fun isNativeLibraryAvailable(libraryName: String): Boolean {
        return try {
            System.loadLibrary(libraryName)
            true
        } catch (e: UnsatisfiedLinkError) {
            false
        }
    }

    /**
     * Get native library architecture information
     */
    external fun getNativeArchInfo(): NativeArchInfo?

    /**
     * Check native memory availability
     */
    external fun getNativeMemoryInfo(): NativeMemoryInfo?

    /**
     * Validate model file format in native code
     */
    external fun validateModelFormat(modelPath: String, expectedFormat: String): Boolean

    /**
     * Get file checksum using native implementation (faster for large files)
     */
    external fun calculateNativeChecksum(filePath: String): String?

    init {
        try {
            System.loadLibrary("jni-utils")
            Log.d(TAG, "JNI utilities library loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "JNI utilities library not available - some functions will be disabled", e)
        }
    }
}

/**
 * Native architecture information
 */
data class NativeArchInfo(
    val abi: String,
    val architecture: String,
    val hasNeon: Boolean,
    val hasAvx: Boolean,
    val cacheLineSize: Int,
    val pageSize: Int
)

/**
 * Native memory information
 */
data class NativeMemoryInfo(
    val totalPhysicalMemory: Long,
    val availablePhysicalMemory: Long,
    val totalVirtualMemory: Long,
    val availableVirtualMemory: Long,
    val processMemoryUsage: Long
)

/**
 * Memory pool for efficient native buffer management
 */
class NativeMemoryPool(
    private val bufferSize: Int = 1024 * 1024, // 1MB default
    private val maxBuffers: Int = 10
) {
    private val availableBuffers = mutableListOf<ByteBuffer>()
    private val usedBuffers = mutableSetOf<ByteBuffer>()

    /**
     * Get a buffer from the pool or create new one
     */
    @Synchronized
    fun acquireBuffer(): ByteBuffer {
        return if (availableBuffers.isNotEmpty()) {
            val buffer = availableBuffers.removeAt(0)
            buffer.clear()
            usedBuffers.add(buffer)
            buffer
        } else {
            val buffer = ByteBuffer.allocateDirect(bufferSize)
            usedBuffers.add(buffer)
            buffer
        }
    }

    /**
     * Return buffer to the pool
     */
    @Synchronized
    fun releaseBuffer(buffer: ByteBuffer) {
        if (usedBuffers.remove(buffer)) {
            if (availableBuffers.size < maxBuffers) {
                buffer.clear()
                availableBuffers.add(buffer)
            }
            // If pool is full, let buffer be garbage collected
        }
    }

    /**
     * Clear all buffers and release memory
     */
    @Synchronized
    fun clear() {
        availableBuffers.clear()
        usedBuffers.clear()
    }

    /**
     * Get pool statistics
     */
    @Synchronized
    fun getStats(): PoolStats {
        return PoolStats(
            totalBuffers = availableBuffers.size + usedBuffers.size,
            availableBuffers = availableBuffers.size,
            usedBuffers = usedBuffers.size,
            bufferSize = bufferSize
        )
    }
}

/**
 * Pool statistics
 */
data class PoolStats(
    val totalBuffers: Int,
    val availableBuffers: Int,
    val usedBuffers: Int,
    val bufferSize: Int
)

/**
 * Native tensor operations utilities
 */
object NativeTensorUtils {
    private const val TAG = "NativeTensorUtils"

    /**
     * Create tensor metadata for native operations
     */
    fun createTensorMetadata(
        shape: IntArray,
        dataType: TensorDataType,
        layout: TensorLayout = TensorLayout.NCHW
    ): TensorMetadata {
        val elementSize = when (dataType) {
            TensorDataType.FLOAT32 -> 4
            TensorDataType.FLOAT16 -> 2
            TensorDataType.INT32 -> 4
            TensorDataType.INT8 -> 1
            TensorDataType.UINT8 -> 1
        }

        val totalElements = shape.fold(1) { acc, dim -> acc * dim }
        val totalBytes = totalElements * elementSize

        return TensorMetadata(
            shape = shape,
            dataType = dataType,
            layout = layout,
            elementSize = elementSize,
            totalElements = totalElements,
            totalBytes = totalBytes
        )
    }

    /**
     * Allocate tensor buffer with proper alignment
     */
    fun allocateTensorBuffer(metadata: TensorMetadata, alignment: Int = 32): ByteBuffer {
        // Add padding for alignment
        val paddedSize = ((metadata.totalBytes + alignment - 1) / alignment) * alignment
        return ByteBuffer.allocateDirect(paddedSize)
    }

    // Native methods for tensor operations
    external fun nativeTransposeTensor(
        input: ByteBuffer,
        output: ByteBuffer,
        shape: IntArray,
        permutation: IntArray
    ): Boolean

    external fun nativeReshapeTensor(
        input: ByteBuffer,
        output: ByteBuffer,
        oldShape: IntArray,
        newShape: IntArray
    ): Boolean

    external fun nativeQuantizeTensor(
        input: ByteBuffer,
        output: ByteBuffer,
        scale: Float,
        zeroPoint: Int,
        inputType: Int,
        outputType: Int
    ): Boolean

    init {
        try {
            System.loadLibrary("tensor-utils")
            Log.d(TAG, "Native tensor utils library loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "Native tensor utils library not available")
        }
    }
}

/**
 * Tensor data types
 */
enum class TensorDataType {
    FLOAT32,
    FLOAT16,
    INT32,
    INT8,
    UINT8
}

/**
 * Tensor memory layout
 */
enum class TensorLayout {
    NCHW,  // Batch, Channel, Height, Width
    NHWC,  // Batch, Height, Width, Channel
    NC,    // Batch, Channel
    CHW,   // Channel, Height, Width
    HWC    // Height, Width, Channel
}

/**
 * Tensor metadata
 */
data class TensorMetadata(
    val shape: IntArray,
    val dataType: TensorDataType,
    val layout: TensorLayout,
    val elementSize: Int,
    val totalElements: Int,
    val totalBytes: Int
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as TensorMetadata

        if (!shape.contentEquals(other.shape)) return false
        if (dataType != other.dataType) return false
        if (layout != other.layout) return false
        if (elementSize != other.elementSize) return false
        if (totalElements != other.totalElements) return false
        if (totalBytes != other.totalBytes) return false

        return true
    }

    override fun hashCode(): Int {
        var result = shape.contentHashCode()
        result = 31 * result + dataType.hashCode()
        result = 31 * result + layout.hashCode()
        result = 31 * result + elementSize
        result = 31 * result + totalElements
        result = 31 * result + totalBytes
        return result
    }
}
