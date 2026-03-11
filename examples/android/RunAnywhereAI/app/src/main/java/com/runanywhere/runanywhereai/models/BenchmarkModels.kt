package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
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

    val description: String
        get() = when (this) {
            LLM -> "Language model generation"
            STT -> "Speech recognition"
            TTS -> "Speech synthesis"
            VLM -> "Vision-language model"
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

// -- Component Model Info (snapshot for persistence) --

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
@Immutable
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
@Immutable
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
@Immutable
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

@Immutable
data class BenchmarkProgressUpdate(
    val completedCount: Int,
    val totalCount: Int,
    val currentScenario: String,
    val currentModel: String,
) {
    val progress: Float
        get() = if (totalCount > 0) completedCount.toFloat() / totalCount.toFloat() else 0f
}

// -- UI State --

@Immutable
sealed interface BenchmarkUiState {
    data object Loading : BenchmarkUiState

    @Immutable
    data class Ready(
        val isRunning: Boolean = false,
        val progress: Float = 0f,
        val currentScenario: String = "",
        val currentModel: String = "",
        val completedCount: Int = 0,
        val totalCount: Int = 0,
        val pastRuns: ImmutableList<BenchmarkRun> = persistentListOf(),
        val selectedCategories: Set<BenchmarkCategory> = BenchmarkCategory.entries.toSet(),
        val errorMessage: String? = null,
        val showClearConfirmation: Boolean = false,
        val copiedToastMessage: String? = null,
        val skippedCategoriesMessage: String? = null,
    ) : BenchmarkUiState

    @Immutable
    data class Error(val message: String) : BenchmarkUiState
}

// -- Benchmark Event (one-shot) --

sealed interface BenchmarkEvent {
    data class ShowSnackbar(val message: String) : BenchmarkEvent
    data class ShareFile(val intent: android.content.Intent) : BenchmarkEvent
}

// -- Export Format --

enum class BenchmarkExportFormat(val displayName: String) {
    MARKDOWN("Markdown"),
    JSON("JSON"),
}
