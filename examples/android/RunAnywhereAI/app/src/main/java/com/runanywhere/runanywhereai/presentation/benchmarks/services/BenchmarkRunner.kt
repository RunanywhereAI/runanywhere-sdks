package com.runanywhere.runanywhereai.presentation.benchmarks.services

import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkProgressUpdate
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkResult
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkScenario
import com.runanywhere.runanywhereai.presentation.benchmarks.models.ComponentModelInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.availableModels
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

// -- Provider Interface --

interface BenchmarkScenarioProvider {
    val category: BenchmarkCategory
    fun scenarios(): List<BenchmarkScenario>
    suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics
}

// -- Runner Errors --

sealed class BenchmarkRunnerError(message: String) : Exception(message) {
    class NoModelsAvailable(skippedCategories: List<BenchmarkCategory>) : BenchmarkRunnerError(
        "No downloaded models found for: ${skippedCategories.joinToString { it.displayName }}. Download models first from the Models tab.",
    )

    class FetchModelsFailed(cause: Throwable) : BenchmarkRunnerError(
        "Failed to fetch available models: ${cause.localizedMessage ?: cause.message ?: "Unknown error"}",
    )
}

// -- Preflight Result --

data class BenchmarkPreflightResult(
    val availableCategories: Map<BenchmarkCategory, List<ModelInfo>>,
    val skippedCategories: List<BenchmarkCategory>,
    val totalWorkItems: Int,
)

// -- Runner --

class BenchmarkRunner {

    private val providers: Map<BenchmarkCategory, BenchmarkScenarioProvider>

    init {
        val all = listOf(
            LLMBenchmarkProvider(),
            STTBenchmarkProvider(),
            TTSBenchmarkProvider(),
            VLMBenchmarkProvider(),
        )
        providers = all.associateBy { it.category }
    }

    // -- Preflight Check --

    suspend fun preflight(categories: Set<BenchmarkCategory>): BenchmarkPreflightResult {
        val allModels: List<ModelInfo> = try {
            RunAnywhere.availableModels()
        } catch (e: Exception) {
            throw BenchmarkRunnerError.FetchModelsFailed(e)
        }

        val available = mutableMapOf<BenchmarkCategory, List<ModelInfo>>()
        val skipped = mutableListOf<BenchmarkCategory>()

        for (category in BenchmarkCategory.entries) {
            if (category !in categories) continue
            if (providers[category] == null) {
                skipped.add(category)
                continue
            }
            val models = allModels.filter {
                it.category == category.modelCategory && it.isDownloaded && !it.isBuiltIn
            }
            if (models.isEmpty()) {
                skipped.add(category)
            } else {
                available[category] = models
            }
        }

        var totalItems = 0
        for ((category, models) in available) {
            val scenarioCount = providers[category]?.scenarios()?.size ?: 0
            totalItems += models.size * scenarioCount
        }

        return BenchmarkPreflightResult(
            availableCategories = available,
            skippedCategories = skipped,
            totalWorkItems = totalItems,
        )
    }

    // -- Run Result (includes skipped categories) --

    data class BenchmarkRunResult(
        val results: List<BenchmarkResult>,
        val skippedCategories: List<BenchmarkCategory>,
    )

    // -- Run --

    suspend fun runBenchmarks(
        categories: Set<BenchmarkCategory>,
        onProgress: (BenchmarkProgressUpdate) -> Unit,
    ): BenchmarkRunResult {
        val preflightResult = preflight(categories)

        if (preflightResult.availableCategories.isEmpty()) {
            throw BenchmarkRunnerError.NoModelsAvailable(preflightResult.skippedCategories)
        }

        data class WorkItem(
            val category: BenchmarkCategory,
            val model: ModelInfo,
            val scenario: BenchmarkScenario,
        )

        val workItems = mutableListOf<WorkItem>()
        for (category in BenchmarkCategory.entries) {
            if (category !in categories) continue
            val provider = providers[category] ?: continue
            val models = preflightResult.availableCategories[category] ?: continue
            val scenarioList = provider.scenarios()
            for (model in models) {
                for (scenario in scenarioList) {
                    workItems.add(WorkItem(category, model, scenario))
                }
            }
        }

        val total = workItems.size
        val results = mutableListOf<BenchmarkResult>()

        for ((index, item) in workItems.withIndex()) {
            coroutineContext.ensureActive()

            onProgress(
                BenchmarkProgressUpdate(
                    completedCount = index,
                    totalCount = total,
                    currentScenario = item.scenario.name,
                    currentModel = item.model.name,
                ),
            )

            val metrics: BenchmarkMetrics = try {
                val provider = providers[item.category] ?: continue
                provider.execute(
                    scenario = item.scenario,
                    model = item.model,
                    deviceInfo = BenchmarkDeviceInfo(
                        modelName = "",
                        chipName = "",
                        totalMemoryBytes = 0,
                        availableMemoryBytes = SyntheticInputGenerator.availableMemoryBytes(),
                        osVersion = "",
                    ),
                )
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                BenchmarkMetrics(
                    errorMessage = "${item.category.displayName} [${item.model.name}]: ${e.localizedMessage ?: e.message ?: "Unknown error"}",
                )
            }

            results.add(
                BenchmarkResult(
                    category = item.category,
                    scenario = item.scenario,
                    modelInfo = ComponentModelInfo.from(item.model),
                    metrics = metrics,
                ),
            )
        }

        onProgress(
            BenchmarkProgressUpdate(
                completedCount = total,
                totalCount = total,
                currentScenario = "Done",
                currentModel = "",
            ),
        )

        return BenchmarkRunResult(
            results = results,
            skippedCategories = preflightResult.skippedCategories,
        )
    }
}
