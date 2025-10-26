package com.runanywhere.runanywhereai.presentation.tools

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.generateWithTools
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlin.random.Random

/**
 * UI State for Tool Calling screen
 */
data class ToolCallingUiState(
    val isLoading: Boolean = false,
    val isModelLoaded: Boolean = true, // Will be updated from SDK
    val input: String = "",
    val results: List<ToolExecutionResult> = emptyList(),
    val errorMessage: String? = null
)

/**
 * Result of a tool execution
 */
data class ToolExecutionResult(
    val query: String,
    val success: Boolean,
    val toolCalls: List<ToolCall>,
    val executionResults: Map<String, String>, // tool name -> result
    val responseText: String?
)

/**
 * ViewModel demonstrating grammar-based tool calling
 *
 * Shows how to:
 * - Define tools with parameters using DSL
 * - Use grammar-based constrained generation (100% valid JSON)
 * - Execute tools and display results
 */
class ToolCallingViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(ToolCallingUiState())
    val uiState: StateFlow<ToolCallingUiState> = _uiState.asStateFlow()

    // Define available tools with DSL
    private val availableTools = listOf(
        // Time tool
        tool("get_current_time", "Get the current date and time") {
            stringParameter(
                name = "timezone",
                description = "Timezone (e.g., 'America/New_York', 'Asia/Tokyo'). Leave empty for system timezone.",
                required = false
            )
        },

        // Calculator tool
        tool("calculate", "Perform simple mathematical calculations") {
            stringParameter(
                name = "expression",
                description = "Mathematical expression to evaluate (e.g., '2 + 2', '15 * 7', '100 / 5')",
                required = true
            )
        },

        // Random number tool
        tool("generate_random_number", "Generate a random number within a specified range") {
            intParameter(
                name = "min",
                description = "Minimum value (inclusive)",
                required = true
            )
            intParameter(
                name = "max",
                description = "Maximum value (inclusive)",
                required = true
            )
        }
    )

    init {
        // Check if model is loaded
        checkModelStatus()
    }

    private fun checkModelStatus() {
        viewModelScope.launch {
            try {
                val isLoaded = RunAnywhere.isInitialized
                _uiState.value = _uiState.value.copy(isModelLoaded = isLoaded)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isModelLoaded = false)
            }
        }
    }

    fun updateInput(text: String) {
        _uiState.value = _uiState.value.copy(input = text)
    }

    fun generateWithTools() {
        val input = _uiState.value.input
        if (input.isBlank()) return

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                errorMessage = null
            )

            try {
                // Generate with grammar-based tool calling
                // Grammar ensures 100% valid JSON output
                val result = RunAnywhere.generateWithTools(
                    prompt = input,
                    tools = availableTools,
                    options = RunAnywhereGenerationOptions(
                        maxTokens = 300,
                        temperature = 0.7f,
                        toolCallingMode = ToolCallingMode.GRAMMAR_BASED
                    )
                )

                if (result.success) {
                    // Execute detected tool calls
                    val executionResults = mutableMapOf<String, String>()

                    result.toolCalls.forEach { toolCall ->
                        val toolResult = executeToolMock(toolCall)
                        executionResults[toolCall.name] = toolResult
                    }

                    // Add to results list
                    val newResult = ToolExecutionResult(
                        query = input,
                        success = true,
                        toolCalls = result.toolCalls,
                        executionResults = executionResults,
                        responseText = result.text
                    )

                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        results = _uiState.value.results + newResult,
                        input = "" // Clear input after successful execution
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        errorMessage = "Generation failed: ${result.text ?: "Unknown error"}"
                    )
                }

            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = "Error: ${e.message ?: "Unknown error"}"
                )
                e.printStackTrace()
            }
        }
    }

    /**
     * Mock tool execution for demonstration
     * In a real app, these would call actual APIs/services
     */
    private fun executeToolMock(toolCall: ToolCall): String {
        return when (toolCall.name) {
            "get_current_time" -> {
                val timezone = toolCall.arguments["timezone"]
                val now = LocalDateTime.now()
                val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
                if (timezone.isNullOrBlank()) {
                    "Current time (System timezone): ${now.format(formatter)}"
                } else {
                    "Current time ($timezone): ${now.format(formatter)}"
                }
            }

            "calculate" -> {
                val expression = toolCall.arguments["expression"] ?: "0"
                try {
                    val result = evaluateSimpleExpression(expression)
                    "$expression = $result"
                } catch (e: Exception) {
                    "Error: Invalid expression '$expression'"
                }
            }

            "generate_random_number" -> {
                val min = toolCall.arguments["min"]?.toIntOrNull() ?: 0
                val max = toolCall.arguments["max"]?.toIntOrNull() ?: 100
                val random = Random.nextInt(min, max + 1)
                "Generated: $random (range: $min-$max)"
            }

            else -> "Unknown tool: ${toolCall.name}"
        }
    }

    /**
     * Simple expression evaluator for demo
     * Only handles basic arithmetic: +, -, *, /
     */
    private fun evaluateSimpleExpression(expr: String): Double {
        val clean = expr.replace(" ", "")

        return when {
            "+" in clean -> {
                val parts = clean.split("+")
                parts.sumOf { it.toDouble() }
            }
            "-" in clean && clean.indexOf("-") > 0 -> {
                val parts = clean.split("-")
                parts.first().toDouble() - parts.drop(1).sumOf { it.toDouble() }
            }
            "*" in clean -> {
                val parts = clean.split("*")
                parts.fold(1.0) { acc, s -> acc * s.toDouble() }
            }
            "/" in clean -> {
                val parts = clean.split("/")
                parts.drop(1).fold(parts.first().toDouble()) { acc, s -> acc / s.toDouble() }
            }
            else -> clean.toDouble()
        }
    }

    fun clearResults() {
        _uiState.value = _uiState.value.copy(
            results = emptyList(),
            errorMessage = null
        )
    }
}
