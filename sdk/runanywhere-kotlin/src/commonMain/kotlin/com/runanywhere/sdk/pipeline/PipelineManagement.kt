package com.runanywhere.sdk.pipeline

import com.runanywhere.sdk.components.base.Component
import com.runanywhere.sdk.components.base.ComponentInput
import com.runanywhere.sdk.components.base.ComponentOutput
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.Contextual
import kotlinx.serialization.Serializable
import kotlin.reflect.KClass

/**
 * Pipeline management system for orchestrating multi-component AI workflows
 * Matches iOS pipeline capabilities with enhanced Kotlin features
 */

/**
 * Pipeline step configuration
 */
@Serializable
data class PipelineStep(
    /** Unique identifier for this step */
    val id: String,

    /** Human-readable name */
    val name: String,

    /** Component class name to execute */
    val componentType: String,

    /** Input data mapping from previous steps */
    val inputMapping: Map<String, String> = emptyMap(),

    /** Output data mapping for next steps */
    val outputMapping: Map<String, String> = emptyMap(),

    /** Whether this step can be skipped on error */
    val optional: Boolean = false,

    /** Maximum retry attempts */
    val maxRetries: Int = 0,

    /** Timeout in milliseconds */
    val timeoutMs: Long = 60_000L,

    /** Dependencies - step IDs that must complete before this step */
    val dependencies: List<String> = emptyList(),

    /** Parallel execution group (steps with same group run in parallel) */
    val parallelGroup: String? = null
)

/**
 * Pipeline configuration
 */
@Serializable
data class PipelineConfig(
    /** Unique pipeline identifier */
    val id: String,

    /** Pipeline name */
    val name: String,

    /** Pipeline description */
    val description: String? = null,

    /** Pipeline steps in execution order */
    val steps: List<PipelineStep>,

    /** Global timeout for entire pipeline */
    val globalTimeoutMs: Long = 300_000L, // 5 minutes

    /** Whether to stop on first error */
    val stopOnError: Boolean = true,

    /** Maximum concurrent parallel steps */
    val maxConcurrentSteps: Int = 3,

    /** Pipeline metadata */
    val metadata: Map<String, String> = emptyMap()
) {
    /**
     * Validate the pipeline configuration
     */
    fun validate() {
        require(id.isNotBlank()) { "Pipeline ID cannot be blank" }
        require(name.isNotBlank()) { "Pipeline name cannot be blank" }
        require(steps.isNotEmpty()) { "Pipeline must have at least one step" }
        require(globalTimeoutMs > 0) { "Global timeout must be positive" }
        require(maxConcurrentSteps > 0) { "Max concurrent steps must be positive" }

        // Validate step dependencies
        val stepIds = steps.map { it.id }.toSet()
        steps.forEach { step ->
            step.dependencies.forEach { depId ->
                require(stepIds.contains(depId)) {
                    "Step '${step.id}' depends on non-existent step '$depId'"
                }
            }
        }

        // Check for circular dependencies
        validateNoCycles()
    }

    private fun validateNoCycles() {
        val visited = mutableSetOf<String>()
        val recursionStack = mutableSetOf<String>()

        fun hasCycle(stepId: String): Boolean {
            if (recursionStack.contains(stepId)) return true
            if (visited.contains(stepId)) return false

            visited.add(stepId)
            recursionStack.add(stepId)

            val step = steps.find { it.id == stepId }
            step?.dependencies?.forEach { depId ->
                if (hasCycle(depId)) return true
            }

            recursionStack.remove(stepId)
            return false
        }

        steps.forEach { step ->
            if (hasCycle(step.id)) {
                throw SDKError.ValidationFailed("Circular dependency detected involving step '${step.id}'")
            }
        }
    }
}

/**
 * Pipeline execution result
 */
@Serializable
data class PipelineExecutionResult(
    /** Pipeline configuration */
    val pipelineConfig: PipelineConfig,

    /** Execution status */
    val status: PipelineStatus,

    /** Step results */
    val stepResults: Map<String, PipelineStepResult>,

    /** Overall execution time in milliseconds */
    val executionTimeMs: Long,

    /** Start timestamp */
    val startTime: Long,

    /** End timestamp */
    val endTime: Long,

    /** Error information if pipeline failed */
    val error: String? = null,

    /** Final output data */
    val outputData: Map<String, @Contextual Any> = emptyMap()
) {
    /**
     * Check if pipeline execution was successful
     */
    val isSuccessful: Boolean
        get() = status == PipelineStatus.COMPLETED

    /**
     * Get successful step count
     */
    val successfulSteps: Int
        get() = stepResults.values.count { it.status == PipelineStepStatus.COMPLETED }

    /**
     * Get failed step count
     */
    val failedSteps: Int
        get() = stepResults.values.count { it.status == PipelineStepStatus.FAILED }
}

/**
 * Pipeline step execution result
 */
@Serializable
data class PipelineStepResult(
    /** Step configuration */
    val step: PipelineStep,

    /** Execution status */
    val status: PipelineStepStatus,

    /** Execution time in milliseconds */
    val executionTimeMs: Long,

    /** Start timestamp */
    val startTime: Long,

    /** End timestamp */
    val endTime: Long,

    /** Number of retry attempts */
    val retryCount: Int = 0,

    /** Output data from this step */
    val outputData: Map<String, @Contextual Any> = emptyMap(),

    /** Error information if step failed */
    val error: String? = null
)

/**
 * Pipeline execution status
 */
@Serializable
enum class PipelineStatus(val value: String) {
    PENDING("pending"),
    RUNNING("running"),
    COMPLETED("completed"),
    FAILED("failed"),
    CANCELLED("cancelled"),
    TIMEOUT("timeout");

    companion object {
        fun fromValue(value: String): PipelineStatus? {
            return values().find { it.value == value }
        }
    }
}

/**
 * Pipeline step execution status
 */
@Serializable
enum class PipelineStepStatus(val value: String) {
    PENDING("pending"),
    RUNNING("running"),
    COMPLETED("completed"),
    FAILED("failed"),
    SKIPPED("skipped"),
    TIMEOUT("timeout");

    companion object {
        fun fromValue(value: String): PipelineStepStatus? {
            return values().find { it.value == value }
        }
    }
}

/**
 * Pipeline execution context
 */
data class PipelineExecutionContext(
    /** Pipeline configuration */
    val config: PipelineConfig,

    /** Available components by type */
    val components: Map<String, Component>,

    /** Initial input data */
    val initialData: Map<String, Any> = emptyMap(),

    /** Current execution state */
    var currentData: MutableMap<String, Any> = mutableMapOf(),

    /** Step execution results */
    val stepResults: MutableMap<String, PipelineStepResult> = mutableMapOf(),

    /** Execution start time */
    val startTime: Long = getCurrentTimeMillis()
)

/**
 * Pipeline executor interface
 */
interface PipelineExecutor {
    /** Execute a pipeline */
    suspend fun execute(
        config: PipelineConfig,
        components: Map<String, Component>,
        initialData: Map<String, Any> = emptyMap()
    ): PipelineExecutionResult

    /** Execute pipeline with streaming progress updates */
    fun executeWithProgress(
        config: PipelineConfig,
        components: Map<String, Component>,
        initialData: Map<String, Any> = emptyMap()
    ): Flow<PipelineProgressUpdate>

    /** Cancel pipeline execution */
    suspend fun cancel(pipelineId: String): Boolean

    /** Get current execution status */
    suspend fun getStatus(pipelineId: String): PipelineStatus?
}

/**
 * Pipeline progress update
 */
@Serializable
data class PipelineProgressUpdate(
    /** Pipeline ID */
    val pipelineId: String,

    /** Current step being executed */
    val currentStep: String? = null,

    /** Completed steps count */
    val completedSteps: Int,

    /** Total steps count */
    val totalSteps: Int,

    /** Progress percentage (0-100) */
    val progressPercentage: Double,

    /** Current status */
    val status: PipelineStatus,

    /** Timestamp */
    val timestamp: Long = getCurrentTimeMillis(),

    /** Additional message */
    val message: String? = null
)

/**
 * Default pipeline executor implementation
 */
class DefaultPipelineExecutor : PipelineExecutor {
    private val activePipelines = mutableMapOf<String, PipelineExecutionContext>()

    override suspend fun execute(
        config: PipelineConfig,
        components: Map<String, Component>,
        initialData: Map<String, Any>
    ): PipelineExecutionResult {
        config.validate()

        val context = PipelineExecutionContext(
            config = config,
            components = components,
            initialData = initialData
        )
        context.currentData.putAll(initialData)

        activePipelines[config.id] = context

        return try {
            executeInternal(context)
        } finally {
            activePipelines.remove(config.id)
        }
    }

    override fun executeWithProgress(
        config: PipelineConfig,
        components: Map<String, Component>,
        initialData: Map<String, Any>
    ): Flow<PipelineProgressUpdate> = flow {
        config.validate()

        val context = PipelineExecutionContext(
            config = config,
            components = components,
            initialData = initialData
        )
        context.currentData.putAll(initialData)

        activePipelines[config.id] = context

        try {
            // Emit initial progress
            emit(PipelineProgressUpdate(
                pipelineId = config.id,
                completedSteps = 0,
                totalSteps = config.steps.size,
                progressPercentage = 0.0,
                status = PipelineStatus.RUNNING,
                message = "Starting pipeline execution"
            ))

            // Execute steps with progress updates
            val result = executeInternalWithProgress(context) { progress ->
                kotlinx.coroutines.runBlocking { emit(progress) }
            }

            // Emit final progress
            emit(PipelineProgressUpdate(
                pipelineId = config.id,
                completedSteps = result.successfulSteps,
                totalSteps = config.steps.size,
                progressPercentage = 100.0,
                status = result.status,
                message = if (result.isSuccessful) "Pipeline completed successfully" else "Pipeline failed"
            ))
        } finally {
            activePipelines.remove(config.id)
        }
    }

    override suspend fun cancel(pipelineId: String): Boolean {
        val context = activePipelines[pipelineId] ?: return false
        // In a real implementation, we would set a cancellation flag
        // and check it during step execution
        activePipelines.remove(pipelineId)
        return true
    }

    override suspend fun getStatus(pipelineId: String): PipelineStatus? {
        return activePipelines[pipelineId]?.let { PipelineStatus.RUNNING }
    }

    private suspend fun executeInternal(context: PipelineExecutionContext): PipelineExecutionResult {
        val startTime = getCurrentTimeMillis()
        var status = PipelineStatus.RUNNING
        var error: String? = null

        try {
            // Execute steps in order, respecting dependencies
            val executionPlan = createExecutionPlan(context.config.steps)

            for (batch in executionPlan) {
                // Execute steps in current batch (can be parallel)
                val batchResults = executeBatch(batch, context)

                // Check for failures
                val failedSteps = batchResults.filter { it.status == PipelineStepStatus.FAILED }
                if (failedSteps.isNotEmpty() && context.config.stopOnError) {
                    status = PipelineStatus.FAILED
                    error = "Step '${failedSteps.first().step.id}' failed: ${failedSteps.first().error}"
                    break
                }
            }

            if (status == PipelineStatus.RUNNING) {
                status = PipelineStatus.COMPLETED
            }

        } catch (e: Exception) {
            status = PipelineStatus.FAILED
            error = e.message
        }

        val endTime = getCurrentTimeMillis()

        return PipelineExecutionResult(
            pipelineConfig = context.config,
            status = status,
            stepResults = context.stepResults,
            executionTimeMs = endTime - startTime,
            startTime = startTime,
            endTime = endTime,
            error = error,
            outputData = context.currentData
        )
    }

    private suspend fun executeInternalWithProgress(
        context: PipelineExecutionContext,
        progressCallback: suspend (PipelineProgressUpdate) -> Unit
    ): PipelineExecutionResult {
        val startTime = getCurrentTimeMillis()
        var status = PipelineStatus.RUNNING
        var error: String? = null
        var completedSteps = 0

        try {
            val executionPlan = createExecutionPlan(context.config.steps)

            for (batch in executionPlan) {
                // Execute steps in current batch
                val batchResults = executeBatch(batch, context)
                completedSteps += batchResults.size

                // Emit progress update
                progressCallback(PipelineProgressUpdate(
                    pipelineId = context.config.id,
                    currentStep = batch.firstOrNull()?.id,
                    completedSteps = completedSteps,
                    totalSteps = context.config.steps.size,
                    progressPercentage = (completedSteps.toDouble() / context.config.steps.size) * 100.0,
                    status = PipelineStatus.RUNNING,
                    message = "Completed batch of ${batch.size} steps"
                ))

                // Check for failures
                val failedSteps = batchResults.filter { it.status == PipelineStepStatus.FAILED }
                if (failedSteps.isNotEmpty() && context.config.stopOnError) {
                    status = PipelineStatus.FAILED
                    error = "Step '${failedSteps.first().step.id}' failed: ${failedSteps.first().error}"
                    break
                }
            }

            if (status == PipelineStatus.RUNNING) {
                status = PipelineStatus.COMPLETED
            }

        } catch (e: Exception) {
            status = PipelineStatus.FAILED
            error = e.message
        }

        val endTime = getCurrentTimeMillis()

        return PipelineExecutionResult(
            pipelineConfig = context.config,
            status = status,
            stepResults = context.stepResults,
            executionTimeMs = endTime - startTime,
            startTime = startTime,
            endTime = endTime,
            error = error,
            outputData = context.currentData
        )
    }

    private fun createExecutionPlan(steps: List<PipelineStep>): List<List<PipelineStep>> {
        // Create batches based on dependencies and parallel groups
        val remaining = steps.toMutableList()
        val executed = mutableSetOf<String>()
        val batches = mutableListOf<List<PipelineStep>>()

        while (remaining.isNotEmpty()) {
            val readySteps = remaining.filter { step ->
                step.dependencies.all { depId -> executed.contains(depId) }
            }

            if (readySteps.isEmpty()) {
                throw SDKError.InvalidState("Unable to resolve step dependencies")
            }

            batches.add(readySteps)
            remaining.removeAll(readySteps)
            executed.addAll(readySteps.map { it.id })
        }

        return batches
    }

    private suspend fun executeBatch(
        batch: List<PipelineStep>,
        context: PipelineExecutionContext
    ): List<PipelineStepResult> {
        // For simplicity, execute sequentially
        // In a full implementation, we would execute parallel groups concurrently
        return batch.map { step ->
            executeStep(step, context)
        }
    }

    private suspend fun executeStep(
        step: PipelineStep,
        context: PipelineExecutionContext
    ): PipelineStepResult {
        val startTime = getCurrentTimeMillis()
        var status = PipelineStepStatus.RUNNING
        var error: String? = null
        var retryCount = 0
        val outputData = mutableMapOf<String, Any>()

        try {
            val component = context.components[step.componentType]
                ?: throw SDKError.ComponentNotInitialized("Component '${step.componentType}' not found")

            // Ensure component is ready
            if (component.state != ComponentState.READY) {
                throw SDKError.ComponentNotReady("Component '${step.componentType}' is not ready")
            }

            // Prepare input data based on mapping
            val inputData = prepareInputData(step, context)

            // Execute with retries
            while (retryCount <= step.maxRetries) {
                try {
                    // In a real implementation, we would call the component's process method
                    // For now, we simulate execution
                    simulateStepExecution(step, inputData, outputData)

                    status = PipelineStepStatus.COMPLETED
                    break
                } catch (e: Exception) {
                    retryCount++
                    if (retryCount > step.maxRetries) {
                        throw e
                    }
                    kotlinx.coroutines.delay(1000) // Wait before retry
                }
            }

            // Apply output mapping
            applyOutputMapping(step, outputData, context)

        } catch (e: Exception) {
            status = if (step.optional) PipelineStepStatus.SKIPPED else PipelineStepStatus.FAILED
            error = e.message
        }

        val endTime = getCurrentTimeMillis()
        val result = PipelineStepResult(
            step = step,
            status = status,
            executionTimeMs = endTime - startTime,
            startTime = startTime,
            endTime = endTime,
            retryCount = retryCount,
            outputData = outputData,
            error = error
        )

        context.stepResults[step.id] = result
        return result
    }

    private fun prepareInputData(step: PipelineStep, context: PipelineExecutionContext): Map<String, Any> {
        val inputData = mutableMapOf<String, Any>()

        step.inputMapping.forEach { (targetKey, sourceKey) ->
            context.currentData[sourceKey]?.let { value ->
                inputData[targetKey] = value
            }
        }

        return inputData
    }

    private fun applyOutputMapping(
        step: PipelineStep,
        stepOutput: Map<String, Any>,
        context: PipelineExecutionContext
    ) {
        step.outputMapping.forEach { (sourceKey, targetKey) ->
            stepOutput[sourceKey]?.let { value ->
                context.currentData[targetKey] = value
            }
        }
    }

    private fun simulateStepExecution(
        step: PipelineStep,
        inputData: Map<String, Any>,
        outputData: MutableMap<String, Any>
    ) {
        // Simulate component execution
        // In a real implementation, this would call the actual component
        when (step.componentType) {
            "LLMComponent" -> {
                outputData["text"] = "Generated text from LLM"
                outputData["tokens"] = 150
            }
            "STTComponent" -> {
                outputData["transcript"] = "Transcribed text from audio"
                outputData["confidence"] = 0.95
            }
            "TTSComponent" -> {
                outputData["audio"] = "Generated audio data"
                outputData["duration"] = 5.2
            }
            else -> {
                outputData["result"] = "Generic step result"
            }
        }
    }
}

/**
 * Pipeline builder for creating complex pipelines
 */
class PipelineBuilder(
    private val id: String,
    private val name: String
) {
    private val steps = mutableListOf<PipelineStep>()
    private var description: String? = null
    private var globalTimeoutMs: Long = 300_000L
    private var stopOnError: Boolean = true
    private var maxConcurrentSteps: Int = 3
    private val metadata = mutableMapOf<String, String>()

    fun description(description: String): PipelineBuilder {
        this.description = description
        return this
    }

    fun globalTimeout(timeoutMs: Long): PipelineBuilder {
        this.globalTimeoutMs = timeoutMs
        return this
    }

    fun stopOnError(stop: Boolean): PipelineBuilder {
        this.stopOnError = stop
        return this
    }

    fun maxConcurrentSteps(max: Int): PipelineBuilder {
        this.maxConcurrentSteps = max
        return this
    }

    fun addMetadata(key: String, value: String): PipelineBuilder {
        this.metadata[key] = value
        return this
    }

    fun addStep(
        id: String,
        name: String,
        componentType: String,
        configure: PipelineStepBuilder.() -> Unit = {}
    ): PipelineBuilder {
        val stepBuilder = PipelineStepBuilder(id, name, componentType)
        stepBuilder.configure()
        steps.add(stepBuilder.build())
        return this
    }

    fun build(): PipelineConfig {
        return PipelineConfig(
            id = id,
            name = name,
            description = description,
            steps = steps,
            globalTimeoutMs = globalTimeoutMs,
            stopOnError = stopOnError,
            maxConcurrentSteps = maxConcurrentSteps,
            metadata = metadata
        )
    }
}

/**
 * Pipeline step builder
 */
class PipelineStepBuilder(
    private val id: String,
    private val name: String,
    private val componentType: String
) {
    private val inputMapping = mutableMapOf<String, String>()
    private val outputMapping = mutableMapOf<String, String>()
    private val dependencies = mutableListOf<String>()
    private var optional: Boolean = false
    private var maxRetries: Int = 0
    private var timeoutMs: Long = 60_000L
    private var parallelGroup: String? = null

    fun mapInput(targetKey: String, sourceKey: String): PipelineStepBuilder {
        inputMapping[targetKey] = sourceKey
        return this
    }

    fun mapOutput(sourceKey: String, targetKey: String): PipelineStepBuilder {
        outputMapping[sourceKey] = targetKey
        return this
    }

    fun dependsOn(stepId: String): PipelineStepBuilder {
        dependencies.add(stepId)
        return this
    }

    fun optional(isOptional: Boolean = true): PipelineStepBuilder {
        this.optional = isOptional
        return this
    }

    fun maxRetries(retries: Int): PipelineStepBuilder {
        this.maxRetries = retries
        return this
    }

    fun timeout(timeoutMs: Long): PipelineStepBuilder {
        this.timeoutMs = timeoutMs
        return this
    }

    fun parallelGroup(group: String): PipelineStepBuilder {
        this.parallelGroup = group
        return this
    }

    internal fun build(): PipelineStep {
        return PipelineStep(
            id = id,
            name = name,
            componentType = componentType,
            inputMapping = inputMapping,
            outputMapping = outputMapping,
            dependencies = dependencies,
            optional = optional,
            maxRetries = maxRetries,
            timeoutMs = timeoutMs,
            parallelGroup = parallelGroup
        )
    }
}
