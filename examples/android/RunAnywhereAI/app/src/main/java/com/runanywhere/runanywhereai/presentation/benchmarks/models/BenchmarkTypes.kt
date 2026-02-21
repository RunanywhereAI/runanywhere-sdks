package com.runanywhere.runanywhereai.presentation.benchmarks.models

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.ui.graphics.vector.ImageVector
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

// -- Benchmark Category --

@Serializable
enum class BenchmarkCategory(val value: String) {
    @SerialName("llm") LLM("llm"),
    @SerialName("stt") STT("stt"),
    @SerialName("tts") TTS("tts"),
    @SerialName("vlm") VLM("vlm"),
    ;

    val displayName: String
        get() = when (this) {
            LLM -> "LLM"
            STT -> "STT"
            TTS -> "TTS"
            VLM -> "VLM"
        }

    val icon: ImageVector
        get() = when (this) {
            LLM -> Icons.Filled.ChatBubble
            STT -> Icons.Filled.GraphicEq
            TTS -> Icons.Filled.VolumeUp
            VLM -> Icons.Filled.Visibility
        }

    val modelCategory: ModelCategory
        get() = when (this) {
            LLM -> ModelCategory.LANGUAGE
            STT -> ModelCategory.SPEECH_RECOGNITION
            TTS -> ModelCategory.SPEECH_SYNTHESIS
            VLM -> ModelCategory.MULTIMODAL
        }
}

// -- Benchmark Run Status --

@Serializable
enum class BenchmarkRunStatus(val value: String) {
    @SerialName("running") RUNNING("running"),
    @SerialName("completed") COMPLETED("completed"),
    @SerialName("failed") FAILED("failed"),
    @SerialName("cancelled") CANCELLED("cancelled"),
}

// -- Benchmark Scenario --

@Serializable
data class BenchmarkScenario(
    val name: String,
    val category: BenchmarkCategory,
) {
    val id: String get() = "${category.value}_$name"
}

// -- Component Model Info (snapshot of ModelInfo for persistence) --

@Serializable
data class ComponentModelInfo(
    val id: String,
    val name: String,
    val framework: String,
    val category: String,
) {
    companion object {
        fun from(model: ModelInfo): ComponentModelInfo = ComponentModelInfo(
            id = model.id,
            name = model.name,
            framework = model.framework.displayName,
            category = model.category.value,
        )
    }
}

// -- Device Info (snapshot for persistence) --

@Serializable
data class BenchmarkDeviceInfo(
    val modelName: String,
    val chipName: String,
    val totalMemoryBytes: Long,
    val availableMemoryBytes: Long,
    val osVersion: String,
)

// -- Benchmark Metrics --

@Serializable
data class BenchmarkMetrics(
    // Common
    val endToEndLatencyMs: Double = 0.0,
    val loadTimeMs: Double = 0.0,
    val warmupTimeMs: Double = 0.0,
    val memoryDeltaBytes: Long = 0,

    // LLM-specific
    val ttftMs: Double? = null,
    val tokensPerSecond: Double? = null,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,

    // STT-specific
    val audioLengthSeconds: Double? = null,
    val realTimeFactor: Double? = null,

    // TTS-specific
    val audioDurationSeconds: Double? = null,
    val charactersProcessed: Int? = null,

    // VLM-specific
    val promptTokens: Int? = null,
    val completionTokens: Int? = null,

    // Error info
    val errorMessage: String? = null,
) {
    val didSucceed: Boolean get() = errorMessage == null
}

// -- Benchmark Result --

@Serializable
data class BenchmarkResult(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: Long = System.currentTimeMillis(),
    val category: BenchmarkCategory,
    val scenario: BenchmarkScenario,
    val modelInfo: ComponentModelInfo,
    val metrics: BenchmarkMetrics,
)

// -- Benchmark Run --

@Serializable
data class BenchmarkRun(
    val id: String = UUID.randomUUID().toString(),
    val startedAt: Long = System.currentTimeMillis(),
    val completedAt: Long? = null,
    val results: List<BenchmarkResult> = emptyList(),
    val status: BenchmarkRunStatus = BenchmarkRunStatus.RUNNING,
    val deviceInfo: BenchmarkDeviceInfo,
) {
    val durationSeconds: Double?
        get() {
            val completed = completedAt ?: return null
            return (completed - startedAt) / 1000.0
        }
}

// -- Progress Update --

data class BenchmarkProgressUpdate(
    val completedCount: Int,
    val totalCount: Int,
    val currentScenario: String,
    val currentModel: String,
) {
    val progress: Float
        get() = if (totalCount > 0) completedCount.toFloat() / totalCount.toFloat() else 0f
}
