# Android Local LLM Implementation Guide

## 🎯 Executive Summary

This comprehensive guide covers all mainstream frameworks and SDKs for running Large Language Models (LLMs) locally on Android devices. Each framework is detailed with installation instructions, Kotlin/Java implementation examples, model management, and performance optimization strategies.

## 📋 Table of Contents

1. [Google Gemini Nano with ML Kit](#1-google-gemini-nano-with-ml-kit)
2. [Android AI Core](#2-android-ai-core)
3. [ONNX Runtime](#3-onnx-runtime)
4. [ExecuTorch](#4-executorch)
5. [MLC-LLM](#5-mlc-llm)
6. [TensorFlow Lite (LiteRT)](#6-tensorflow-lite-litert)
7. [MediaPipe LLM Inference](#7-mediapipe-llm-inference)
8. [llama.cpp (GGUF)](#8-llamacpp-gguf)
9. [picoLLM](#9-picollm)
10. [Native LLM Implementations](#10-native-llm-implementations)
11. [Sample App Architecture](#11-sample-app-architecture)
12. [Model Recommendations](#12-model-recommendations)
13. [Performance Optimization](#13-performance-optimization)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Google Gemini Nano with ML Kit

### Overview
Google's on-device AI solution providing Gemini Nano model through ML Kit APIs, offering privacy-focused, offline-capable generative AI features.

### Requirements
- **Android Version**: 14+ (API level 34+)
- **Devices**: Pixel 8 Pro, Pixel 9 series, Samsung S24 series (expanding)
- **RAM**: 8GB minimum, 12GB recommended
- **Storage**: ~500MB for base model + variants

### Installation

```gradle
// app/build.gradle
dependencies {
    // ML Kit GenAI APIs
    implementation 'com.google.mlkit:genai:1.0.0'
    implementation 'com.google.mlkit:genai-common:1.0.0'

    // Google AI Edge SDK (Direct access)
    implementation 'com.google.ai.edge:genai:1.0.0'

    // For specific APIs
    implementation 'com.google.mlkit:genai-summarization:1.0.0'
    implementation 'com.google.mlkit:genai-proofreading:1.0.0'
    implementation 'com.google.mlkit:genai-rewriting:1.0.0'
    implementation 'com.google.mlkit:genai-image-description:1.0.0'
}
```

### Manifest Configuration

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="com.google.android.gms.permission.GENAI" />

<application>
    <!-- Enable AI Core -->
    <meta-data
        android:name="com.google.android.gms.genai.API_KEY"
        android:value="your_api_key_here" />
</application>
```

### Implementation

#### Summarization API

```kotlin
import com.google.mlkit.genai.summarization.*
import kotlinx.coroutines.tasks.await

class GeminiSummarizer(private val context: Context) {
    private lateinit var summarizer: Summarizer

    suspend fun initialize() {
        val options = SummarizerOptions.builder(context)
            .setInputType(InputType.ARTICLE)
            .setOutputType(OutputType.BULLET_POINTS)
            .setLanguage(Language.ENGLISH)
            .setSummaryLength(SummaryLength.SHORT)
            .build()

        summarizer = Summarization.getClient(options)

        // Check availability and download if needed
        when (val status = summarizer.checkFeatureStatus().await()) {
            FeatureStatus.AVAILABLE -> {
                // Ready to use
                Log.d("Gemini", "Summarizer ready")
            }
            FeatureStatus.DOWNLOADING -> {
                // Model downloading in background
                summarizer.awaitDownload()
                Log.d("Gemini", "Model downloaded")
            }
            FeatureStatus.UNAVAILABLE -> {
                throw Exception("Gemini Nano not supported on this device")
            }
        }
    }

    suspend fun summarize(text: String): String {
        val request = SummarizationRequest.builder(text)
            .setMaxOutputTokens(150)
            .setTemperature(0.7f)
            .build()

        return summarizer.summarize(request).await()
    }

    // Streaming summarization
    fun summarizeStream(
        text: String,
        onUpdate: (String) -> Unit,
        onComplete: () -> Unit,
        onError: (Exception) -> Unit
    ) {
        val request = SummarizationRequest.builder(text)
            .setStreamingEnabled(true)
            .build()

        summarizer.runInference(request)
            .addOnSuccessListener { result ->
                // Handle streaming updates
                result.streamingCallback = { partialResult ->
                    onUpdate(partialResult)
                }
            }
            .addOnCompleteListener {
                onComplete()
            }
            .addOnFailureListener { e ->
                onError(e)
            }
    }
}
```

#### Proofreading API

```kotlin
import com.google.mlkit.genai.proofreading.*

class GeminiProofreader(private val context: Context) {
    private lateinit var proofreader: Proofreader

    suspend fun initialize() {
        val options = ProofreadingOptions.builder(context)
            .setLanguage(Language.ENGLISH)
            .setCorrectionTypes(
                CorrectionType.GRAMMAR,
                CorrectionType.SPELLING,
                CorrectionType.PUNCTUATION,
                CorrectionType.STYLE
            )
            .setSuggestionConfidenceThreshold(0.8f)
            .build()

        proofreader = Proofreading.getClient(options)

        // Wait for model to be ready
        proofreader.awaitDownload()
    }

    suspend fun proofread(text: String, context: String? = null): List<Suggestion> {
        val request = ProofreadingRequest.builder(text)
            .apply {
                context?.let { setContext(it) }
            }
            .build()

        val result = proofreader.proofread(request).await()

        return result.suggestions.map { suggestion ->
            Suggestion(
                type = suggestion.type,
                original = suggestion.original,
                replacement = suggestion.replacement,
                confidence = suggestion.confidence,
                explanation = suggestion.explanation
            )
        }
    }

    // Apply suggestions
    fun applySuggestions(originalText: String, suggestions: List<Suggestion>): String {
        var correctedText = originalText

        // Apply suggestions in reverse order to maintain indices
        suggestions.sortedByDescending { it.startIndex }.forEach { suggestion ->
            correctedText = correctedText.replaceRange(
                suggestion.startIndex,
                suggestion.endIndex,
                suggestion.replacement
            )
        }

        return correctedText
    }
}

data class Suggestion(
    val type: CorrectionType,
    val original: String,
    val replacement: String,
    val confidence: Float,
    val explanation: String?,
    val startIndex: Int = 0,
    val endIndex: Int = 0
)
```

#### Rewriting API

```kotlin
import com.google.mlkit.genai.rewriting.*

class GeminiRewriter(private val context: Context) {
    private lateinit var rewriter: Rewriter

    enum class RewritingStyle {
        FORMAL,      // Professional tone
        CASUAL,      // Conversational tone
        CONCISE,     // Shortened version
        ELABORATE,   // Expanded version
        CREATIVE,    // More creative expression
        SIMPLE,      // Simplified language
        TECHNICAL    // Technical writing
    }

    suspend fun initialize() {
        val options = RewritingOptions.builder(context)
            .setDefaultStyle(RewritingStyle.FORMAL)
            .setPreserveIntent(true)
            .setMaxOutputLength(500)
            .build()

        rewriter = Rewriting.getClient(options)
        await rewriter.checkAndDownloadModel()
    }

    suspend fun rewrite(
        text: String,
        style: RewritingStyle,
        targetAudience: String? = null
    ): String {
        val request = RewritingRequest.builder(text)
            .setStyle(style)
            .apply {
                targetAudience?.let { setTargetAudience(it) }
            }
            .setPreserveKeyInformation(true)
            .build()

        return rewriter.rewrite(request).await()
    }

    // Multiple style variations
    suspend fun generateVariations(text: String): Map<RewritingStyle, String> {
        val variations = mutableMapOf<RewritingStyle, String>()

        RewritingStyle.values().forEach { style ->
            try {
                variations[style] = rewrite(text, style)
            } catch (e: Exception) {
                Log.e("Rewriter", "Failed to generate $style variation", e)
            }
        }

        return variations
    }
}
```

#### Image Description API

```kotlin
import com.google.mlkit.genai.imagedescription.*
import android.graphics.Bitmap

class GeminiImageDescriber(private val context: Context) {
    private lateinit var imageDescriber: ImageDescriber

    suspend fun initialize() {
        val options = ImageDescriptionOptions.builder(context)
            .setDetailLevel(DetailLevel.DETAILED)
            .setFocusAreas(
                FocusArea.OBJECTS,
                FocusArea.TEXT,
                FocusArea.SCENE,
                FocusArea.PEOPLE,
                FocusArea.EMOTIONS
            )
            .setLanguage(Language.ENGLISH)
            .build()

        imageDescriber = ImageDescription.getClient(options)
        await imageDescriber.ensureModelReady()
    }

    suspend fun describeImage(
        bitmap: Bitmap,
        maxWords: Int = 100,
        includeColors: Boolean = true,
        includeEmotions: Boolean = true
    ): ImageDescriptionResult {
        val request = ImageDescriptionRequest.builder(bitmap)
            .setMaxWords(maxWords)
            .setIncludeColors(includeColors)
            .setIncludeEmotions(includeEmotions)
            .setIncludeObjectLocations(true)
            .build()

        val result = imageDescriber.describe(request).await()

        return ImageDescriptionResult(
            description = result.description,
            objects = result.detectedObjects,
            colors = result.dominantColors,
            emotions = result.detectedEmotions,
            text = result.extractedText
        )
    }

    // Describe image from URI
    suspend fun describeImageFromUri(uri: Uri): ImageDescriptionResult {
        val bitmap = MediaStore.Images.Media.getBitmap(
            context.contentResolver,
            uri
        )
        return describeImage(bitmap)
    }
}

data class ImageDescriptionResult(
    val description: String,
    val objects: List<DetectedObject>,
    val colors: List<DominantColor>,
    val emotions: List<DetectedEmotion>,
    val text: String?
)
```

#### Direct Gemini Nano Access (Google AI Edge SDK)

```kotlin
import com.google.ai.edge.genai.*

class GeminiNanoChat(private val context: Context) {
    private lateinit var model: GenerativeModel
    private lateinit var chat: Chat

    suspend fun initialize() {
        // Configure generation parameters
        val config = generationConfig {
            temperature = 0.7f
            topK = 40
            topP = 0.95f
            maxOutputTokens = 256
            stopSequences = listOf("Human:", "AI:")
        }

        // Safety settings
        val safetySettings = listOf(
            SafetySetting(HarmCategory.HARASSMENT, BlockThreshold.MEDIUM_AND_ABOVE),
            SafetySetting(HarmCategory.HATE_SPEECH, BlockThreshold.MEDIUM_AND_ABOVE),
            SafetySetting(HarmCategory.SEXUALLY_EXPLICIT, BlockThreshold.MEDIUM_AND_ABOVE),
            SafetySetting(HarmCategory.DANGEROUS_CONTENT, BlockThreshold.MEDIUM_AND_ABOVE)
        )

        // Initialize model
        model = GenerativeModel(
            modelName = "gemini-nano",
            generationConfig = config,
            safetySettings = safetySettings
        )

        // Check availability
        if (!model.isAvailable()) {
            throw Exception("Gemini Nano not available on this device")
        }
    }

    // Single-turn generation
    suspend fun generate(prompt: String): String {
        val response = model.generateContent(prompt)
        return response.text ?: ""
    }

    // Streaming generation
    fun generateStream(
        prompt: String,
        onToken: (String) -> Unit,
        onComplete: () -> Unit,
        onError: (Exception) -> Unit
    ) {
        lifecycleScope.launch {
            try {
                model.generateContentStream(prompt).collect { chunk ->
                    chunk.text?.let { onToken(it) }
                }
                onComplete()
            } catch (e: Exception) {
                onError(e)
            }
        }
    }

    // Multi-turn chat
    fun startChat(history: List<Content> = emptyList()): Chat {
        chat = model.startChat(history)
        return chat
    }

    suspend fun sendMessage(message: String): String {
        val response = chat.sendMessage(message)
        return response.text ?: ""
    }

    // Multimodal input
    suspend fun analyzeImageWithText(
        bitmap: Bitmap,
        question: String
    ): String {
        val content = content {
            image(bitmap)
            text(question)
        }

        val response = model.generateContent(content)
        return response.text ?: ""
    }

    // Advanced: Function calling
    suspend fun generateWithTools(
        prompt: String,
        tools: List<Tool>
    ): String {
        val request = GenerateContentRequest(
            contents = listOf(content { text(prompt) }),
            tools = tools
        )

        val response = model.generateContent(request)

        // Handle tool calls if any
        response.candidates.firstOrNull()?.let { candidate ->
            candidate.content.parts.forEach { part ->
                when (part) {
                    is FunctionCallPart -> {
                        // Execute function and get result
                        val result = executeFunction(part.name, part.args)
                        // Send result back to model
                        return sendFunctionResponse(part.name, result)
                    }
                }
            }
        }

        return response.text ?: ""
    }
}
```

### Performance and Safety

```kotlin
class GeminiNanoManager {
    companion object {
        // Check device compatibility
        fun isDeviceSupported(context: Context): Boolean {
            val packageManager = context.packageManager
            return packageManager.hasSystemFeature("com.google.android.feature.GEMINI_NANO")
        }

        // Get model info
        suspend fun getModelInfo(context: Context): ModelInfo {
            val aiCore = AICore.getInstance(context)
            return aiCore.getModelInfo("gemini-nano")
        }

        // Monitor resource usage
        fun monitorResourceUsage(context: Context): ResourceMetrics {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)

            return ResourceMetrics(
                availableMemory = memoryInfo.availMem,
                totalMemory = memoryInfo.totalMem,
                lowMemory = memoryInfo.lowMemory,
                cpuUsage = getCpuUsage(),
                temperature = getBatteryTemperature(context)
            )
        }
    }
}
```

---

## 2. Android AI Core

### Overview
System-level AI service managing on-device models, providing automatic updates and resource management.

### Requirements
- **Android Version**: 14+ (API level 34+)
- **System Feature**: com.google.android.feature.AICore
- **Permissions**: System-level permissions

### Implementation

```kotlin
import com.google.android.aicore.*

class AICoreLLMService(private val context: Context) {
    private lateinit var aiCore: AICore
    private var currentModel: AIModel? = null

    suspend fun initialize() {
        aiCore = AICore.getInstance(context)

        // Check if AI Core is available
        if (!aiCore.isAvailable()) {
            throw Exception("AI Core not available on this device")
        }

        // List available models
        val models = aiCore.listAvailableModels()
        models.forEach { model ->
            Log.d("AICore", "Available model: ${model.name} (${model.size})")
        }
    }

    // Download and prepare model
    suspend fun prepareModel(modelName: String) {
        val downloadRequest = ModelDownloadRequest.builder()
            .setModelName(modelName)
            .setPriority(DownloadPriority.HIGH)
            .setWifiRequired(false)
            .build()

        aiCore.downloadModel(downloadRequest) { progress ->
            Log.d("AICore", "Download progress: ${progress.percentComplete}%")
        }.await()

        currentModel = aiCore.loadModel(modelName)
    }

    // Run inference
    suspend fun generate(prompt: String, maxTokens: Int = 150): String {
        val model = currentModel ?: throw Exception("Model not loaded")

        val request = InferenceRequest.builder()
            .setInput(prompt)
            .setMaxOutputTokens(maxTokens)
            .setTemperature(0.7f)
            .build()

        val response = model.runInference(request).await()
        return response.text
    }

    // Model management
    suspend fun deleteModel(modelName: String) {
        aiCore.deleteModel(modelName)
    }

    fun getModelStorageInfo(): StorageInfo {
        return aiCore.getStorageInfo()
    }
}
```

---

## 3. ONNX Runtime

### Overview
Microsoft's cross-platform inference framework supporting models from multiple ML frameworks with Android-optimized execution providers.

### Requirements
- **Android Version**: API level 19+ (Android 4.4+)
- **Architecture**: arm64-v8a, armeabi-v7a, x86_64
- **Size**: ~20MB per architecture
- **RAM**: 2GB+ for small models, 4GB+ for larger models

### Installation

```gradle
dependencies {
    // ONNX Runtime for Android
    implementation 'com.microsoft.onnxruntime:onnxruntime-android:1.19.0'

    // Optional: NNAPI execution provider
    implementation 'com.microsoft.onnxruntime:onnxruntime-android-nnapi:1.19.0'

    // Optional: GPU execution provider
    implementation 'com.microsoft.onnxruntime:onnxruntime-android-gpu:1.19.0'
}
```

### Implementation

```kotlin
import ai.onnxruntime.*
import java.nio.FloatBuffer
import java.nio.LongBuffer

class ONNXRuntimeLLM(private val context: Context) {
    private lateinit var ortEnvironment: OrtEnvironment
    private lateinit var ortSession: OrtSession
    private val tokenizer = Tokenizer() // Custom tokenizer implementation

    suspend fun initialize(modelPath: String) = withContext(Dispatchers.IO) {
        // Create ORT environment
        ortEnvironment = OrtEnvironment.getEnvironment()

        // Create session options
        val sessionOptions = OrtSession.SessionOptions().apply {
            // Add execution providers
            addNnapi() // Android NNAPI
            addCPU()   // CPU fallback

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
        ortSession = ortEnvironment.createSession(modelBytes, sessionOptions)

        // Log input/output info
        logModelInfo()
    }

    suspend fun generate(
        prompt: String,
        maxLength: Int = 100,
        temperature: Float = 0.7f
    ): String = withContext(Dispatchers.Default) {
        val generatedTokens = mutableListOf<Long>()
        var inputIds = tokenizer.encode(prompt)

        for (i in 0 until maxLength) {
            // Prepare input tensor
            val inputTensor = createInputTensor(inputIds)

            // Run inference
            val outputs = ortSession.run(mapOf("input_ids" to inputTensor))

            // Get logits
            val logits = outputs[0].value as Array<Array<FloatArray>>
            val lastLogits = logits[0][inputIds.size - 1]

            // Sample next token
            val nextToken = sampleToken(lastLogits, temperature)
            generatedTokens.add(nextToken)

            // Check for EOS
            if (nextToken == tokenizer.eosTokenId) break

            // Update input
            inputIds = inputIds + nextToken
        }

        tokenizer.decode(generatedTokens)
    }

    // Streaming generation
    fun generateStream(
        prompt: String,
        onToken: (String) -> Unit,
        options: GenerationOptions = GenerationOptions()
    ) = flow {
        var inputIds = tokenizer.encode(prompt)

        repeat(options.maxTokens) {
            val inputTensor = createInputTensor(inputIds)
            val outputs = ortSession.run(mapOf("input_ids" to inputTensor))

            val logits = outputs[0].value as Array<Array<FloatArray>>
            val nextToken = sampleToken(logits[0].last(), options.temperature)

            if (nextToken == tokenizer.eosTokenId) return@flow

            val text = tokenizer.decode(listOf(nextToken))
            emit(text)
            onToken(text)

            inputIds = inputIds + nextToken
        }
    }

    private fun createInputTensor(tokens: List<Long>): OnnxTensor {
        val shape = longArrayOf(1, tokens.size.toLong())
        val buffer = LongBuffer.allocate(tokens.size)
        buffer.put(tokens.toLongArray())
        buffer.rewind()

        return OnnxTensor.createTensor(ortEnvironment, buffer, shape)
    }

    private fun sampleToken(logits: FloatArray, temperature: Float): Long {
        // Apply temperature
        val scaledLogits = logits.map { it / temperature }.toFloatArray()

        // Softmax
        val maxLogit = scaledLogits.maxOrNull() ?: 0f
        val expLogits = scaledLogits.map { exp(it - maxLogit) }
        val sumExp = expLogits.sum()
        val probs = expLogits.map { it / sumExp }

        // Sample from distribution
        return sampleFromDistribution(probs)
    }

    // Advanced: Quantized model support
    suspend fun loadQuantizedModel(modelPath: String, quantizationType: QuantizationType) {
        val sessionOptions = OrtSession.SessionOptions().apply {
            when (quantizationType) {
                QuantizationType.INT8 -> {
                    // Enable INT8 quantization
                    addConfigEntry("session.disable_prepacking", "1")
                    addConfigEntry("session.use_int8_subgraph", "1")
                }
                QuantizationType.UINT8 -> {
                    addConfigEntry("session.use_uint8_subgraph", "1")
                }
                QuantizationType.DYNAMIC -> {
                    // Dynamic quantization settings
                    setExecutionMode(OrtSession.SessionOptions.ExecutionMode.PARALLEL)
                }
            }

            // Use NNAPI for quantized models
            addNnapi(NnapiFlags.USE_FP16)
        }

        val modelBytes = loadModelFromPath(modelPath)
        ortSession = ortEnvironment.createSession(modelBytes, sessionOptions)
    }

    // Resource management
    fun release() {
        ortSession.close()
        ortEnvironment.close()
    }

    private fun logModelInfo() {
        Log.d("ONNX", "Model inputs:")
        ortSession.inputNames.forEach { name ->
            val info = ortSession.getInputInfo(name)
            Log.d("ONNX", "  $name: ${info.shape.contentToString()}")
        }

        Log.d("ONNX", "Model outputs:")
        ortSession.outputNames.forEach { name ->
            val info = ortSession.getOutputInfo(name)
            Log.d("ONNX", "  $name: ${info.shape.contentToString()}")
        }
    }
}

// Helper classes
data class GenerationOptions(
    val maxTokens: Int = 150,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 50,
    val repetitionPenalty: Float = 1.1f
)

enum class QuantizationType {
    INT8, UINT8, DYNAMIC, FLOAT16
}
```

### Performance Optimization

```kotlin
class ONNXRuntimeOptimizer {
    companion object {
        fun createOptimizedSession(
            environment: OrtEnvironment,
            modelPath: String,
            deviceCapabilities: DeviceCapabilities
        ): OrtSession {
            val sessionOptions = OrtSession.SessionOptions().apply {
                // Choose execution provider based on device
                when {
                    deviceCapabilities.hasNPU -> {
                        // Use NPU if available
                        addQnnExecutionProvider(QnnExecutionProviderOptions())
                    }
                    deviceCapabilities.hasGPU -> {
                        // Use GPU
                        addGpu()
                    }
                    deviceCapabilities.supportsNNAPI -> {
                        // Use NNAPI
                        addNnapi(NnapiFlags.USE_FP16 or NnapiFlags.CPU_DISABLED)
                    }
                    else -> {
                        // Optimized CPU
                        addCPU()
                        setInterOpNumThreads(deviceCapabilities.cpuCores / 2)
                        setIntraOpNumThreads(deviceCapabilities.cpuCores)
                    }
                }

                // Memory optimizations
                setMemoryPatternOptimization(true)
                addFreeDimensionOverride("batch_size", 1)

                // Graph optimizations
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                setGraphOptimizationLevel(GraphOptimizationLevel.ORT_ENABLE_ALL)
            }

            return environment.createSession(modelPath, sessionOptions)
        }
    }
}
```

---

## 4. ExecuTorch

### Overview
PyTorch's edge AI framework enabling efficient on-device inference for PyTorch models with multiple backend support.

### Requirements
- **Android Version**: API level 21+ (Android 5.0+)
- **Architecture**: arm64-v8a, armeabi-v7a
- **AAR Size**: ~50MB
- **Model Format**: .pte (PyTorch Edge)

### Installation

```gradle
dependencies {
    // ExecuTorch Android AAR
    implementation 'org.pytorch:executorch-android:0.6.0-rc1'

    // Optional backends
    implementation 'org.pytorch:executorch-backend-xnnpack:0.6.0-rc1'
    implementation 'org.pytorch:executorch-backend-vulkan:0.6.0-rc1'
    implementation 'org.pytorch:executorch-backend-qnn:0.6.0-rc1'  // Qualcomm NPU
}

// Or direct from S3
repositories {
    maven {
        url "https://pytorch.s3.amazonaws.com/executorch/release"
    }
}
```

### Implementation

```kotlin
import org.pytorch.executorch.*
import kotlinx.coroutines.flow.*

class ExecuTorchLLM(private val context: Context) {
    private var module: Module? = null
    private lateinit var tokenizer: LlamaTokenizer

    suspend fun initialize(modelPath: String) = withContext(Dispatchers.IO) {
        // Load model from assets
        val modelFile = File(context.filesDir, "model.pte")
        if (!modelFile.exists()) {
            context.assets.open(modelPath).use { input ->
                modelFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }

        // Load module with configuration
        module = Module.load(
            modelFile.absolutePath,
            mapOf(
                Module.BACKEND to Module.Backend.XNNPACK,
                Module.NUM_THREADS to Runtime.getRuntime().availableProcessors()
            )
        )

        // Initialize tokenizer
        tokenizer = LlamaTokenizer.getInstance()
        val tokenizerPath = copyAssetToFile("tokenizer.model")
        tokenizer.load(tokenizerPath)
    }

    suspend fun generate(
        prompt: String,
        maxTokens: Int = 150,
        temperature: Float = 0.7f,
        callback: (String) -> Unit = {}
    ): String = withContext(Dispatchers.Default) {
        val result = StringBuilder()

        // Tokenize input
        val tokens = tokenizer.encode(prompt).toMutableList()

        repeat(maxTokens) {
            // Prepare input tensor
            val inputArray = tokens.toLongArray()
            val inputTensor = Tensor.fromBlob(
                inputArray,
                longArrayOf(1, inputArray.size.toLong()),
                MemoryFormat.CONTIGUOUS
            )

            // Forward pass
            val output = module?.forward(IValue.from(inputTensor))?.toTensor()
                ?: throw Exception("Model forward pass failed")

            // Get logits for last position
            val logits = output.dataAsFloatArray
            val vocabSize = logits.size / tokens.size
            val lastLogits = logits.sliceArray(
                (tokens.size - 1) * vocabSize until tokens.size * vocabSize
            )

            // Sample next token
            val nextToken = sampleToken(lastLogits, temperature)
            tokens.add(nextToken.toLong())

            // Decode token
            val text = tokenizer.decode(intArrayOf(nextToken))
            result.append(text)
            callback(text)

            // Check for EOS
            if (nextToken == tokenizer.eosToken) break
        }

        result.toString()
    }

    // Streaming with Flow
    fun generateStream(
        prompt: String,
        options: GenerationOptions = GenerationOptions()
    ): Flow<GenerationResult> = flow {
        val tokens = tokenizer.encode(prompt).toMutableList()
        var totalTime = 0L

        repeat(options.maxTokens) { i ->
            val startTime = System.currentTimeMillis()

            // Create input tensor
            val inputTensor = createInputTensor(tokens)

            // Run inference
            val output = module?.forward(IValue.from(inputTensor))?.toTensor()
                ?: return@flow

            // Process output
            val nextToken = processOutput(output, tokens.size, options)
            tokens.add(nextToken.toLong())

            val inferenceTime = System.currentTimeMillis() - startTime
            totalTime += inferenceTime

            // Decode and emit
            val text = tokenizer.decode(intArrayOf(nextToken))
            emit(
                GenerationResult(
                    token = text,
                    tokenId = nextToken,
                    inferenceTimeMs = inferenceTime,
                    tokensPerSecond = (i + 1).toFloat() / (totalTime / 1000f)
                )
            )

            if (nextToken == tokenizer.eosToken) return@flow
        }
    }

    // Advanced: Custom backend selection
    fun selectOptimalBackend(): Module.Backend {
        return when {
            isQualcommDevice() -> Module.Backend.QNN
            isMediaTekDevice() -> Module.Backend.MTK
            hasVulkanSupport() -> Module.Backend.VULKAN
            else -> Module.Backend.XNNPACK
        }
    }

    // Llama-specific implementation
    inner class LlamaModel {
        fun generate(
            prompt: String,
            systemPrompt: String? = null
        ): Flow<String> = flow {
            val formattedPrompt = formatPrompt(prompt, systemPrompt)

            val options = GenerationOptions(
                maxTokens = 200,
                temperature = 0.7f,
                topP = 0.9f,
                repetitionPenalty = 1.1f
            )

            generateStream(formattedPrompt, options).collect { result ->
                emit(result.token)
            }
        }

        private fun formatPrompt(prompt: String, systemPrompt: String?): String {
            return buildString {
                append("<s>")
                if (systemPrompt != null) {
                    append("[INST] <<SYS>>\n")
                    append(systemPrompt)
                    append("\n<</SYS>>\n\n")
                }
                append(prompt)
                append(" [/INST]")
            }
        }
    }

    // Resource monitoring
    fun getModelStats(): ModelStats {
        return ModelStats(
            modelSizeBytes = module?.getModelSize() ?: 0,
            ramUsageBytes = module?.getCurrentMemoryUsage() ?: 0,
            backend = module?.getBackend() ?: Module.Backend.CPU,
            optimizationLevel = module?.getOptimizationLevel() ?: 0
        )
    }
}

data class GenerationResult(
    val token: String,
    val tokenId: Int,
    val inferenceTimeMs: Long,
    val tokensPerSecond: Float
)

data class ModelStats(
    val modelSizeBytes: Long,
    val ramUsageBytes: Long,
    val backend: Module.Backend,
    val optimizationLevel: Int
)
```

### Backend Configuration

```kotlin
class ExecuTorchBackendManager {
    companion object {
        fun configureForDevice(context: Context): Map<String, Any> {
            val config = mutableMapOf<String, Any>()

            // Detect device capabilities
            val deviceInfo = getDeviceInfo()

            when {
                // Qualcomm Snapdragon with HTP/DSP
                deviceInfo.chipset.contains("Snapdragon") -> {
                    config[Module.BACKEND] = Module.Backend.QNN
                    config["qnn_htp_performance_mode"] = "high_performance"
                    config["qnn_device"] = "HTP"
                }

                // MediaTek Dimensity with APU
                deviceInfo.chipset.contains("Dimensity") -> {
                    config[Module.BACKEND] = Module.Backend.MTK
                    config["mtk_neuron_config"] = "APU_3.0"
                }

                // Devices with Vulkan support
                hasVulkanSupport() -> {
                    config[Module.BACKEND] = Module.Backend.VULKAN
                    config["vulkan_enable_fp16"] = true
                }

                // Default: Optimized CPU
                else -> {
                    config[Module.BACKEND] = Module.Backend.XNNPACK
                    config[Module.NUM_THREADS] = deviceInfo.cpuCores
                }
            }

            return config
        }
    }
}
```

---

## 5. MLC-LLM

### Overview
Machine Learning Compilation framework providing universal LLM deployment with hardware-agnostic optimization.

### Requirements
- **Android Version**: API level 24+ (Android 7.0+)
- **Architecture**: arm64-v8a
- **RAM**: 4GB+ for quantized models
- **Storage**: 1-4GB per model

### Installation

```gradle
dependencies {
    // MLC-LLM Android SDK
    implementation 'org.mlc:mlc-llm:0.1.0'

    // TVM Runtime (required dependency)
    implementation 'org.apache.tvm:tvm4j-core:0.1.0'
}

// Alternative: Local AAR
implementation files('libs/mlc-llm-release.aar')
```

### Implementation

```kotlin
import org.mlc.llm.*
import kotlinx.coroutines.flow.*

class MLCLLMChat(private val context: Context) {
    private lateinit var engine: MLCEngine
    private var isInitialized = false

    suspend fun initialize(
        modelPath: String,
        modelLib: String = "model_android"
    ) = withContext(Dispatchers.IO) {
        // Create engine configuration
        val config = MLCEngineConfig().apply {
            model = modelPath
            modelLib = modelLib
            device = DeviceKind.AUTO // Auto-select best device
            maxBatchSize = 1
            maxSequenceLength = 2048
            maxTotalSequenceLength = 4096
            prefillChunkSize = 512
            gpuMemoryUtilization = 0.9f
        }

        // Initialize engine
        engine = MLCEngine(config)

        // Load model
        engine.reload(modelPath, modelLib)

        isInitialized = true
        Log.d("MLC", "Model loaded successfully")
    }

    // Chat completion with OpenAI-compatible API
    suspend fun chatCompletion(
        messages: List<ChatMessage>,
        temperature: Float = 0.7f,
        maxTokens: Int = 150
    ): String = withContext(Dispatchers.Default) {
        val request = ChatCompletionRequest(
            model = engine.modelId,
            messages = messages.map { msg ->
                Message(role = msg.role.toString(), content = msg.content)
            },
            temperature = temperature,
            maxTokens = maxTokens,
            stream = false
        )

        val response = engine.chatCompletion(request)
        response.choices.firstOrNull()?.message?.content ?: ""
    }

    // Streaming chat completion
    fun streamChatCompletion(
        messages: List<ChatMessage>,
        options: GenerationConfig = GenerationConfig()
    ): Flow<StreamResponse> = flow {
        val request = ChatCompletionRequest(
            model = engine.modelId,
            messages = messages.map { msg ->
                Message(role = msg.role.toString(), content = msg.content)
            },
            temperature = options.temperature,
            maxTokens = options.maxTokens,
            topP = options.topP,
            frequencyPenalty = options.frequencyPenalty,
            presencePenalty = options.presencePenalty,
            stream = true
        )

        engine.streamChatCompletion(request) { chunk ->
            emit(StreamResponse(
                content = chunk.choices.firstOrNull()?.delta?.content ?: "",
                finishReason = chunk.choices.firstOrNull()?.finishReason
            ))
        }
    }

    // Advanced: JSON mode for structured generation
    suspend fun generateJSON<T : Any>(
        prompt: String,
        schema: Class<T>
    ): T = withContext(Dispatchers.Default) {
        val request = ChatCompletionRequest(
            model = engine.modelId,
            messages = listOf(
                Message(role = "system", content = "Respond only with valid JSON"),
                Message(role = "user", content = prompt)
            ),
            responseFormat = ResponseFormat(type = "json_object"),
            jsonSchema = generateJsonSchema(schema)
        )

        val response = engine.chatCompletion(request)
        val json = response.choices.first().message.content

        // Parse JSON to object
        Gson().fromJson(json, schema)
    }

    // Multi-LoRA support
    suspend fun loadLoRA(adapterPath: String, adapterName: String) {
        engine.loadLoRA(adapterPath, adapterName)
    }

    fun switchLoRA(adapterName: String) {
        engine.activateLoRA(adapterName)
    }

    // Conversation management
    inner class ConversationManager {
        private val conversations = mutableMapOf<String, MutableList<ChatMessage>>()

        fun createConversation(id: String) {
            conversations[id] = mutableListOf()
        }

        suspend fun sendMessage(
            conversationId: String,
            message: String
        ): String {
            val conversation = conversations[conversationId]
                ?: throw Exception("Conversation not found")

            // Add user message
            conversation.add(ChatMessage(ChatRole.USER, message))

            // Generate response
            val response = chatCompletion(conversation)

            // Add assistant message
            conversation.add(ChatMessage(ChatRole.ASSISTANT, response))

            return response
        }

        fun getHistory(conversationId: String): List<ChatMessage> {
            return conversations[conversationId] ?: emptyList()
        }
    }

    // Model management
    companion object {
        fun downloadModel(
            modelId: String,
            progressCallback: (Float) -> Unit
        ): Flow<DownloadResult> = flow {
            val downloader = MLCModelDownloader()

            downloader.download(
                model = modelId,
                progressHandler = { progress ->
                    progressCallback(progress.fractionCompleted.toFloat())
                    emit(DownloadResult.Progress(progress.fractionCompleted.toFloat()))
                }
            )

            emit(DownloadResult.Completed(modelId))
        }

        fun listAvailableModels(): List<MLCModel> {
            return listOf(
                MLCModel("Llama-3.2-3B-Instruct-q4f16_1-MLC", "1.7GB"),
                MLCModel("Mistral-7B-Instruct-v0.3-q4f16_1-MLC", "3.8GB"),
                MLCModel("Phi-3-mini-4k-instruct-q4f16_1-MLC", "1.5GB"),
                MLCModel("Qwen2.5-1.5B-Instruct-q4f16_1-MLC", "0.8GB"),
                MLCModel("gemma-2b-it-q4f16_1-MLC", "1.1GB")
            )
        }
    }
}

// Helper classes
data class ChatMessage(
    val role: ChatRole,
    val content: String
)

enum class ChatRole {
    USER, ASSISTANT, SYSTEM
}

data class GenerationConfig(
    val temperature: Float = 0.7f,
    val maxTokens: Int = 150,
    val topP: Float = 0.95f,
    val topK: Int = 40,
    val frequencyPenalty: Float = 0.0f,
    val presencePenalty: Float = 0.0f,
    val stopSequences: List<String> = emptyList()
)

sealed class DownloadResult {
    data class Progress(val percentage: Float) : DownloadResult()
    data class Completed(val modelId: String) : DownloadResult()
    data class Error(val message: String) : DownloadResult()
}
```

### Performance Optimization

```kotlin
class MLCPerformanceOptimizer {
    companion object {
        fun optimizeForDevice(context: Context): MLCEngineConfig {
            val config = MLCEngineConfig()
            val deviceInfo = getDeviceInfo(context)

            when {
                // High-end device (8GB+ RAM)
                deviceInfo.totalRam > 8_000_000_000L -> {
                    config.apply {
                        device = DeviceKind.METAL // or CUDA on supported devices
                        maxBatchSize = 4
                        maxSequenceLength = 4096
                        gpuMemoryUtilization = 0.9f
                        prefillChunkSize = 1024
                    }
                }

                // Mid-range device (4-8GB RAM)
                deviceInfo.totalRam > 4_000_000_000L -> {
                    config.apply {
                        device = DeviceKind.VULKAN
                        maxBatchSize = 1
                        maxSequenceLength = 2048
                        gpuMemoryUtilization = 0.7f
                        prefillChunkSize = 512
                    }
                }

                // Low-end device
                else -> {
                    config.apply {
                        device = DeviceKind.CPU
                        maxBatchSize = 1
                        maxSequenceLength = 1024
                        prefillChunkSize = 256
                    }
                }
            }

            return config
        }
    }
}
```

---

## 6. TensorFlow Lite (LiteRT)

### Overview
Google's lightweight ML framework (now rebranded as LiteRT) optimized for mobile and embedded devices.

### Requirements
- **Android Version**: API level 19+ (Android 4.4+)
- **Architecture**: All Android architectures
- **Size**: ~1MB base, varies with ops
- **Model Format**: .tflite

### Installation

```gradle
dependencies {
    // TensorFlow Lite core
    implementation 'org.tensorflow:tensorflow-lite:2.16.1'

    // GPU delegate for acceleration
    implementation 'org.tensorflow:tensorflow-lite-gpu:2.16.1'

    // NNAPI delegate
    implementation 'org.tensorflow:tensorflow-lite-nnapi:2.16.1'

    // Support library for easier integration
    implementation 'org.tensorflow:tensorflow-lite-support:0.4.4'

    // Task library for common ML tasks
    implementation 'org.tensorflow:tensorflow-lite-task-text:0.4.4'
}
```

### Implementation

```kotlin
import org.tensorflow.lite.*
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import java.nio.ByteBuffer

class TFLiteLLM(private val context: Context) {
    private lateinit var interpreter: Interpreter
    private lateinit var tokenizer: BertTokenizer // or custom tokenizer
    private val modelBuffer: ByteBuffer by lazy {
        loadModelFile("model.tflite")
    }

    suspend fun initialize() = withContext(Dispatchers.IO) {
        // Configure interpreter options
        val options = Interpreter.Options().apply {
            // CPU settings
            setNumThreads(Runtime.getRuntime().availableProcessors())

            // Add GPU delegate
            val gpuDelegate = GpuDelegate(
                GpuDelegate.Options().apply {
                    setPrecisionLossAllowed(true)
                    setInferencePreference(
                        GpuDelegate.Options.INFERENCE_PREFERENCE_SUSTAINED_SPEED
                    )
                }
            )
            addDelegate(gpuDelegate)

            // Add NNAPI delegate for Android NN API
            val nnapiDelegate = NnapiDelegate(
                NnapiDelegate.Options().apply {
                    setAllowFp16(true)
                    setUseNnapiCpu(false)
                    setExecutionPreference(
                        NnapiDelegate.Options.EXECUTION_PREFERENCE_SUSTAINED_SPEED
                    )
                }
            )
            addDelegate(nnapiDelegate)

            // Enable XNNPack delegate (built-in)
            setUseXNNPACK(true)
        }

        // Create interpreter
        interpreter = Interpreter(modelBuffer, options)

        // Initialize tokenizer
        tokenizer = BertTokenizer.builder()
            .setVocabFile(context.assets.open("vocab.txt"))
            .build()

        // Log model info
        logModelDetails()
    }

    suspend fun generate(
        prompt: String,
        maxLength: Int = 100,
        temperature: Float = 0.7f
    ): String = withContext(Dispatchers.Default) {
        val result = StringBuilder()
        var inputIds = tokenizer.tokenize(prompt).ids

        repeat(maxLength) {
            // Prepare input
            val inputTensor = prepareInput(inputIds)

            // Allocate output buffer
            val outputShape = interpreter.getOutputTensor(0).shape()
            val outputBuffer = TensorBuffer.createFixedSize(
                outputShape,
                DataType.FLOAT32
            )

            // Run inference
            interpreter.run(inputTensor.buffer, outputBuffer.buffer)

            // Process output
            val logits = outputBuffer.floatArray
            val nextToken = sampleFromLogits(logits, temperature)

            if (nextToken == tokenizer.vocab["[SEP]"]) break

            // Decode token
            val word = tokenizer.idToToken(nextToken)
            result.append(word).append(" ")

            // Update input
            inputIds = inputIds + nextToken
        }

        result.toString().trim()
    }

    // Streaming with dynamic tensor shapes
    fun generateStream(
        prompt: String,
        onToken: (String) -> Unit
    ) = flow {
        var inputIds = tokenizer.tokenize(prompt).ids

        repeat(100) { // max iterations
            // Resize input tensor if needed
            val inputShape = intArrayOf(1, inputIds.size)
            interpreter.resizeInput(0, inputShape)
            interpreter.allocateTensors()

            // Prepare input
            val inputBuffer = ByteBuffer.allocateDirect(
                inputIds.size * 4
            ).apply {
                order(ByteOrder.nativeOrder())
                asIntBuffer().put(inputIds.toIntArray())
            }

            // Run inference
            val outputBuffer = ByteBuffer.allocateDirect(
                tokenizer.vocabSize * 4
            ).order(ByteOrder.nativeOrder())

            interpreter.run(inputBuffer, outputBuffer)

            // Sample next token
            val logits = FloatArray(tokenizer.vocabSize)
            outputBuffer.asFloatBuffer().get(logits)
            val nextToken = sampleFromLogits(logits, 0.7f)

            // Decode and emit
            val word = tokenizer.idToToken(nextToken)
            emit(word)
            onToken(word)

            if (nextToken == tokenizer.vocab["[SEP]"]) break

            inputIds = inputIds + nextToken
        }
    }

    // Batch processing for efficiency
    suspend fun generateBatch(
        prompts: List<String>,
        maxLength: Int = 100
    ): List<String> = withContext(Dispatchers.Default) {
        // Tokenize all prompts
        val tokenizedBatch = prompts.map { tokenizer.tokenize(it).ids }

        // Pad to same length
        val maxInputLength = tokenizedBatch.maxOf { it.size }
        val paddedBatch = tokenizedBatch.map { ids ->
            ids + List(maxInputLength - ids.size) { tokenizer.vocab["[PAD]"]!! }
        }

        // Prepare batch input
        val batchSize = prompts.size
        val inputShape = intArrayOf(batchSize, maxInputLength)
        interpreter.resizeInput(0, inputShape)
        interpreter.allocateTensors()

        // Run batch inference
        val inputBuffer = createBatchInput(paddedBatch)
        val outputShape = interpreter.getOutputTensor(0).shape()
        val outputBuffer = ByteBuffer.allocateDirect(
            outputShape.reduce { acc, i -> acc * i } * 4
        ).order(ByteOrder.nativeOrder())

        interpreter.run(inputBuffer, outputBuffer)

        // Process batch output
        processBatchOutput(outputBuffer, batchSize)
    }

    // Model optimization utilities
    companion object {
        suspend fun convertAndOptimizeModel(
            modelPath: String,
            outputPath: String,
            optimization: OptimizationStrategy
        ) = withContext(Dispatchers.IO) {
            // This would typically be done in Python
            val converter = """
                import tensorflow as tf

                # Load model
                model = tf.keras.models.load_model('$modelPath')

                # Convert to TFLite
                converter = tf.lite.TFLiteConverter.from_keras_model(model)

                # Apply optimizations
                if optimization == 'DYNAMIC_RANGE':
                    converter.optimizations = [tf.lite.Optimize.DEFAULT]
                elif optimization == 'FLOAT16':
                    converter.optimizations = [tf.lite.Optimize.DEFAULT]
                    converter.target_spec.supported_types = [tf.float16]
                elif optimization == 'INT8':
                    converter.optimizations = [tf.lite.Optimize.DEFAULT]
                    converter.representative_dataset = representative_dataset_gen

                # Convert and save
                tflite_model = converter.convert()

                with open('$outputPath', 'wb') as f:
                    f.write(tflite_model)
            """.trimIndent()

            // Execute conversion
            PythonBridge.execute(converter)
        }
    }

    private fun loadModelFile(filename: String): ByteBuffer {
        val fileDescriptor = context.assets.openFd(filename)
        val inputStream = FileInputStream(fileDescriptor.fileDescriptor)
        val fileChannel = inputStream.channel
        val startOffset = fileDescriptor.startOffset
        val declaredLength = fileDescriptor.declaredLength

        return fileChannel.map(
            FileChannel.MapMode.READ_ONLY,
            startOffset,
            declaredLength
        )
    }

    private fun logModelDetails() {
        Log.d("TFLite", "Input tensors:")
        interpreter.inputTensorCount.let { count ->
            repeat(count) { i ->
                val tensor = interpreter.getInputTensor(i)
                Log.d("TFLite", "  Input $i: ${tensor.shape().contentToString()}")
            }
        }

        Log.d("TFLite", "Output tensors:")
        interpreter.outputTensorCount.let { count ->
            repeat(count) { i ->
                val tensor = interpreter.getOutputTensor(i)
                Log.d("TFLite", "  Output $i: ${tensor.shape().contentToString()}")
            }
        }
    }
}

enum class OptimizationStrategy {
    NONE, DYNAMIC_RANGE, FLOAT16, INT8
}
```

### Advanced Features

```kotlin
// Quantization-aware inference
class QuantizedTFLiteModel(context: Context) {
    private lateinit var interpreter: Interpreter

    fun loadQuantizedModel(modelPath: String) {
        val options = Interpreter.Options().apply {
            // Enable quantized model support
            setUseNNAPI(true)
            setAllowFp16PrecisionForFp32(true)
            setNumThreads(4)

            // Add Hexagon delegate for Snapdragon
            if (isSnapdragonDevice()) {
                val hexagonDelegate = HexagonDelegate(
                    context,
                    HexagonDelegate.Options()
                )
                addDelegate(hexagonDelegate)
            }
        }

        interpreter = Interpreter(loadModelFile(modelPath), options)
    }

    fun runInt8Inference(input: IntArray): FloatArray {
        // Quantize input
        val quantizedInput = ByteBuffer.allocateDirect(input.size)
            .order(ByteOrder.nativeOrder())

        input.forEach { value ->
            quantizedInput.put((value - 128).toByte()) // INT8 quantization
        }

        // Allocate output
        val outputSize = interpreter.getOutputTensor(0).numElements()
        val output = ByteBuffer.allocateDirect(outputSize)
            .order(ByteOrder.nativeOrder())

        // Run inference
        interpreter.run(quantizedInput, output)

        // Dequantize output
        val scale = interpreter.getOutputTensor(0).quantizationParams().scale
        val zeroPoint = interpreter.getOutputTensor(0).quantizationParams().zeroPoint

        val result = FloatArray(outputSize)
        output.rewind()
        repeat(outputSize) { i ->
            val quantizedValue = output.get()
            result[i] = scale * (quantizedValue - zeroPoint)
        }

        return result
    }
}
```

---

## 7. MediaPipe LLM Inference

### Overview
Google's MediaPipe framework for on-device LLM inference with support for various model architectures.

### Requirements
- **Android Version**: API level 24+ (Android 7.0+)
- **Architecture**: arm64-v8a
- **Models**: Gemma-2, Phi-2, Falcon, StableLM
- **RAM**: 4GB+ recommended

### Installation

```gradle
dependencies {
    // MediaPipe Tasks for GenAI
    implementation 'com.google.mediapipe:tasks-genai:0.10.0'

    // MediaPipe core
    implementation 'com.google.mediapipe:mediapipe-core:0.10.0'
}
```

### Implementation

```kotlin
import com.google.mediapipe.tasks.genai.llminference.*
import com.google.mediapipe.tasks.core.BaseOptions

class MediaPipeLLM(private val context: Context) {
    private lateinit var llmInference: LlmInference
    private val modelPath = "gemma-2b-it-gpu-int4.bin"

    suspend fun initialize() = withContext(Dispatchers.IO) {
        // Configure base options
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(modelPath)
            .setDelegate(BaseOptions.Delegate.GPU) // Use GPU acceleration
            .build()

        // Configure LLM options
        val options = LlmInference.LlmInferenceOptions.builder()
            .setBaseOptions(baseOptions)
            .setMaxTokens(512)
            .setMaxTopK(40)
            .setTemperature(0.8f)
            .setRandomSeed(42)
            .build()

        // Create LLM inference instance
        llmInference = LlmInference.createFromOptions(context, options)

        Log.d("MediaPipe", "Model loaded: ${llmInference.modelInfo}")
    }

    suspend fun generateResponse(prompt: String): String {
        return withContext(Dispatchers.Default) {
            llmInference.generateResponse(prompt)
        }
    }

    // Streaming generation
    fun generateResponseStream(
        prompt: String,
        onPartialResult: (String) -> Unit,
        onComplete: () -> Unit,
        onError: (Exception) -> Unit
    ) {
        llmInference.generateResponseAsync(
            prompt,
            object : LlmInference.PartialResultListener {
                override fun onPartialResult(partialResult: String) {
                    onPartialResult(partialResult)
                }

                override fun onComplete() {
                    onComplete()
                }

                override fun onError(error: RuntimeException) {
                    onError(error)
                }
            }
        )
    }

    // Advanced configuration with LoRA adapters
    suspend fun loadWithLoRA(
        baseModelPath: String,
        loraPath: String,
        loraScale: Float = 1.0f
    ) {
        val options = LlmInference.LlmInferenceOptions.builder()
            .setBaseOptions(
                BaseOptions.builder()
                    .setModelAssetPath(baseModelPath)
                    .build()
            )
            .setLoraPath(loraPath)
            .setLoraScale(loraScale)
            .build()

        llmInference = LlmInference.createFromOptions(context, options)
    }

    // Model-specific implementations
    inner class GemmaModel {
        suspend fun chat(
            messages: List<ChatMessage>,
            systemPrompt: String? = null
        ): String {
            val formattedPrompt = formatGemmaPrompt(messages, systemPrompt)
            return generateResponse(formattedPrompt)
        }

        private fun formatGemmaPrompt(
            messages: List<ChatMessage>,
            systemPrompt: String?
        ): String {
            return buildString {
                systemPrompt?.let {
                    append("<start_of_turn>system\n$it<end_of_turn>\n")
                }

                messages.forEach { message ->
                    when (message.role) {
                        ChatRole.USER -> append("<start_of_turn>user\n")
                        ChatRole.ASSISTANT -> append("<start_of_turn>model\n")
                        else -> {}
                    }
                    append(message.content)
                    append("<end_of_turn>\n")
                }

                append("<start_of_turn>model\n")
            }
        }
    }

    // Supported model configurations
    companion object {
        data class ModelConfig(
            val name: String,
            val path: String,
            val delegate: BaseOptions.Delegate,
            val maxTokens: Int,
            val description: String
        )

        val SUPPORTED_MODELS = listOf(
            ModelConfig(
                "Gemma-2B",
                "gemma-2b-it-gpu-int4.bin",
                BaseOptions.Delegate.GPU,
                512,
                "Google's efficient 2B parameter model"
            ),
            ModelConfig(
                "Phi-2",
                "phi-2-gpu-int4.bin",
                BaseOptions.Delegate.GPU,
                512,
                "Microsoft's compact 2.7B model"
            ),
            ModelConfig(
                "Falcon-RW-1B",
                "falcon-rw-1b-cpu-int8.bin",
                BaseOptions.Delegate.CPU,
                256,
                "TII's 1B parameter model"
            ),
            ModelConfig(
                "StableLM-3B",
                "stablelm-3b-gpu-int4.bin",
                BaseOptions.Delegate.GPU,
                512,
                "Stability AI's 3B model"
            )
        )
    }
}
```

### AI Edge Model Export

```kotlin
// Export custom models for MediaPipe
class AIEdgeExporter {
    companion object {
        // Python script for model export
        const val EXPORT_SCRIPT = """
        import ai_edge_torch
        import torch

        # Load your PyTorch model
        model = torch.load('model.pth')
        model.eval()

        # Convert to AI Edge format
        sample_input = torch.randn(1, 512)
        edge_model = ai_edge_torch.convert(
            model,
            sample_inputs=(sample_input,),
            quant_config=ai_edge_torch.QuantConfig(
                weight_dtype=torch.int4,
                activation_dtype=torch.int8
            )
        )

        # Export for MediaPipe
        edge_model.export('model_mediapipe.tflite')
        """

        fun exportModel(
            inputModelPath: String,
            outputPath: String,
            quantization: QuantizationType = QuantizationType.INT4
        ) {
            // Execute Python script to convert model
            PythonBridge.execute(EXPORT_SCRIPT)
        }
    }
}
```

---

## 8. llama.cpp (GGUF)

### Overview
High-performance C++ implementation for LLM inference with GGUF format support, optimized for CPU execution.

### Requirements
- **Android Version**: API level 21+ (Android 5.0+)
- **Architecture**: All Android architectures
- **JNI**: Native library with Java/Kotlin bindings
- **Model Format**: .gguf files

### Installation

```gradle
dependencies {
    // Option 1: Pre-built AAR
    implementation 'com.github.ggerganov:llama-android:0.1.0'

    // Option 2: Local native library
    implementation fileTree(dir: 'libs', include: ['*.so'])
}

// CMakeLists.txt for native integration
android {
    externalNativeBuild {
        cmake {
            path "src/main/cpp/CMakeLists.txt"
            version "3.10.2"
        }
    }
}
```

### JNI Wrapper Implementation

```kotlin
// Native methods declaration
class LlamaCppJNI {
    companion object {
        init {
            System.loadLibrary("llama")
        }

        // Native method declarations
        @JvmStatic external fun initBackend()
        @JvmStatic external fun freeBackend()
        @JvmStatic external fun loadModel(
            modelPath: String,
            nGpuLayers: Int,
            useMmap: Boolean,
            useMlock: Boolean
        ): Long
        @JvmStatic external fun freeModel(model: Long)
        @JvmStatic external fun createContext(
            model: Long,
            contextSize: Int,
            batchSize: Int,
            threads: Int
        ): Long
        @JvmStatic external fun freeContext(context: Long)
        @JvmStatic external fun tokenize(
            model: Long,
            text: String,
            addBos: Boolean
        ): IntArray
        @JvmStatic external fun detokenize(
            model: Long,
            tokens: IntArray
        ): String
        @JvmStatic external fun generate(
            context: Long,
            tokens: IntArray,
            maxTokens: Int,
            temperature: Float,
            topP: Float,
            topK: Int,
            callback: GenerateCallback
        ): IntArray
    }

    interface GenerateCallback {
        fun onToken(token: String)
        fun onComplete()
    }
}

// Kotlin wrapper
class LlamaCppModel(private val context: Context) {
    private var modelPtr: Long = 0
    private var contextPtr: Long = 0
    private val modelPath: String by lazy {
        copyAssetToFile("model.gguf")
    }

    suspend fun initialize(
        contextSize: Int = 2048,
        batchSize: Int = 512,
        threads: Int = Runtime.getRuntime().availableProcessors()
    ) = withContext(Dispatchers.IO) {
        // Initialize backend
        LlamaCppJNI.initBackend()

        // Load model
        modelPtr = LlamaCppJNI.loadModel(
            modelPath = modelPath,
            nGpuLayers = 0, // CPU only on Android
            useMmap = true,
            useMlock = false
        )

        if (modelPtr == 0L) {
            throw Exception("Failed to load model")
        }

        // Create context
        contextPtr = LlamaCppJNI.createContext(
            model = modelPtr,
            contextSize = contextSize,
            batchSize = batchSize,
            threads = threads
        )

        if (contextPtr == 0L) {
            throw Exception("Failed to create context")
        }

        Log.d("LlamaCpp", "Model loaded successfully")
    }

    suspend fun generate(
        prompt: String,
        maxTokens: Int = 200,
        temperature: Float = 0.7f,
        topP: Float = 0.95f,
        topK: Int = 40
    ): String = withContext(Dispatchers.Default) {
        // Tokenize prompt
        val tokens = LlamaCppJNI.tokenize(modelPtr, prompt, true)

        val result = StringBuilder()

        // Generate tokens
        LlamaCppJNI.generate(
            context = contextPtr,
            tokens = tokens,
            maxTokens = maxTokens,
            temperature = temperature,
            topP = topP,
            topK = topK,
            callback = object : LlamaCppJNI.GenerateCallback {
                override fun onToken(token: String) {
                    result.append(token)
                }

                override fun onComplete() {
                    // Generation complete
                }
            }
        )

        result.toString()
    }

    // Streaming generation with Flow
    fun generateStream(
        prompt: String,
        options: GenerationOptions = GenerationOptions()
    ): Flow<String> = callbackFlow {
        val tokens = LlamaCppJNI.tokenize(modelPtr, prompt, true)

        LlamaCppJNI.generate(
            context = contextPtr,
            tokens = tokens,
            maxTokens = options.maxTokens,
            temperature = options.temperature,
            topP = options.topP,
            topK = options.topK,
            callback = object : LlamaCppJNI.GenerateCallback {
                override fun onToken(token: String) {
                    trySend(token)
                }

                override fun onComplete() {
                    close()
                }
            }
        )

        awaitClose()
    }

    // Advanced sampling strategies
    inner class SamplingStrategies {
        fun mirostat(
            prompt: String,
            tau: Float = 5.0f,
            eta: Float = 0.1f
        ): Flow<String> {
            // Mirostat sampling implementation
            return generateWithCustomSampling(prompt) { logits ->
                applyMirostatSampling(logits, tau, eta)
            }
        }

        fun topKTopP(
            prompt: String,
            topK: Int = 40,
            topP: Float = 0.95f
        ): Flow<String> {
            return generateStream(
                prompt,
                GenerationOptions(topK = topK, topP = topP)
            )
        }

        fun beamSearch(
            prompt: String,
            beamWidth: Int = 5
        ): List<String> {
            // Beam search implementation
            return performBeamSearch(prompt, beamWidth)
        }
    }

    // Grammar-constrained generation
    fun generateWithGrammar(
        prompt: String,
        grammar: String,
        maxTokens: Int = 200
    ): String {
        // Load grammar
        val grammarPtr = LlamaCppJNI.loadGrammar(grammar)

        try {
            // Generate with grammar constraints
            return LlamaCppJNI.generateWithGrammar(
                context = contextPtr,
                prompt = prompt,
                grammar = grammarPtr,
                maxTokens = maxTokens
            )
        } finally {
            LlamaCppJNI.freeGrammar(grammarPtr)
        }
    }

    // Model information
    fun getModelInfo(): ModelInfo {
        return ModelInfo(
            vocabSize = LlamaCppJNI.getVocabSize(modelPtr),
            contextLength = LlamaCppJNI.getContextLength(modelPtr),
            modelType = LlamaCppJNI.getModelType(modelPtr),
            fileSize = File(modelPath).length()
        )
    }

    // Cleanup
    fun release() {
        if (contextPtr != 0L) {
            LlamaCppJNI.freeContext(contextPtr)
            contextPtr = 0L
        }
        if (modelPtr != 0L) {
            LlamaCppJNI.freeModel(modelPtr)
            modelPtr = 0L
        }
        LlamaCppJNI.freeBackend()
    }

    private fun copyAssetToFile(assetName: String): String {
        val file = File(context.filesDir, assetName)
        if (!file.exists()) {
            context.assets.open(assetName).use { input ->
                file.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }
        return file.absolutePath
    }
}

// Native implementation (C++)
/*
#include <jni.h>
#include "llama.h"

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_LlamaCppJNI_loadModel(
    JNIEnv *env,
    jclass clazz,
    jstring model_path,
    jint n_gpu_layers,
    jboolean use_mmap,
    jboolean use_mlock
) {
    const char *path = env->GetStringUTFChars(model_path, nullptr);

    llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = n_gpu_layers;
    params.use_mmap = use_mmap;
    params.use_mlock = use_mlock;

    llama_model *model = llama_load_model_from_file(path, params);

    env->ReleaseStringUTFChars(model_path, path);

    return reinterpret_cast<jlong>(model);
}
*/
```

### GGUF Model Management

```kotlin
class GGUFModelManager(private val context: Context) {

    // Validate GGUF file
    fun validateModel(modelPath: String): Boolean {
        return try {
            val file = RandomAccessFile(modelPath, "r")
            val magic = ByteArray(4)
            file.read(magic)
            file.close()

            // Check GGUF magic number
            String(magic) == "GGUF"
        } catch (e: Exception) {
            false
        }
    }

    // Get model metadata
    suspend fun getModelMetadata(modelPath: String): GGUFMetadata {
        return withContext(Dispatchers.IO) {
            val metadata = LlamaCppJNI.getModelMetadata(modelPath)

            GGUFMetadata(
                version = metadata["version"] as? Int ?: 0,
                architecture = metadata["arch"] as? String ?: "unknown",
                quantization = metadata["quantization"] as? String ?: "unknown",
                parameters = metadata["parameters"] as? Long ?: 0,
                fileSize = File(modelPath).length()
            )
        }
    }

    // Model conversion (requires external tools)
    fun convertToGGUF(
        inputPath: String,
        outputPath: String,
        quantization: String = "Q4_K_M"
    ) {
        // This would call external conversion tools
        ProcessBuilder(
            "python",
            "convert.py",
            inputPath,
            "--outtype", quantization,
            "--outfile", outputPath
        ).start().waitFor()
    }

    data class GGUFMetadata(
        val version: Int,
        val architecture: String,
        val quantization: String,
        val parameters: Long,
        val fileSize: Long
    )
}
```

---

## 9. picoLLM

### Overview
Picovoice's cross-platform LLM inference engine optimized for edge devices with minimal footprint.

### Requirements
- **Android Version**: API level 21+ (Android 5.0+)
- **Architecture**: arm64-v8a, armeabi-v7a
- **API Key**: Required from Picovoice Console
- **RAM**: 2GB+ for compressed models

### Installation

```gradle
dependencies {
    implementation 'ai.picovoice:picollm-android:1.0.0'
}

// Add to AndroidManifest.xml
<uses-permission android:name="android.permission.INTERNET" />
```

### Implementation

```kotlin
import ai.picovoice.picollm.*

class PicoLLMChat(
    private val context: Context,
    private val accessKey: String
) {
    private var picollm: PicoLLM? = null
    private lateinit var modelPath: String

    suspend fun initialize(modelName: String) = withContext(Dispatchers.IO) {
        // Download model if needed
        modelPath = downloadModel(modelName)

        // Create PicoLLM instance
        picollm = PicoLLM.Builder()
            .setAccessKey(accessKey)
            .setModelPath(modelPath)
            .setDevice("best") // Automatically select best hardware
            .build()

        Log.d("PicoLLM", "Model loaded: ${picollm?.modelInfo}")
    }

    suspend fun generate(
        prompt: String,
        completionTokenLimit: Int = 200,
        stopPhrases: Set<String> = setOf(".", "?", "!"),
        temperature: Float = 0.7f,
        topP: Float = 0.9f
    ): String = withContext(Dispatchers.Default) {
        val options = PicoLLMGenerateOptions.Builder()
            .setCompletionTokenLimit(completionTokenLimit)
            .setStopPhrases(stopPhrases)
            .setPresencePenalty(0.0f)
            .setFrequencyPenalty(0.0f)
            .setTemperature(temperature)
            .setTopP(topP)
            .build()

        picollm?.generate(
            prompt = prompt,
            options = options
        ) ?: throw Exception("PicoLLM not initialized")
    }

    // Streaming generation
    fun generateStream(
        prompt: String,
        onToken: (String) -> Unit,
        onComplete: () -> Unit,
        onError: (Exception) -> Unit
    ) {
        val options = PicoLLMGenerateOptions.Builder()
            .setCompletionTokenLimit(200)
            .setTemperature(0.7f)
            .setStreamingEnabled(true)
            .build()

        try {
            picollm?.generate(
                prompt = prompt,
                options = options,
                streamCallback = { token ->
                    onToken(token)
                },
                completionCallback = {
                    onComplete()
                }
            )
        } catch (e: PicoLLMException) {
            onError(e)
        }
    }

    // Dialog management
    inner class DialogManager {
        private var dialog: PicoLLMDialog? = null

        fun createDialog(): PicoLLMDialog {
            dialog = picollm?.createDialog()
                ?: throw Exception("PicoLLM not initialized")
            return dialog!!
        }

        suspend fun addMessage(
            role: String,
            content: String
        ) = withContext(Dispatchers.Default) {
            dialog?.addMessage(role, content)
        }

        suspend fun generate(
            options: PicoLLMGenerateOptions? = null
        ): String = withContext(Dispatchers.Default) {
            dialog?.generate(options ?: getDefaultOptions())
                ?: throw Exception("Dialog not initialized")
        }

        fun getHistory(): List<PicoLLMMessage> {
            return dialog?.getHistory() ?: emptyList()
        }

        fun reset() {
            dialog?.reset()
        }
    }

    // Token usage tracking
    fun getUsage(): TokenUsage {
        return TokenUsage(
            promptTokens = picollm?.usage?.promptTokens ?: 0,
            completionTokens = picollm?.usage?.completionTokens ?: 0,
            totalTokens = picollm?.usage?.totalTokens ?: 0
        )
    }

    // Model management
    private suspend fun downloadModel(modelName: String): String {
        val modelFile = File(context.filesDir, "$modelName.pllm")

        if (!modelFile.exists()) {
            // Download from Picovoice servers
            val downloader = PicoLLMModelDownloader(accessKey)
            downloader.download(
                modelName = modelName,
                outputPath = modelFile.absolutePath
            ) { progress ->
                Log.d("PicoLLM", "Download progress: ${progress * 100}%")
            }
        }

        return modelFile.absolutePath
    }

    // Advanced features
    inner class AdvancedFeatures {
        // Custom tokenization
        fun tokenize(text: String): IntArray {
            return picollm?.tokenize(text)
                ?: throw Exception("PicoLLM not initialized")
        }

        fun detokenize(tokens: IntArray): String {
            return picollm?.detokenize(tokens)
                ?: throw Exception("PicoLLM not initialized")
        }

        // Forward pass for custom sampling
        suspend fun forward(tokens: IntArray): FloatArray {
            return withContext(Dispatchers.Default) {
                picollm?.forward(tokens)
                    ?: throw Exception("PicoLLM not initialized")
            }
        }

        // Interrupt generation
        fun interrupt() {
            picollm?.interrupt()
        }
    }

    // Cleanup
    fun release() {
        picollm?.delete()
        picollm = null
    }

    companion object {
        // Available models
        val AVAILABLE_MODELS = listOf(
            PicoLLMModel("phi2-290", "2.9B parameters, 1.5GB"),
            PicoLLMModel("llama2-7b", "7B parameters, 3.8GB"),
            PicoLLMModel("mistral-7b", "7B parameters, 3.8GB"),
            PicoLLMModel("gemma-2b", "2B parameters, 1.2GB")
        )

        data class PicoLLMModel(
            val name: String,
            val description: String
        )
    }
}

data class TokenUsage(
    val promptTokens: Int,
    val completionTokens: Int,
    val totalTokens: Int
)
```

---

## 10. Native LLM Implementations

### Overview
Custom native implementations using C++ and JNI for maximum performance and flexibility.

### Implementation Example

```kotlin
// Native LLM base class
abstract class NativeLLM(protected val context: Context) {
    protected var nativeHandle: Long = 0

    init {
        System.loadLibrary("native_llm")
    }

    // Native methods
    protected external fun nativeInit(
        modelPath: String,
        configJson: String
    ): Long

    protected external fun nativeGenerate(
        handle: Long,
        prompt: String,
        maxTokens: Int,
        temperature: Float
    ): String

    protected external fun nativeGenerateStream(
        handle: Long,
        prompt: String,
        callback: StreamCallback
    )

    protected external fun nativeRelease(handle: Long)

    interface StreamCallback {
        fun onToken(token: String)
        fun onError(error: String)
        fun onComplete()
    }

    // High-level interface
    abstract suspend fun initialize(modelPath: String)
    abstract suspend fun generate(prompt: String, options: GenerationOptions): String
    abstract fun generateStream(prompt: String, onToken: (String) -> Unit): Flow<String>

    fun release() {
        if (nativeHandle != 0L) {
            nativeRelease(nativeHandle)
            nativeHandle = 0L
        }
    }
}

// Optimized transformer implementation
class OptimizedTransformer(context: Context) : NativeLLM(context) {

    override suspend fun initialize(modelPath: String) = withContext(Dispatchers.IO) {
        val config = TransformerConfig(
            vocabSize = 32000,
            hiddenSize = 4096,
            numLayers = 32,
            numHeads = 32,
            maxSequenceLength = 2048
        )

        nativeHandle = nativeInit(modelPath, Gson().toJson(config))
        if (nativeHandle == 0L) {
            throw Exception("Failed to initialize native model")
        }
    }

    override suspend fun generate(
        prompt: String,
        options: GenerationOptions
    ): String = withContext(Dispatchers.Default) {
        nativeGenerate(
            handle = nativeHandle,
            prompt = prompt,
            maxTokens = options.maxTokens,
            temperature = options.temperature
        )
    }

    override fun generateStream(
        prompt: String,
        onToken: (String) -> Unit
    ): Flow<String> = callbackFlow {
        nativeGenerateStream(
            handle = nativeHandle,
            prompt = prompt,
            callback = object : StreamCallback {
                override fun onToken(token: String) {
                    trySend(token)
                    onToken(token)
                }

                override fun onError(error: String) {
                    close(Exception(error))
                }

                override fun onComplete() {
                    close()
                }
            }
        )

        awaitClose()
    }

    // Custom attention implementation
    external fun nativeFlashAttention(
        handle: Long,
        query: FloatArray,
        key: FloatArray,
        value: FloatArray,
        mask: FloatArray?
    ): FloatArray

    data class TransformerConfig(
        val vocabSize: Int,
        val hiddenSize: Int,
        val numLayers: Int,
        val numHeads: Int,
        val maxSequenceLength: Int
    )
}

// Native C++ implementation skeleton
/*
#include <jni.h>
#include <android/log.h>
#include <vector>
#include <memory>

class NativeTransformer {
private:
    std::unique_ptr<Model> model;
    std::unique_ptr<Tokenizer> tokenizer;

public:
    bool initialize(const std::string& modelPath, const std::string& config) {
        // Load model and tokenizer
        model = Model::load(modelPath);
        tokenizer = Tokenizer::load(modelPath + ".tokenizer");
        return model && tokenizer;
    }

    std::string generate(
        const std::string& prompt,
        int maxTokens,
        float temperature
    ) {
        // Tokenize
        auto tokens = tokenizer->encode(prompt);

        // Generate
        for (int i = 0; i < maxTokens; ++i) {
            auto logits = model->forward(tokens);
            auto nextToken = sample(logits, temperature);

            if (nextToken == tokenizer->eosToken()) break;

            tokens.push_back(nextToken);
        }

        // Decode
        return tokenizer->decode(tokens);
    }
};

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_example_NativeLLM_nativeInit(
    JNIEnv* env,
    jobject thiz,
    jstring modelPath,
    jstring configJson
) {
    const char* path = env->GetStringUTFChars(modelPath, nullptr);
    const char* config = env->GetStringUTFChars(configJson, nullptr);

    auto transformer = std::make_unique<NativeTransformer>();
    if (transformer->initialize(path, config)) {
        return reinterpret_cast<jlong>(transformer.release());
    }

    return 0;
}

}
*/
```

### Hardware-Specific Optimizations

```kotlin
// ARM NEON optimizations
class NeonOptimizedLLM(context: Context) : NativeLLM(context) {

    external fun nativeMatMulNeon(
        a: FloatArray,
        b: FloatArray,
        m: Int,
        n: Int,
        k: Int
    ): FloatArray

    external fun nativeSoftmaxNeon(
        input: FloatArray,
        size: Int
    ): FloatArray

    // Optimized operations
    fun optimizedAttention(
        query: FloatArray,
        key: FloatArray,
        value: FloatArray,
        seqLen: Int,
        hiddenSize: Int
    ): FloatArray {
        // Q * K^T with NEON
        val scores = nativeMatMulNeon(
            query,
            key,
            seqLen,
            seqLen,
            hiddenSize
        )

        // Softmax with NEON
        val weights = nativeSoftmaxNeon(scores, seqLen)

        // Weights * V with NEON
        return nativeMatMulNeon(
            weights,
            value,
            seqLen,
            hiddenSize,
            seqLen
        )
    }
}

// Vulkan compute shader implementation
class VulkanLLM(context: Context) : NativeLLM(context) {

    external fun nativeInitVulkan(): Boolean
    external fun nativeMatMulVulkan(
        a: FloatArray,
        b: FloatArray,
        m: Int,
        n: Int,
        k: Int
    ): FloatArray

    override suspend fun initialize(modelPath: String) {
        super.initialize(modelPath)

        if (!nativeInitVulkan()) {
            throw Exception("Vulkan initialization failed")
        }
    }
}
```

---

## 11. Sample App Architecture

### Project Structure

```
LocalLLMAndroid/
├── app/
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/com/example/localllm/
│   │   │   │   ├── MainActivity.kt
│   │   │   │   ├── ui/
│   │   │   │   │   ├── chat/
│   │   │   │   │   │   ├── ChatFragment.kt
│   │   │   │   │   │   ├── ChatViewModel.kt
│   │   │   │   │   │   └── MessageAdapter.kt
│   │   │   │   │   ├── models/
│   │   │   │   │   │   ├── ModelListFragment.kt
│   │   │   │   │   │   └── ModelManagerViewModel.kt
│   │   │   │   │   └── settings/
│   │   │   │   │       └── SettingsFragment.kt
│   │   │   │   ├── data/
│   │   │   │   │   ├── models/
│   │   │   │   │   ├── repository/
│   │   │   │   │   └── database/
│   │   │   │   ├── llm/
│   │   │   │   │   ├── LLMService.kt
│   │   │   │   │   ├── frameworks/
│   │   │   │   │   │   ├── GeminiNanoService.kt
│   │   │   │   │   │   ├── ONNXRuntimeService.kt
│   │   │   │   │   │   ├── ExecuTorchService.kt
│   │   │   │   │   │   ├── MLCService.kt
│   │   │   │   │   │   ├── TFLiteService.kt
│   │   │   │   │   │   ├── MediaPipeService.kt
│   │   │   │   │   │   ├── LlamaCppService.kt
│   │   │   │   │   │   └── PicoLLMService.kt
│   │   │   │   │   └── LLMFactory.kt
│   │   │   │   └── utils/
│   │   │   │       ├── PerformanceMonitor.kt
│   │   │   │       ├── ModelDownloader.kt
│   │   │   │       └── Extensions.kt
│   │   │   ├── cpp/
│   │   │   │   ├── CMakeLists.txt
│   │   │   │   └── native-lib.cpp
│   │   │   └── res/
│   │   └── androidTest/
│   └── build.gradle
├── gradle/
└── build.gradle
```

### Core Implementation

```kotlin
// LLMService interface
interface LLMService {
    val name: String
    val isInitialized: Boolean

    suspend fun initialize(modelPath: String)
    suspend fun generate(prompt: String, options: GenerationOptions): String
    fun generateStream(prompt: String, options: GenerationOptions): Flow<String>
    fun getModelInfo(): ModelInfo?
    fun release()
}

// Unified LLM Manager
class UnifiedLLMManager(private val context: Context) {
    private val services = mutableMapOf<LLMFramework, LLMService>()
    private var currentService: LLMService? = null

    init {
        registerServices()
    }

    private fun registerServices() {
        services[LLMFramework.GEMINI_NANO] = GeminiNanoService(context)
        services[LLMFramework.ONNX_RUNTIME] = ONNXRuntimeService(context)
        services[LLMFramework.EXECUTORCH] = ExecuTorchService(context)
        services[LLMFramework.MLC_LLM] = MLCService(context)
        services[LLMFramework.TFLITE] = TFLiteService(context)
        services[LLMFramework.MEDIAPIPE] = MediaPipeService(context)
        services[LLMFramework.LLAMA_CPP] = LlamaCppService(context)
        services[LLMFramework.PICOLLM] = PicoLLMService(context)
    }

    suspend fun selectFramework(
        framework: LLMFramework,
        modelPath: String
    ) {
        currentService?.release()

        currentService = services[framework]?.apply {
            initialize(modelPath)
        }
    }

    suspend fun generate(
        prompt: String,
        options: GenerationOptions = GenerationOptions()
    ): String {
        return currentService?.generate(prompt, options)
            ?: throw Exception("No LLM service selected")
    }

    fun generateStream(
        prompt: String,
        options: GenerationOptions = GenerationOptions()
    ): Flow<String> {
        return currentService?.generateStream(prompt, options)
            ?: flow { }
    }
}

// Main Activity with Compose UI
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            LocalLLMTheme {
                val navController = rememberNavController()

                Scaffold(
                    bottomBar = {
                        BottomNavigation(navController)
                    }
                ) { paddingValues ->
                    NavHost(
                        navController = navController,
                        startDestination = "chat",
                        modifier = Modifier.padding(paddingValues)
                    ) {
                        composable("chat") { ChatScreen() }
                        composable("models") { ModelListScreen() }
                        composable("benchmark") { BenchmarkScreen() }
                        composable("settings") { SettingsScreen() }
                    }
                }
            }
        }
    }
}

// Chat ViewModel
class ChatViewModel(
    private val llmManager: UnifiedLLMManager
) : ViewModel() {
    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    fun sendMessage(content: String) {
        viewModelScope.launch {
            // Add user message
            _messages.value += ChatMessage(
                role = ChatRole.USER,
                content = content,
                timestamp = System.currentTimeMillis()
            )

            _isGenerating.value = true

            // Create assistant message
            val assistantMessage = ChatMessage(
                role = ChatRole.ASSISTANT,
                content = "",
                timestamp = System.currentTimeMillis()
            )
            _messages.value += assistantMessage

            try {
                // Stream generation
                llmManager.generateStream(content).collect { token ->
                    _messages.value = _messages.value.map { msg ->
                        if (msg == assistantMessage) {
                            msg.copy(content = msg.content + token)
                        } else msg
                    }
                }
            } catch (e: Exception) {
                _messages.value = _messages.value.map { msg ->
                    if (msg == assistantMessage) {
                        msg.copy(content = "Error: ${e.message}")
                    } else msg
                }
            } finally {
                _isGenerating.value = false
            }
        }
    }
}

// Chat UI with Compose
@Composable
fun ChatScreen(
    viewModel: ChatViewModel = viewModel()
) {
    val messages by viewModel.messages.collectAsState()
    val isGenerating by viewModel.isGenerating.collectAsState()
    var inputText by remember { mutableStateOf("") }

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Messages list
        LazyColumn(
            modifier = Modifier.weight(1f),
            reverseLayout = true
        ) {
            items(messages.reversed()) { message ->
                MessageItem(message)
            }
        }

        // Input bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextField(
                value = inputText,
                onValueChange = { inputText = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Type a message...") },
                enabled = !isGenerating
            )

            IconButton(
                onClick = {
                    if (inputText.isNotBlank() && !isGenerating) {
                        viewModel.sendMessage(inputText)
                        inputText = ""
                    }
                },
                enabled = inputText.isNotBlank() && !isGenerating
            ) {
                Icon(Icons.Default.Send, contentDescription = "Send")
            }
        }
    }
}

@Composable
fun MessageItem(message: ChatMessage) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp),
        horizontalArrangement = if (message.role == ChatRole.USER) {
            Arrangement.End
        } else {
            Arrangement.Start
        }
    ) {
        Card(
            modifier = Modifier
                .widthIn(max = 280.dp)
                .padding(4.dp),
            colors = CardDefaults.cardColors(
                containerColor = if (message.role == ChatRole.USER) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.surface
                }
            )
        ) {
            Text(
                text = message.content,
                modifier = Modifier.padding(12.dp),
                color = if (message.role == ChatRole.USER) {
                    MaterialTheme.colorScheme.onPrimary
                } else {
                    MaterialTheme.colorScheme.onSurface
                }
            )
        }
    }
}
```

### Performance Monitoring

```kotlin
class PerformanceMonitor {
    private var startTime = 0L
    private var firstTokenTime = 0L
    private var tokenCount = 0
    private var memoryBefore = 0L

    fun startMeasurement() {
        startTime = System.currentTimeMillis()
        tokenCount = 0
        memoryBefore = getUsedMemory()
    }

    fun recordFirstToken() {
        if (firstTokenTime == 0L) {
            firstTokenTime = System.currentTimeMillis()
        }
    }

    fun recordToken() {
        tokenCount++
        recordFirstToken()
    }

    fun endMeasurement(): PerformanceMetrics {
        val endTime = System.currentTimeMillis()
        val memoryAfter = getUsedMemory()

        return PerformanceMetrics(
            totalTime = endTime - startTime,
            timeToFirstToken = firstTokenTime - startTime,
            tokensPerSecond = tokenCount.toFloat() / ((endTime - startTime) / 1000f),
            tokenCount = tokenCount,
            memoryUsed = memoryAfter - memoryBefore,
            cpuUsage = getCpuUsage(),
            batteryTemperature = getBatteryTemperature()
        )
    }

    private fun getUsedMemory(): Long {
        val runtime = Runtime.getRuntime()
        return runtime.totalMemory() - runtime.freeMemory()
    }

    private fun getCpuUsage(): Float {
        // Implementation for CPU usage monitoring
        return 0f
    }

    private fun getBatteryTemperature(): Float {
        // Implementation for battery temperature
        return 0f
    }
}

data class PerformanceMetrics(
    val totalTime: Long,
    val timeToFirstToken: Long,
    val tokensPerSecond: Float,
    val tokenCount: Int,
    val memoryUsed: Long,
    val cpuUsage: Float,
    val batteryTemperature: Float
)
```

---

## 12. Model Recommendations

### Small Models (1-3B parameters)

| Model | Size | Quantized | Framework | Use Case |
|-------|------|-----------|-----------|----------|
| Gemini Nano | 1.8B | Built-in | ML Kit | General chat |
| Phi-3-mini | 2.7B | ~1.5GB | ONNX/MLC | Code & chat |
| Gemma-2B | 2B | ~1GB | MediaPipe | Google quality |
| Qwen2.5-1.5B | 1.5B | ~800MB | ONNX/MLC | Multilingual |
| TinyLlama | 1.1B | ~550MB | GGUF | Basic tasks |

### Medium Models (3-7B parameters)

| Model | Size | Quantized | Framework | Use Case |
|-------|------|-----------|-----------|----------|
| Llama-3.2-3B | 3B | ~1.7GB | ExecuTorch | Meta quality |
| Mistral-7B | 7B | ~3.8GB | MLC/GGUF | High quality |
| Vicuna-7B | 7B | ~3.8GB | GGUF | Conversation |
| Falcon-7B | 7B | ~3.8GB | ONNX | Instruction |

### Device-Specific Recommendations

```kotlin
class ModelRecommender {
    data class DeviceProfile(
        val totalRam: Long,
        val availableRam: Long,
        val chipset: String,
        val hasNPU: Boolean,
        val android Version: Int
    )

    fun recommendModel(profile: DeviceProfile): ModelRecommendation {
        return when {
            // Flagship devices (12GB+ RAM, latest chips)
            profile.totalRam > 12_000_000_000L && profile.hasNPU -> {
                ModelRecommendation(
                    model = "Mistral-7B-Instruct",
                    framework = LLMFramework.MLC_LLM,
                    quantization = "Q4_K_M",
                    reason = "Best quality for high-end device"
                )
            }

            // High-end devices (8-12GB RAM)
            profile.totalRam > 8_000_000_000L -> {
                ModelRecommendation(
                    model = "Llama-3.2-3B",
                    framework = LLMFramework.EXECUTORCH,
                    quantization = "INT4",
                    reason = "Balanced performance"
                )
            }

            // Mid-range devices (6-8GB RAM)
            profile.totalRam > 6_000_000_000L -> {
                ModelRecommendation(
                    model = "Gemma-2B",
                    framework = LLMFramework.MEDIAPIPE,
                    quantization = "INT4",
                    reason = "Optimized for mobile"
                )
            }

            // Google Pixel with Gemini Nano
            profile.androidVersion >= 34 &&
            profile.chipset.contains("Tensor") -> {
                ModelRecommendation(
                    model = "Gemini-Nano",
                    framework = LLMFramework.GEMINI_NANO,
                    quantization = "Built-in",
                    reason = "Native Android integration"
                )
            }

            // Entry devices (4-6GB RAM)
            else -> {
                ModelRecommendation(
                    model = "TinyLlama-1.1B",
                    framework = LLMFramework.TFLITE,
                    quantization = "INT8",
                    reason = "Lightweight model"
                )
            }
        }
    }
}
```

---

## 13. Performance Optimization

### Memory Management

```kotlin
class MemoryOptimizer(private val context: Context) {
    private val activityManager = context.getSystemService(
        Context.ACTIVITY_SERVICE
    ) as ActivityManager

    fun optimizeForLLM() {
        // Configure large heap if available
        if (activityManager.largeMemoryClass > activityManager.memoryClass) {
            // Request large heap in manifest
            // android:largeHeap="true"
        }

        // Monitor memory pressure
        context.registerComponentCallbacks(object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                when (level) {
                    ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> {
                        // App in background
                        releaseNonEssentialMemory()
                    }
                    ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> {
                        // System low on memory
                        emergencyMemoryCleanup()
                    }
                }
            }

            override fun onConfigurationChanged(newConfig: Configuration) {}
            override fun onLowMemory() {
                emergencyMemoryCleanup()
            }
        })
    }

    fun getMemoryInfo(): MemoryInfo {
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        return MemoryInfo(
            totalMemory = memInfo.totalMem,
            availableMemory = memInfo.availMem,
            threshold = memInfo.threshold,
            lowMemory = memInfo.lowMemory
        )
    }

    private fun releaseNonEssentialMemory() {
        // Clear image caches
        Glide.get(context).clearMemory()

        // Clear WebView cache if used
        WebView(context).clearCache(true)

        // Run garbage collection
        System.gc()
    }
}
```

### Battery Optimization

```kotlin
class BatteryOptimizer(private val context: Context) {
    private val batteryManager = context.getSystemService(
        Context.BATTERY_SERVICE
    ) as BatteryManager

    private val powerManager = context.getSystemService(
        Context.POWER_SERVICE
    ) as PowerManager

    fun getOptimalConfiguration(): LLMConfiguration {
        val batteryLevel = batteryManager.getIntProperty(
            BatteryManager.BATTERY_PROPERTY_CAPACITY
        )

        val isCharging = batteryManager.isCharging
        val isPowerSaveMode = powerManager.isPowerSaveMode

        return when {
            isCharging -> {
                // Maximum performance when charging
                LLMConfiguration(
                    threads = Runtime.getRuntime().availableProcessors(),
                    maxTokens = 500,
                    useGPU = true,
                    batchSize = 8
                )
            }

            isPowerSaveMode || batteryLevel < 20 -> {
                // Minimum power consumption
                LLMConfiguration(
                    threads = 2,
                    maxTokens = 100,
                    useGPU = false,
                    batchSize = 1
                )
            }

            batteryLevel < 50 -> {
                // Balanced mode
                LLMConfiguration(
                    threads = 4,
                    maxTokens = 200,
                    useGPU = false,
                    batchSize = 2
                )
            }

            else -> {
                // Normal performance
                LLMConfiguration(
                    threads = 6,
                    maxTokens = 300,
                    useGPU = true,
                    batchSize = 4
                )
            }
        }
    }
}
```

### Thermal Management

```kotlin
class ThermalManager(private val context: Context) {
    private val powerManager = context.getSystemService(
        Context.POWER_SERVICE
    ) as PowerManager

    fun monitorThermalState(
        onThrottling: (ThermalStatus) -> Unit
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            powerManager.addThermalStatusListener { status ->
                when (status) {
                    PowerManager.THERMAL_STATUS_CRITICAL,
                    PowerManager.THERMAL_STATUS_EMERGENCY,
                    PowerManager.THERMAL_STATUS_SHUTDOWN -> {
                        onThrottling(ThermalStatus.CRITICAL)
                    }

                    PowerManager.THERMAL_STATUS_SEVERE -> {
                        onThrottling(ThermalStatus.SEVERE)
                    }

                    PowerManager.THERMAL_STATUS_MODERATE -> {
                        onThrottling(ThermalStatus.MODERATE)
                    }

                    else -> {
                        onThrottling(ThermalStatus.NORMAL)
                    }
                }
            }
        }
    }

    fun adjustPerformanceForThermal(status: ThermalStatus): LLMConfiguration {
        return when (status) {
            ThermalStatus.CRITICAL -> {
                // Minimum performance to cool down
                LLMConfiguration(
                    threads = 1,
                    maxTokens = 50,
                    useGPU = false,
                    inferenceDelay = 100 // Add delay between inferences
                )
            }

            ThermalStatus.SEVERE -> {
                LLMConfiguration(
                    threads = 2,
                    maxTokens = 100,
                    useGPU = false,
                    inferenceDelay = 50
                )
            }

            ThermalStatus.MODERATE -> {
                LLMConfiguration(
                    threads = 4,
                    maxTokens = 150,
                    useGPU = true,
                    inferenceDelay = 0
                )
            }

            ThermalStatus.NORMAL -> {
                // Full performance
                getDefaultConfiguration()
            }
        }
    }
}

enum class ThermalStatus {
    NORMAL, MODERATE, SEVERE, CRITICAL
}
```

---

## 14. Troubleshooting

### Common Issues and Solutions

```kotlin
class LLMTroubleshooter {

    fun diagnoseIssue(error: Exception): Diagnosis {
        return when (error) {
            is OutOfMemoryError -> {
                Diagnosis(
                    issue = "Out of memory",
                    solutions = listOf(
                        "Use a smaller or more quantized model",
                        "Close other apps to free memory",
                        "Enable large heap in manifest",
                        "Reduce context size or batch size"
                    ),
                    code = DiagnosisCode.MEMORY_ISSUE
                )
            }

            is ModelLoadException -> {
                Diagnosis(
                    issue = "Failed to load model",
                    solutions = listOf(
                        "Check model file exists and is not corrupted",
                        "Verify model format matches framework",
                        "Ensure sufficient storage space",
                        "Check file permissions"
                    ),
                    code = DiagnosisCode.MODEL_LOAD_ERROR
                )
            }

            is UnsupportedOperationException -> {
                if (error.message?.contains("GPU") == true) {
                    Diagnosis(
                        issue = "GPU not supported",
                        solutions = listOf(
                            "Fall back to CPU execution",
                            "Use a different framework",
                            "Check GPU driver compatibility"
                        ),
                        code = DiagnosisCode.HARDWARE_INCOMPATIBLE
                    )
                } else {
                    defaultDiagnosis(error)
                }
            }

            else -> defaultDiagnosis(error)
        }
    }

    fun performSystemCheck(): SystemCheckResult {
        val checks = mutableListOf<Check>()

        // Memory check
        val memInfo = getMemoryInfo()
        checks.add(
            Check(
                name = "Available Memory",
                passed = memInfo.availableMemory > 1_000_000_000L,
                details = "Available: ${formatBytes(memInfo.availableMemory)}"
            )
        )

        // Storage check
        val storageInfo = getStorageInfo()
        checks.add(
            Check(
                name = "Storage Space",
                passed = storageInfo.availableSpace > 2_000_000_000L,
                details = "Available: ${formatBytes(storageInfo.availableSpace)}"
            )
        )

        // CPU check
        checks.add(
            Check(
                name = "CPU Cores",
                passed = Runtime.getRuntime().availableProcessors() >= 4,
                details = "Cores: ${Runtime.getRuntime().availableProcessors()}"
            )
        )

        // Android version check
        checks.add(
            Check(
                name = "Android Version",
                passed = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N,
                details = "API Level: ${Build.VERSION.SDK_INT}"
            )
        )

        return SystemCheckResult(
            allPassed = checks.all { it.passed },
            checks = checks
        )
    }
}

data class Diagnosis(
    val issue: String,
    val solutions: List<String>,
    val code: DiagnosisCode
)

enum class DiagnosisCode {
    MEMORY_ISSUE,
    MODEL_LOAD_ERROR,
    HARDWARE_INCOMPATIBLE,
    PERMISSION_DENIED,
    NETWORK_ERROR,
    UNKNOWN
}
```

### Debug Utilities

```kotlin
object LLMDebugger {
    private const val TAG = "LLMDebug"
    var isEnabled = BuildConfig.DEBUG

    fun log(message: String, tag: String = TAG) {
        if (isEnabled) {
            Log.d(tag, message)
        }
    }

    fun logPerformance(metrics: PerformanceMetrics) {
        if (isEnabled) {
            Log.d(TAG, """
                Performance Metrics:
                - Total time: ${metrics.totalTime}ms
                - First token: ${metrics.timeToFirstToken}ms
                - Tokens/sec: ${"%.2f".format(metrics.tokensPerSecond)}
                - Memory used: ${formatBytes(metrics.memoryUsed)}
                - CPU usage: ${"%.1f".format(metrics.cpuUsage)}%
                - Battery temp: ${"%.1f".format(metrics.batteryTemperature)}°C
            """.trimIndent())
        }
    }

    fun dumpModelInfo(modelInfo: ModelInfo) {
        if (isEnabled) {
            Log.d(TAG, """
                Model Information:
                - Name: ${modelInfo.name}
                - Size: ${formatBytes(modelInfo.sizeBytes)}
                - Parameters: ${formatNumber(modelInfo.parameters)}
                - Quantization: ${modelInfo.quantization}
                - Format: ${modelInfo.format}
            """.trimIndent())
        }
    }

    fun profileOperation(
        operationName: String,
        block: () -> Unit
    ) {
        if (isEnabled) {
            val startTime = System.currentTimeMillis()
            val startMemory = Runtime.getRuntime().totalMemory() -
                            Runtime.getRuntime().freeMemory()

            block()

            val endTime = System.currentTimeMillis()
            val endMemory = Runtime.getRuntime().totalMemory() -
                          Runtime.getRuntime().freeMemory()

            Log.d(TAG, """
                Operation: $operationName
                - Time: ${endTime - startTime}ms
                - Memory delta: ${formatBytes(endMemory - startMemory)}
            """.trimIndent())
        }
    }
}
```

---

## Conclusion

This comprehensive guide covers all major frameworks for running LLMs locally on Android. Each framework offers unique advantages:

- **Gemini Nano**: Best for Google ecosystem integration with ML Kit
- **ONNX Runtime**: Excellent cross-platform support
- **ExecuTorch**: Optimal for PyTorch models
- **MLC-LLM**: Universal deployment with great optimization
- **TensorFlow Lite**: Mature ecosystem with good tooling
- **MediaPipe**: Specialized for specific models
- **llama.cpp**: Most efficient CPU implementation
- **picoLLM**: Compressed models with easy API

Choose based on your specific requirements for model support, performance needs, and target devices.
