package com.runanywhere.runanywhereai.npu

import android.content.Context
import android.content.res.AssetManager
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

/**
 * Kokoro TTS NPU Loader using TFLite + QNN Delegate
 *
 * This is a QUICK VERIFICATION class to test if LiteRT + QNN works on Samsung S25.
 *
 * Phase 1 (NOW): Verify NPU execution works
 * Phase 2 (LATER): Refactor to C++ backend matching platform TTS/LLM architecture
 */
class KokoroTFLiteNPU(private val context: Context) {

    companion object {
        private const val TAG = "KokoroTFLiteNPU"
        private const val MAX_AUDIO_LENGTH = 22050  // 1 second at 22050 Hz (matches test model)
        private const val INPUT_SIZE = 50  // Token input size (matches test model)
        private const val TEST_MODEL_ASSET = "test_npu_model.tflite"  // Float32 model
        private const val TEST_MODEL_INT8_ASSET = "test_npu_model_int8.tflite"  // INT8 quantized model (for NPU)

        // Benchmark configuration - configurable
        private const val WARMUP_RUNS = 5
        private const val BENCHMARK_RUNS = 50  // More runs for accurate timing

        /**
         * Comprehensive benchmark: Compare CPU, GPU, and NNAPI (int8 for NPU)
         * Uses nanosecond precision for accurate sub-millisecond timing
         */
        fun runComprehensiveBenchmark(context: Context): BenchmarkResult {
            Log.i(TAG, "")
            Log.i(TAG, "╔══════════════════════════════════════════════════════════════╗")
            Log.i(TAG, "║        COMPREHENSIVE NPU BENCHMARK - HIGH PRECISION          ║")
            Log.i(TAG, "╠══════════════════════════════════════════════════════════════╣")
            Log.i(TAG, "║  Testing: CPU (XNNPACK), GPU, NNAPI F32, NNAPI INT8 (NPU)   ║")
            Log.i(TAG, "║  Config: $WARMUP_RUNS warmup runs, $BENCHMARK_RUNS benchmark runs               ║")
            Log.i(TAG, "║  Timing: Nanosecond precision (System.nanoTime)             ║")
            Log.i(TAG, "╚══════════════════════════════════════════════════════════════╝")
            Log.i(TAG, "")

            // Get device info
            val deviceName = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"
            val chipset = android.os.Build.HARDWARE
            Log.i(TAG, "Device: $deviceName")
            Log.i(TAG, "Hardware: $chipset")
            Log.i(TAG, "SDK: ${android.os.Build.VERSION.SDK_INT}")
            Log.i(TAG, "")

            val results = mutableMapOf<String, SingleBenchmark>()

            // Test 1: CPU with XNNPACK (float32 model)
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            Log.i(TAG, "  TEST 1/4: CPU (XNNPACK) - Float32 Model")
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            results["CPU"] = runSingleBenchmark(context, TEST_MODEL_ASSET, "cpu", isInt8 = false)

            // Test 2: GPU Delegate (float32 model)
            Log.i(TAG, "")
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            Log.i(TAG, "  TEST 2/4: GPU Delegate (OpenGL/OpenCL) - Float32 Model")
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            results["GPU"] = runSingleBenchmark(context, TEST_MODEL_ASSET, "gpu", isInt8 = false)

            // Test 3: NNAPI with float32 (will likely use GPU/CPU)
            Log.i(TAG, "")
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            Log.i(TAG, "  TEST 3/4: NNAPI (Float32) - Uses GPU/CPU internally")
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            results["NNAPI_F32"] = runSingleBenchmark(context, TEST_MODEL_ASSET, "nnapi", isInt8 = false)

            // Test 4: NNAPI with int8 (will use NPU!)
            Log.i(TAG, "")
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            Log.i(TAG, "  TEST 4/4: NNAPI (INT8) - Should use NPU/DSP!")
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            results["NNAPI_INT8"] = runSingleBenchmark(context, TEST_MODEL_INT8_ASSET, "nnapi", isInt8 = true)

            // Build detailed summary
            Log.i(TAG, "")
            Log.i(TAG, "╔══════════════════════════════════════════════════════════════╗")
            Log.i(TAG, "║                    BENCHMARK SUMMARY                         ║")
            Log.i(TAG, "╚══════════════════════════════════════════════════════════════╝")

            val summary = StringBuilder()
            summary.appendLine("=== NPU Benchmark Results ===")
            summary.appendLine("Device: $deviceName")
            summary.appendLine("Hardware: $chipset")
            summary.appendLine("")
            summary.appendLine("Configuration:")
            summary.appendLine("  - Warmup runs: $WARMUP_RUNS")
            summary.appendLine("  - Benchmark runs: $BENCHMARK_RUNS")
            summary.appendLine("  - Float32 model: $TEST_MODEL_ASSET")
            summary.appendLine("  - INT8 model: $TEST_MODEL_INT8_ASSET")
            summary.appendLine("")
            summary.appendLine("Results:")

            // Log detailed results
            for ((name, bench) in results) {
                val status = if (bench.success) "✅" else "❌"
                Log.i(TAG, "")
                Log.i(TAG, "$status $name:")
                if (bench.success) {
                    Log.i(TAG, "   Load Time:        ${bench.loadTimeMs} ms")
                    Log.i(TAG, "   Avg Inference:    ${bench.inferenceTimeMs} ms")
                    Log.i(TAG, "   Inference (µs):   ${bench.inferenceTimeMicros} µs")
                    Log.i(TAG, "   Min Inference:    ${bench.minInferenceMicros} µs")
                    Log.i(TAG, "   Max Inference:    ${bench.maxInferenceMicros} µs")
                    Log.i(TAG, "   Total Time:       ${bench.totalTimeMs} ms ($BENCHMARK_RUNS runs)")

                    summary.appendLine("$status $name:")
                    summary.appendLine("   Load: ${bench.loadTimeMs}ms")
                    summary.appendLine("   Inference: ${bench.inferenceTimeMicros}µs avg (min: ${bench.minInferenceMicros}µs, max: ${bench.maxInferenceMicros}µs)")
                } else {
                    Log.e(TAG, "   Error: ${bench.error}")
                    summary.appendLine("$status $name: FAILED - ${bench.error?.take(50)}")
                }
            }

            // Find fastest based on inference time (use micros for precision)
            val successfulTests = results.filter { it.value.success }
            if (successfulTests.isNotEmpty()) {
                val fastestInference = successfulTests.minByOrNull { it.value.inferenceTimeMicros }
                val fastestLoad = successfulTests.minByOrNull { it.value.loadTimeMs }

                Log.i(TAG, "")
                Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                Log.i(TAG, "🏆 WINNERS:")
                Log.i(TAG, "   Fastest Inference: ${fastestInference?.key} (${fastestInference?.value?.inferenceTimeMicros}µs)")
                Log.i(TAG, "   Fastest Load:      ${fastestLoad?.key} (${fastestLoad?.value?.loadTimeMs}ms)")
                Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                summary.appendLine("")
                summary.appendLine("🏆 Fastest Inference: ${fastestInference?.key} (${fastestInference?.value?.inferenceTimeMicros}µs)")
                summary.appendLine("🏆 Fastest Load: ${fastestLoad?.key} (${fastestLoad?.value?.loadTimeMs}ms)")
            }

            Log.i(TAG, "")

            return BenchmarkResult(
                cpu = results["CPU"] ?: SingleBenchmark(false, 0, 0, 0, 0, 0, 0, "Not run"),
                gpu = results["GPU"] ?: SingleBenchmark(false, 0, 0, 0, 0, 0, 0, "Not run"),
                nnapiFloat = results["NNAPI_F32"] ?: SingleBenchmark(false, 0, 0, 0, 0, 0, 0, "Not run"),
                nnapiInt8 = results["NNAPI_INT8"] ?: SingleBenchmark(false, 0, 0, 0, 0, 0, 0, "Not run"),
                summary = summary.toString()
            )
        }

        private fun runSingleBenchmark(
            context: Context,
            modelAsset: String,
            backend: String,
            isInt8: Boolean
        ): SingleBenchmark {
            try {
                val loader = KokoroTFLiteNPU(context)

                // Load model with specified backend (use nanoTime for precision)
                Log.i(TAG, "  Loading model: $modelAsset")
                val loadStartNano = System.nanoTime()
                val loadSuccess = when (backend) {
                    "cpu" -> loader.loadModelFromAssetsWithCPU(modelAsset)
                    "gpu" -> loader.loadModelFromAssetsWithGPU(modelAsset)
                    "nnapi" -> loader.loadModelFromAssetsWithNNAPI(modelAsset)
                    else -> false
                }
                val loadTimeNano = System.nanoTime() - loadStartNano
                val loadTimeMs = loadTimeNano / 1_000_000  // Convert to ms

                if (!loadSuccess) {
                    loader.close()
                    Log.e(TAG, "  ❌ Failed to load model")
                    return SingleBenchmark(false, loadTimeMs, 0, 0, 0, 0, 0, "Failed to load model")
                }

                Log.i(TAG, "  ✓ Model loaded in ${loadTimeMs}ms")
                Log.i(TAG, "  Running $WARMUP_RUNS warmup + $BENCHMARK_RUNS benchmark iterations...")

                // Prepare input based on model type
                val inputData: Any = if (isInt8) {
                    ByteArray(INPUT_SIZE) { ((it % 100) - 50).toByte() }
                } else {
                    FloatArray(INPUT_SIZE) { (it % 100).toFloat() / 100f }
                }

                // Warmup runs (don't time these)
                for (i in 0 until WARMUP_RUNS) {
                    if (isInt8) {
                        loader.runInferenceInt8Silent(inputData as ByteArray)
                    } else {
                        loader.runInferenceSilent(inputData as FloatArray)
                    }
                }
                Log.i(TAG, "  ✓ Warmup complete")

                // Benchmark runs with individual timing
                val inferenceTimesNano = LongArray(BENCHMARK_RUNS)

                for (i in 0 until BENCHMARK_RUNS) {
                    val startNano = System.nanoTime()
                    if (isInt8) {
                        loader.runInferenceInt8Silent(inputData as ByteArray)
                    } else {
                        loader.runInferenceSilent(inputData as FloatArray)
                    }
                    inferenceTimesNano[i] = System.nanoTime() - startNano
                }

                // Calculate statistics
                val totalInferenceNano = inferenceTimesNano.sum()
                val avgInferenceNano = totalInferenceNano / BENCHMARK_RUNS
                val minInferenceNano = inferenceTimesNano.minOrNull() ?: 0
                val maxInferenceNano = inferenceTimesNano.maxOrNull() ?: 0

                // Convert to different units
                val avgInferenceMs = avgInferenceNano / 1_000_000
                val avgInferenceMicros = avgInferenceNano / 1_000
                val minInferenceMicros = minInferenceNano / 1_000
                val maxInferenceMicros = maxInferenceNano / 1_000
                val totalTimeMs = (loadTimeNano + totalInferenceNano) / 1_000_000

                loader.close()

                Log.i(TAG, "  ✓ Benchmark complete:")
                Log.i(TAG, "    - Load: ${loadTimeMs}ms")
                Log.i(TAG, "    - Avg inference: ${avgInferenceMicros}µs (${avgInferenceMs}ms)")
                Log.i(TAG, "    - Min: ${minInferenceMicros}µs, Max: ${maxInferenceMicros}µs")

                return SingleBenchmark(
                    success = true,
                    loadTimeMs = loadTimeMs,
                    inferenceTimeMs = avgInferenceMs,
                    inferenceTimeMicros = avgInferenceMicros,
                    minInferenceMicros = minInferenceMicros,
                    maxInferenceMicros = maxInferenceMicros,
                    totalTimeMs = totalTimeMs,
                    error = null
                )

            } catch (e: Exception) {
                Log.e(TAG, "  ❌ Benchmark failed: ${e.message}")
                return SingleBenchmark(false, 0, 0, 0, 0, 0, 0, e.message)
            }
        }

        /**
         * Quick test to verify QNN delegate can be loaded on this device.
         * Call this to check NPU availability without loading a model.
         */
        fun testQNNAvailability(context: Context): QNNTestResult {
            Log.i(TAG, "=== Testing QNN Delegate Availability ===")

            try {
                // Try to load QnnDelegate class
                val qnnDelegateClass = Class.forName("com.qualcomm.qti.QnnDelegate")
                Log.i(TAG, "✅ QnnDelegate class found")

                // Try to load Options class
                val optionsClass = Class.forName("com.qualcomm.qti.QnnDelegate\$Options")
                Log.i(TAG, "✅ QnnDelegate.Options class found")

                // Try to create Options
                val options = optionsClass.getDeclaredConstructor().newInstance()
                Log.i(TAG, "✅ QnnDelegate.Options created")

                // Try to set backend type to HTP (NPU)
                val backendTypeClass = Class.forName("com.qualcomm.qti.QnnDelegate\$Options\$BackendType")
                val htpBackend = backendTypeClass.getField("HTP_BACKEND").get(null)
                val setBackendTypeMethod = optionsClass.getMethod("setBackendType", backendTypeClass)
                setBackendTypeMethod.invoke(options, htpBackend)
                Log.i(TAG, "✅ HTP backend type set")

                // Set skel library directory
                val setSkelLibraryDirMethod = optionsClass.getMethod("setSkelLibraryDir", String::class.java)
                setSkelLibraryDirMethod.invoke(options, context.applicationInfo.nativeLibraryDir)
                Log.i(TAG, "✅ Skel library dir set: ${context.applicationInfo.nativeLibraryDir}")

                // Try to create QnnDelegate instance
                val delegate = qnnDelegateClass.getDeclaredConstructor(optionsClass).newInstance(options)
                Log.i(TAG, "✅ QnnDelegate instance created!")

                // Try to close it
                try {
                    val closeMethod = delegate.javaClass.getMethod("close")
                    closeMethod.invoke(delegate)
                    Log.i(TAG, "✅ QnnDelegate closed successfully")
                } catch (e: Exception) {
                    Log.w(TAG, "Could not close delegate: ${e.message}")
                }

                return QNNTestResult(
                    success = true,
                    message = "QNN Delegate initialized successfully! NPU acceleration available.",
                    error = null
                )

            } catch (e: ClassNotFoundException) {
                val msg = "QNN delegate classes not found. AAR not included?"
                Log.e(TAG, "❌ $msg: ${e.message}")
                return QNNTestResult(success = false, message = msg, error = e.message)

            } catch (e: Exception) {
                val msg = "QNN delegate initialization failed"
                Log.e(TAG, "❌ $msg: ${e.message}", e)
                return QNNTestResult(success = false, message = msg, error = e.message)
            }
        }

        /**
         * Full NPU test: Load model from assets and run inference
         */
        fun runNPUInferenceTest(context: Context): NPUInferenceTestResult {
            Log.i(TAG, "=== Running Full NPU Inference Test (QNN) ===")

            val loader = KokoroTFLiteNPU(context)

            try {
                // Step 1: Load model with QNN delegate
                Log.i(TAG, "Step 1: Loading model from assets with QNN delegate...")
                val loadStart = System.currentTimeMillis()
                val loadSuccess = loader.loadModelFromAssets(TEST_MODEL_ASSET, useNpu = true)
                val loadTime = System.currentTimeMillis() - loadStart

                if (!loadSuccess) {
                    return NPUInferenceTestResult(
                        success = false,
                        npuEnabled = false,
                        backend = "NONE",
                        loadTimeMs = loadTime,
                        inferenceTimeMs = 0,
                        message = "Failed to load model",
                        error = "Model loading failed"
                    )
                }

                val backend = loader.getCurrentBackend()
                Log.i(TAG, "✅ Model loaded in ${loadTime}ms (Backend: $backend)")

                // Step 2: Run inference
                Log.i(TAG, "Step 2: Running inference...")
                val inputFeatures = FloatArray(INPUT_SIZE) { (it % 100).toFloat() / 100f }

                val inferenceStart = System.currentTimeMillis()
                val output = loader.runInference(inputFeatures)
                val inferenceTime = System.currentTimeMillis() - inferenceStart

                if (output == null) {
                    return NPUInferenceTestResult(
                        success = false,
                        npuEnabled = loader.isNPUEnabled(),
                        backend = backend,
                        loadTimeMs = loadTime,
                        inferenceTimeMs = inferenceTime,
                        message = "Inference failed",
                        error = "Output was null"
                    )
                }

                Log.i(TAG, "✅ Inference completed in ${inferenceTime}ms")
                Log.i(TAG, "   Output size: ${output.size} samples")
                Log.i(TAG, "   First 5 values: ${output.take(5)}")

                // Cleanup
                loader.close()

                return NPUInferenceTestResult(
                    success = true,
                    npuEnabled = loader.isNPUEnabled(),
                    backend = backend,
                    loadTimeMs = loadTime,
                    inferenceTimeMs = inferenceTime,
                    message = "✅ QNN Test: $backend\nLoad: ${loadTime}ms, Inference: ${inferenceTime}ms",
                    error = null
                )

            } catch (e: Exception) {
                Log.e(TAG, "❌ QNN test failed: ${e.message}", e)
                loader.close()
                return NPUInferenceTestResult(
                    success = false,
                    npuEnabled = false,
                    backend = "ERROR",
                    loadTimeMs = 0,
                    inferenceTimeMs = 0,
                    message = "QNN Test failed: ${e.message}",
                    error = e.stackTraceToString()
                )
            }
        }

        /**
         * Test NNAPI delegate availability - this uses Android HAL and should work
         * without the libcdsprpc.so sandbox issues
         */
        fun testNNAPIAvailability(context: Context): QNNTestResult {
        Log.i(TAG, "=== Testing NNAPI Delegate Availability ===")

        try {
            // Try to load NnApiDelegate class
            val nnApiDelegateClass = Class.forName("org.tensorflow.lite.nnapi.NnApiDelegate")
            Log.i(TAG, "✅ NnApiDelegate class found")

            // Try to create NnApiDelegate instance (no options needed for basic test)
            val delegate = nnApiDelegateClass.getDeclaredConstructor().newInstance()
            Log.i(TAG, "✅ NnApiDelegate instance created!")

            // Check if NNAPI is available on this device
            try {
                val getNnApiErrnoMethod = delegate.javaClass.getMethod("getNnApiErrno")
                val errno = getNnApiErrnoMethod.invoke(delegate) as Int
                Log.i(TAG, "   NNAPI errno: $errno (0 = success)")
            } catch (e: Exception) {
                Log.w(TAG, "   Could not check NNAPI errno: ${e.message}")
            }

            // Try to close it
            try {
                val closeMethod = delegate.javaClass.getMethod("close")
                closeMethod.invoke(delegate)
                Log.i(TAG, "✅ NnApiDelegate closed successfully")
            } catch (e: Exception) {
                Log.w(TAG, "Could not close delegate: ${e.message}")
            }

            return QNNTestResult(
                success = true,
                message = "NNAPI Delegate available! Hardware acceleration possible via Android HAL.",
                error = null
            )

        } catch (e: ClassNotFoundException) {
            val msg = "NnApiDelegate class not found - add tensorflow-lite-select-tf-ops or ensure NNAPI support"
            Log.e(TAG, "❌ $msg")
            return QNNTestResult(success = false, message = msg, error = e.message)
        } catch (e: Exception) {
            val msg = "NNAPI delegate test failed: ${e.message}"
            Log.e(TAG, "❌ $msg", e)
            return QNNTestResult(success = false, message = msg, error = e.message)
        }
    }

    /**
     * Run inference test with NNAPI delegate
     * NNAPI uses Android HAL layer, so it should work without sandbox issues
     * Note: For true NPU acceleration, model should be int8 quantized
     */
    fun runNNAPIInferenceTest(context: Context): NPUInferenceTestResult {
        Log.i(TAG, "=== Running NNAPI Inference Test ===")
        Log.i(TAG, "Note: NNAPI routes to NPU only with int8 quantized models")
        Log.i(TAG, "      Float models will use GPU or CPU")

        val loader = KokoroTFLiteNPU(context)

        try {
            // Step 1: Load model with NNAPI delegate
            Log.i(TAG, "Step 1: Loading model from assets with NNAPI delegate...")
            val loadStart = System.currentTimeMillis()
            val loadSuccess = loader.loadModelFromAssetsWithNNAPI(TEST_MODEL_ASSET)
            val loadTime = System.currentTimeMillis() - loadStart

            if (!loadSuccess) {
                return NPUInferenceTestResult(
                    success = false,
                    npuEnabled = false,
                    backend = "NONE",
                    loadTimeMs = loadTime,
                    inferenceTimeMs = 0,
                    message = "Failed to load model with NNAPI",
                    error = "Model loading failed"
                )
            }

            val backend = if (loader.isNNAPIEnabled()) "NNAPI" else "CPU"
            Log.i(TAG, "✅ Model loaded in ${loadTime}ms (Backend: $backend)")

            // Step 2: Run inference
            Log.i(TAG, "Step 2: Running inference...")
            val inputFeatures = FloatArray(INPUT_SIZE) { (it % 100).toFloat() / 100f }

            val inferenceStart = System.currentTimeMillis()
            val output = loader.runInference(inputFeatures)
            val inferenceTime = System.currentTimeMillis() - inferenceStart

            if (output == null) {
                return NPUInferenceTestResult(
                    success = false,
                    npuEnabled = loader.isNNAPIEnabled(),
                    backend = backend,
                    loadTimeMs = loadTime,
                    inferenceTimeMs = inferenceTime,
                    message = "Inference failed",
                    error = "Output was null"
                )
            }

            Log.i(TAG, "✅ Inference completed in ${inferenceTime}ms")
            Log.i(TAG, "   Output size: ${output.size} samples")
            Log.i(TAG, "   First 5 values: ${output.take(5)}")

            // Cleanup
            loader.close()

            return NPUInferenceTestResult(
                success = true,
                npuEnabled = loader.isNNAPIEnabled(),
                backend = backend,
                loadTimeMs = loadTime,
                inferenceTimeMs = inferenceTime,
                message = "✅ NNAPI Test Success!\nBackend: $backend\nLoad: ${loadTime}ms, Inference: ${inferenceTime}ms\n(Note: Float model may use GPU/CPU, int8 needed for NPU)",
                error = null
            )

        } catch (e: Exception) {
            Log.e(TAG, "❌ NNAPI test failed: ${e.message}", e)
            loader.close()
            return NPUInferenceTestResult(
                success = false,
                npuEnabled = false,
                backend = "ERROR",
                loadTimeMs = 0,
                inferenceTimeMs = 0,
                message = "NNAPI test failed: ${e.message}",
                error = e.stackTraceToString()
            )
        }
    }

    // Data classes for test results
    data class QNNTestResult(
        val success: Boolean,
        val message: String,
        val error: String?
    )

    data class NPUInferenceTestResult(
        val success: Boolean,
        val npuEnabled: Boolean,
        val backend: String,  // "QNN_HTP", "NNAPI", "GPU", "CPU"
        val loadTimeMs: Long,
        val inferenceTimeMs: Long,
        val message: String,
        val error: String?
    )

    data class SingleBenchmark(
        val success: Boolean,
        val loadTimeMs: Long,
        val inferenceTimeMs: Long,
        val inferenceTimeMicros: Long,  // Microsecond precision
        val minInferenceMicros: Long,   // Min across all runs
        val maxInferenceMicros: Long,   // Max across all runs
        val totalTimeMs: Long,          // Load + all inferences
        val error: String?
    )

    data class BenchmarkResult(
        val cpu: SingleBenchmark,
        val gpu: SingleBenchmark,
        val nnapiFloat: SingleBenchmark,
        val nnapiInt8: SingleBenchmark,
        val summary: String
    )
    }  // End of companion object

    private var interpreter: Interpreter? = null
    private var qnnDelegate: Any? = null  // QnnDelegate (loaded via reflection to handle missing dependency)
    private var nnApiDelegate: Any? = null  // NnApiDelegate (loaded via reflection)
    private var isNpuEnabled = false
    private var isNnApiEnabled = false
    private var currentBackend = "NONE"

    /**
     * Load the TFLite model with QNN delegate for NPU acceleration
     */
    fun loadModel(tfliteModelPath: String): Boolean {
        try {
            Log.i(TAG, "Loading TFLite model: $tfliteModelPath")

            val modelFile = File(tfliteModelPath)
            if (!modelFile.exists()) {
                Log.e(TAG, "Model file not found: $tfliteModelPath")
                return false
            }

            val modelBuffer = loadModelFile(modelFile)

            // Try to load with QNN delegate first
            isNpuEnabled = tryLoadWithQNN(modelBuffer)

            if (!isNpuEnabled) {
                // Fallback to CPU
                Log.w(TAG, "QNN delegate not available, falling back to CPU")
                val options = Interpreter.Options().apply {
                    setNumThreads(4)
                }
                interpreter = Interpreter(modelBuffer, options)
            }

            // Log input/output details
            logModelDetails()

            Log.i(TAG, "Model loaded successfully. NPU enabled: $isNpuEnabled")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Failed to load model: ${e.message}", e)
            return false
        }
    }

    /**
     * Load model from APK assets folder
     */
    fun loadModelFromAssets(assetName: String, useNpu: Boolean = true): Boolean {
        try {
            Log.i(TAG, "Loading model from assets: $assetName")

            // Copy asset to cache directory (TFLite needs a file path or ByteBuffer)
            val assetManager = context.assets
            val inputStream = assetManager.open(assetName)
            val modelBytes = inputStream.readBytes()
            inputStream.close()

            Log.i(TAG, "Model size: ${modelBytes.size / 1024} KB")

            // Create ByteBuffer from bytes
            val modelBuffer = ByteBuffer.allocateDirect(modelBytes.size)
            modelBuffer.order(ByteOrder.nativeOrder())
            modelBuffer.put(modelBytes)
            modelBuffer.rewind()

            // Try to load with QNN delegate first
            if (useNpu) {
                isNpuEnabled = tryLoadWithQNNFromBuffer(modelBuffer)
            }

            if (!isNpuEnabled) {
                // Fallback to CPU
                Log.w(TAG, "QNN delegate not available or disabled, using CPU")
                modelBuffer.rewind()  // Reset position
                val options = Interpreter.Options().apply {
                    setNumThreads(4)
                }
                interpreter = Interpreter(modelBuffer, options)
            }

            // Log input/output details
            logModelDetails()

            currentBackend = if (isNpuEnabled) "QNN_HTP" else "CPU"
            Log.i(TAG, "✅ Model loaded successfully. NPU enabled: $isNpuEnabled, Backend: $currentBackend")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Failed to load model from assets: ${e.message}", e)
            return false
        }
    }

    /**
     * Load model from APK assets folder with NNAPI delegate
     * NNAPI uses Android HAL layer, avoiding sandbox issues
     */
    fun loadModelFromAssetsWithNNAPI(assetName: String): Boolean {
        try {
            Log.i(TAG, "Loading model from assets with NNAPI: $assetName")

            // Copy asset to cache directory
            val assetManager = context.assets
            val inputStream = assetManager.open(assetName)
            val modelBytes = inputStream.readBytes()
            inputStream.close()

            Log.i(TAG, "Model size: ${modelBytes.size / 1024} KB")

            // Create ByteBuffer from bytes
            val modelBuffer = ByteBuffer.allocateDirect(modelBytes.size)
            modelBuffer.order(ByteOrder.nativeOrder())
            modelBuffer.put(modelBytes)
            modelBuffer.rewind()

            // Try to load with NNAPI delegate
            isNnApiEnabled = tryLoadWithNNAPI(modelBuffer)

            if (!isNnApiEnabled) {
                // Fallback to CPU
                Log.w(TAG, "NNAPI delegate not available, using CPU")
                modelBuffer.rewind()
                val options = Interpreter.Options().apply {
                    setNumThreads(4)
                }
                interpreter = Interpreter(modelBuffer, options)
                currentBackend = "CPU"
            } else {
                currentBackend = "NNAPI"
            }

            // Log input/output details
            logModelDetails()

            Log.i(TAG, "✅ Model loaded successfully. NNAPI enabled: $isNnApiEnabled, Backend: $currentBackend")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Failed to load model from assets with NNAPI: ${e.message}", e)
            return false
        }
    }

    /**
     * Load model with CPU only (XNNPACK delegate)
     */
    fun loadModelFromAssetsWithCPU(assetName: String): Boolean {
        try {
            Log.i(TAG, "Loading model from assets with CPU: $assetName")

            val assetManager = context.assets
            val inputStream = assetManager.open(assetName)
            val modelBytes = inputStream.readBytes()
            inputStream.close()

            Log.i(TAG, "Model size: ${modelBytes.size / 1024} KB")

            val modelBuffer = ByteBuffer.allocateDirect(modelBytes.size)
            modelBuffer.order(ByteOrder.nativeOrder())
            modelBuffer.put(modelBytes)
            modelBuffer.rewind()

            // CPU only with XNNPACK
            val options = Interpreter.Options().apply {
                setNumThreads(4)
            }
            interpreter = Interpreter(modelBuffer, options)
            currentBackend = "CPU"
            isNpuEnabled = false
            isNnApiEnabled = false

            logModelDetails()
            Log.i(TAG, "✅ Model loaded with CPU (XNNPACK)")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Failed to load model with CPU: ${e.message}", e)
            return false
        }
    }

    /**
     * Load model with GPU delegate
     */
    fun loadModelFromAssetsWithGPU(assetName: String): Boolean {
        try {
            Log.i(TAG, "Loading model from assets with GPU: $assetName")

            val assetManager = context.assets
            val inputStream = assetManager.open(assetName)
            val modelBytes = inputStream.readBytes()
            inputStream.close()

            Log.i(TAG, "Model size: ${modelBytes.size / 1024} KB")

            val modelBuffer = ByteBuffer.allocateDirect(modelBytes.size)
            modelBuffer.order(ByteOrder.nativeOrder())
            modelBuffer.put(modelBytes)
            modelBuffer.rewind()

            // Try to load GPU delegate via reflection
            try {
                val gpuDelegateClass = Class.forName("org.tensorflow.lite.gpu.GpuDelegate")
                val gpuDelegate = gpuDelegateClass.getDeclaredConstructor().newInstance()

                val options = Interpreter.Options().apply {
                    setNumThreads(4)
                }

                val addDelegateMethod = Interpreter.Options::class.java.getMethod(
                    "addDelegate",
                    org.tensorflow.lite.Delegate::class.java
                )
                addDelegateMethod.invoke(options, gpuDelegate as org.tensorflow.lite.Delegate)

                interpreter = Interpreter(modelBuffer, options)
                currentBackend = "GPU"
                isNpuEnabled = false
                isNnApiEnabled = false

                logModelDetails()
                Log.i(TAG, "✅ Model loaded with GPU delegate")
                return true

            } catch (e: ClassNotFoundException) {
                Log.w(TAG, "GPU delegate not available, falling back to CPU")
                modelBuffer.rewind()
                return loadModelFromAssetsWithCPU(assetName)
            } catch (e: Exception) {
                Log.w(TAG, "GPU delegate failed: ${e.message}, falling back to CPU")
                modelBuffer.rewind()
                val options = Interpreter.Options().apply { setNumThreads(4) }
                interpreter = Interpreter(modelBuffer, options)
                currentBackend = "CPU"
                return true
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to load model with GPU: ${e.message}", e)
            return false
        }
    }

    /**
     * Run inference with int8 input (for quantized models)
     */
    fun runInferenceInt8(inputFeatures: ByteArray): ByteArray? {
        val interp = interpreter ?: run {
            Log.e(TAG, "Model not loaded - cannot run int8 inference")
            throw IllegalStateException("Model not loaded")
        }

        try {
            // Prepare input - shape [1, INPUT_SIZE] int8
            val input = Array(1) { inputFeatures }

            // Prepare output - shape [1, MAX_AUDIO_LENGTH] int8
            val output = Array(1) { ByteArray(MAX_AUDIO_LENGTH) }

            Log.i(TAG, "Running int8 inference with input shape: [1, ${inputFeatures.size}]")

            interp.run(input, output)

            Log.i(TAG, "Int8 inference output shape: [1, ${output[0].size}]")

            return output[0]

        } catch (e: Exception) {
            Log.e(TAG, "Int8 inference failed: ${e.message}", e)
            throw e  // Re-throw to signal failure
        }
    }

    /**
     * Silent int8 inference for benchmarking (no logging overhead)
     */
    fun runInferenceInt8Silent(inputFeatures: ByteArray): ByteArray {
        val interp = interpreter ?: throw IllegalStateException("Model not loaded")

        val input = Array(1) { inputFeatures }
        val output = Array(1) { ByteArray(MAX_AUDIO_LENGTH) }

        interp.run(input, output)

        return output[0]
    }

    /**
     * Try to load model with NNAPI delegate
     * NNAPI routes to NPU (for int8 models), GPU, or CPU based on model type and device
     */
    private fun tryLoadWithNNAPI(modelBuffer: ByteBuffer): Boolean {
        try {
            Log.i(TAG, "Attempting to load with NNAPI delegate...")

            // Try to load NnApiDelegate class via reflection
            val nnApiDelegateClass = Class.forName("org.tensorflow.lite.nnapi.NnApiDelegate")

            // Check if there's an Options class for configuration
            try {
                val optionsClass = Class.forName("org.tensorflow.lite.nnapi.NnApiDelegate\$Options")
                val options = optionsClass.getDeclaredConstructor().newInstance()

                // Try to set accelerator name if available (to force NPU)
                try {
                    val setAcceleratorNameMethod = optionsClass.getMethod("setAcceleratorName", String::class.java)
                    // Common NPU accelerator names: "qti-dsp", "qti-htp", "google-edgetpu"
                    // Leave empty to let NNAPI auto-select best accelerator
                    Log.i(TAG, "  NNAPI Options configured")
                } catch (e: Exception) {
                    Log.i(TAG, "  Using default NNAPI options")
                }

                // Create delegate with options
                val delegate = nnApiDelegateClass.getDeclaredConstructor(optionsClass).newInstance(options)
                nnApiDelegate = delegate
                Log.i(TAG, "  NNAPI delegate created with options")

                // Create interpreter with NNAPI delegate
                val interpreterOptions = Interpreter.Options().apply {
                    setNumThreads(4)
                }

                val addDelegateMethod = Interpreter.Options::class.java.getMethod("addDelegate", org.tensorflow.lite.Delegate::class.java)
                addDelegateMethod.invoke(interpreterOptions, delegate as org.tensorflow.lite.Delegate)

                interpreter = Interpreter(modelBuffer, interpreterOptions)

                Log.i(TAG, "✅ NNAPI delegate loaded successfully!")
                Log.i(TAG, "   Note: Float models use GPU/CPU. Int8 quantized models use NPU.")
                return true

            } catch (e: ClassNotFoundException) {
                // No Options class, try basic constructor
                val delegate = nnApiDelegateClass.getDeclaredConstructor().newInstance()
                nnApiDelegate = delegate
                Log.i(TAG, "  NNAPI delegate created (basic)")

                val interpreterOptions = Interpreter.Options().apply {
                    setNumThreads(4)
                }

                val addDelegateMethod = Interpreter.Options::class.java.getMethod("addDelegate", org.tensorflow.lite.Delegate::class.java)
                addDelegateMethod.invoke(interpreterOptions, delegate as org.tensorflow.lite.Delegate)

                interpreter = Interpreter(modelBuffer, interpreterOptions)

                Log.i(TAG, "✅ NNAPI delegate loaded successfully (basic)!")
                return true
            }

        } catch (e: ClassNotFoundException) {
            Log.w(TAG, "NNAPI delegate classes not found: ${e.message}")
            return false
        } catch (e: Exception) {
            Log.e(TAG, "NNAPI delegate init failed: ${e.message}", e)
            return false
        }
    }

    /**
     * Check if NNAPI is enabled
     */
    fun isNNAPIEnabled(): Boolean = isNnApiEnabled

    /**
     * Get current backend name
     */
    fun getCurrentBackend(): String = currentBackend

    /**
     * Try to load model with QNN delegate from ByteBuffer
     */
    private fun tryLoadWithQNNFromBuffer(modelBuffer: ByteBuffer): Boolean {
        try {
            Log.i(TAG, "Attempting to load with QNN delegate...")

            // Try to load QnnDelegate class via reflection
            val qnnDelegateClass = Class.forName("com.qualcomm.qti.QnnDelegate")
            val optionsClass = Class.forName("com.qualcomm.qti.QnnDelegate\$Options")

            // Create Options
            val options = optionsClass.getDeclaredConstructor().newInstance()

            // Set backend type to HTP (NPU)
            val backendTypeClass = Class.forName("com.qualcomm.qti.QnnDelegate\$Options\$BackendType")
            val htpBackend = backendTypeClass.getField("HTP_BACKEND").get(null)
            val setBackendTypeMethod = optionsClass.getMethod("setBackendType", backendTypeClass)
            setBackendTypeMethod.invoke(options, htpBackend)
            Log.i(TAG, "  HTP backend configured")

            // Set skel library directory
            val setSkelLibraryDirMethod = optionsClass.getMethod("setSkelLibraryDir", String::class.java)
            setSkelLibraryDirMethod.invoke(options, context.applicationInfo.nativeLibraryDir)
            Log.i(TAG, "  Skel dir: ${context.applicationInfo.nativeLibraryDir}")

            // Create QnnDelegate
            val delegate = qnnDelegateClass.getDeclaredConstructor(optionsClass).newInstance(options)
            qnnDelegate = delegate
            Log.i(TAG, "  QNN delegate created")

            // Create interpreter with QNN delegate
            val interpreterOptions = Interpreter.Options().apply {
                setNumThreads(4)
            }

            // Add delegate
            val addDelegateMethod = Interpreter.Options::class.java.getMethod("addDelegate", org.tensorflow.lite.Delegate::class.java)
            addDelegateMethod.invoke(interpreterOptions, delegate as org.tensorflow.lite.Delegate)

            interpreter = Interpreter(modelBuffer, interpreterOptions)

            Log.i(TAG, "✅ QNN delegate loaded - NPU acceleration enabled!")
            return true

        } catch (e: ClassNotFoundException) {
            Log.w(TAG, "QNN delegate classes not found: ${e.message}")
            return false
        } catch (e: Exception) {
            Log.e(TAG, "QNN delegate init failed: ${e.message}", e)
            return false
        }
    }

    /**
     * Run inference with float array input (for test model with float32 input)
     */
    fun runInference(inputFeatures: FloatArray): FloatArray? {
        val interp = interpreter ?: run {
            Log.e(TAG, "Model not loaded - cannot run inference")
            throw IllegalStateException("Model not loaded")
        }

        try {
            // Prepare input - shape [1, INPUT_SIZE] float32
            val input = Array(1) { inputFeatures }

            // Prepare output - shape [1, MAX_AUDIO_LENGTH]
            val output = Array(1) { FloatArray(MAX_AUDIO_LENGTH) }

            Log.i(TAG, "Running inference with input shape: [1, ${inputFeatures.size}]")

            // Run inference
            interp.run(input, output)

            Log.i(TAG, "Inference output shape: [1, ${output[0].size}]")

            return output[0]

        } catch (e: Exception) {
            Log.e(TAG, "Inference failed: ${e.message}", e)
            throw e  // Re-throw to signal failure
        }
    }

    /**
     * Silent inference for benchmarking (no logging overhead)
     */
    fun runInferenceSilent(inputFeatures: FloatArray): FloatArray {
        val interp = interpreter ?: throw IllegalStateException("Model not loaded")

        val input = Array(1) { inputFeatures }
        val output = Array(1) { FloatArray(MAX_AUDIO_LENGTH) }

        interp.run(input, output)

        return output[0]
    }

    /**
     * Check if NPU is enabled
     */
    fun isNPUEnabled(): Boolean = isNpuEnabled

    /**
     * Try to load model with QNN delegate using reflection
     * This allows the code to compile even if QNN delegate isn't available
     */
    private fun tryLoadWithQNN(modelBuffer: MappedByteBuffer): Boolean {
        try {
            // Try to load QnnDelegate class via reflection
            val qnnDelegateClass = Class.forName("com.qualcomm.qti.QnnDelegate")
            val optionsClass = Class.forName("com.qualcomm.qti.QnnDelegate\$Options")

            // Create Options
            val options = optionsClass.getDeclaredConstructor().newInstance()

            // Set backend type to HTP (NPU)
            val backendTypeClass = Class.forName("com.qualcomm.qti.QnnDelegate\$Options\$BackendType")
            val htpBackend = backendTypeClass.getField("HTP_BACKEND").get(null)
            val setBackendTypeMethod = optionsClass.getMethod("setBackendType", backendTypeClass)
            setBackendTypeMethod.invoke(options, htpBackend)

            // Set skel library directory
            val setSkelLibraryDirMethod = optionsClass.getMethod("setSkelLibraryDir", String::class.java)
            setSkelLibraryDirMethod.invoke(options, context.applicationInfo.nativeLibraryDir)

            // Create QnnDelegate
            val delegate = qnnDelegateClass.getDeclaredConstructor(optionsClass).newInstance(options)
            qnnDelegate = delegate

            // Create interpreter with QNN delegate
            val interpreterOptions = Interpreter.Options().apply {
                setNumThreads(4)
            }

            // Add delegate using reflection
            val addDelegateMethod = Interpreter.Options::class.java.getMethod("addDelegate", org.tensorflow.lite.Delegate::class.java)
            addDelegateMethod.invoke(interpreterOptions, delegate as org.tensorflow.lite.Delegate)

            interpreter = Interpreter(modelBuffer, interpreterOptions)

            Log.i(TAG, "✅ QNN delegate loaded successfully - NPU acceleration enabled!")
            return true

        } catch (e: ClassNotFoundException) {
            Log.w(TAG, "QNN delegate classes not found: ${e.message}")
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize QNN delegate: ${e.message}", e)
            return false
        }
    }

    /**
     * Log model input/output details for debugging
     */
    private fun logModelDetails() {
        interpreter?.let { interp ->
            Log.i(TAG, "Model inputs:")
            for (i in 0 until interp.inputTensorCount) {
                val tensor = interp.getInputTensor(i)
                Log.i(TAG, "  [$i] ${tensor.name()}: ${tensor.shape().contentToString()} (${tensor.dataType()})")
            }

            Log.i(TAG, "Model outputs:")
            for (i in 0 until interp.outputTensorCount) {
                val tensor = interp.getOutputTensor(i)
                Log.i(TAG, "  [$i] ${tensor.name()}: ${tensor.shape().contentToString()} (${tensor.dataType()})")
            }
        }
    }

    /**
     * Run inference to synthesize speech
     *
     * @param tokens Input token IDs (phoneme tokens)
     * @param style Style embedding vector
     * @param speed Speech speed multiplier
     * @return Audio samples as FloatArray, or null on error
     */
    fun synthesize(tokens: IntArray, style: FloatArray, speed: Float): FloatArray? {
        val interp = interpreter
        if (interp == null) {
            Log.e(TAG, "Model not loaded")
            return null
        }

        try {
            val startTime = System.currentTimeMillis()

            // Prepare inputs based on model requirements
            // Note: Exact tensor shapes depend on the converted model
            val inputTokens = arrayOf(tokens)
            val inputStyle = arrayOf(style)
            val inputSpeed = arrayOf(floatArrayOf(speed))

            // Prepare output buffer
            // Note: Shape depends on model output
            val outputAudio = Array(1) { FloatArray(MAX_AUDIO_LENGTH) }

            // Run inference
            val inputs = arrayOf<Any>(inputTokens, inputStyle, inputSpeed)
            val outputs = mutableMapOf<Int, Any>(0 to outputAudio)

            interp.runForMultipleInputsOutputs(inputs, outputs)

            val inferenceTime = System.currentTimeMillis() - startTime
            Log.i(TAG, "Inference completed in ${inferenceTime}ms (NPU: $isNpuEnabled)")

            return outputAudio[0]

        } catch (e: Exception) {
            Log.e(TAG, "Inference failed: ${e.message}", e)
            return null
        }
    }

    /**
     * Close and release resources
     */
    fun close() {
        try {
            interpreter?.close()
            interpreter = null

            // Close QNN delegate if it has a close method
            qnnDelegate?.let { delegate ->
                try {
                    val closeMethod = delegate.javaClass.getMethod("close")
                    closeMethod.invoke(delegate)
                } catch (e: Exception) {
                    // Ignore if close method doesn't exist
                }
            }
            qnnDelegate = null
            isNpuEnabled = false

            Log.i(TAG, "Resources released")
        } catch (e: Exception) {
            Log.e(TAG, "Error closing: ${e.message}", e)
        }
    }

    /**
     * Load model file into ByteBuffer
     */
    private fun loadModelFile(file: File): MappedByteBuffer {
        FileInputStream(file).use { fis ->
            val channel = fis.channel
            return channel.map(FileChannel.MapMode.READ_ONLY, 0, channel.size())
        }
    }
}
