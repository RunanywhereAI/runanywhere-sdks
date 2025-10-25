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

data class ToolCallingState(
    val isLoading: Boolean = false,
    val userInput: String = "",
    val lastResponse: String? = null,
    val lastToolCalls: List<ToolCall> = emptyList(),
    val executionResults: List<String> = emptyList(),
    val error: String? = null
)

/**
 * ViewModel demonstrating grammar-based tool calling
 *
 * Shows how to:
 * - Define tools with parameters
 * - Use grammar-based constrained generation
 * - Execute tools and display results
 */
class ToolCallingViewModel : ViewModel() {

    private val _state = MutableStateFlow(ToolCallingState())
    val state: StateFlow<ToolCallingState> = _state.asStateFlow()

    // Define available tools
    private val availableTools = listOf(
        // Weather tool
        tool("get_weather", "Get current weather for a location") {
            stringParameter(
                name = "location",
                description = "City name and optional country (e.g., 'Tokyo, Japan')",
                required = true
            )
            stringParameter(
                name = "units",
                description = "Temperature units: 'celsius' or 'fahrenheit'",
                required = false,
                enum = listOf("celsius", "fahrenheit")
            )
        },

        // Time tool
        tool("get_current_time", "Get the current date and time") {
            stringParameter(
                name = "timezone",
                description = "Timezone (e.g., 'America/New_York', 'Asia/Tokyo')",
                required = false
            )
        },

        // Calculator tool
        tool("calculate", "Perform mathematical calculations") {
            stringParameter(
                name = "expression",
                description = "Mathematical expression to evaluate (e.g., '2 + 2', '15 * 7')",
                required = true
            )
        },

        // Random number tool
        tool("random_number", "Generate a random number") {
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

    fun updateInput(text: String) {
        _state.value = _state.value.copy(userInput = text)
    }

    fun generateWithTools() {
        val input = _state.value.userInput
        if (input.isBlank()) return

        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = true,
                error = null,
                lastToolCalls = emptyList(),
                executionResults = emptyList()
            )

            try {
                // Generate with grammar-based tool calling
                val result = RunAnywhere.generateWithTools(
                    prompt = input,
                    tools = availableTools,
                    options = RunAnywhereGenerationOptions(
                        maxTokens = 300,
                        temperature = 0.7f,
                        toolCallingMode = ToolCallingMode.GRAMMAR_BASED
                    )
                )

                if (result.success && result.toolCalls.isNotEmpty()) {
                    // Execute detected tool calls
                    val executionResults = result.toolCalls.map { toolCall ->
                        executeToolMock(toolCall)
                    }

                    _state.value = _state.value.copy(
                        isLoading = false,
                        lastResponse = result.text,
                        lastToolCalls = result.toolCalls,
                        executionResults = executionResults
                    )
                } else if (result.success) {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        lastResponse = result.text ?: "No response",
                        lastToolCalls = emptyList(),
                        executionResults = emptyList()
                    )
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Generation failed: ${result.text}"
                    )
                }

            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Error: ${e.message}"
                )
            }
        }
    }

    /**
     * Mock tool execution for demonstration
     * In a real app, these would call actual APIs/services
     */
    private fun executeToolMock(toolCall: ToolCall): String {
        return when (toolCall.name) {
            "get_weather" -> {
                val location = toolCall.arguments["location"] ?: "Unknown"
                val units = toolCall.arguments["units"] ?: "celsius"
                val temp = (15..30).random()
                val symbol = if (units == "celsius") "°C" else "°F"
                "Weather in $location: $temp$symbol, Partly cloudy with light winds"
            }

            "get_current_time" -> {
                val timezone = toolCall.arguments["timezone"] ?: "System"
                val now = LocalDateTime.now()
                val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
                "Current time ($timezone): ${now.format(formatter)}"
            }

            "calculate" -> {
                val expression = toolCall.arguments["expression"] ?: "0"
                try {
                    val result = evaluateSimpleExpression(expression)
                    "Result: $expression = $result"
                } catch (e: Exception) {
                    "Error evaluating '$expression': ${e.message}"
                }
            }

            "random_number" -> {
                val min = toolCall.arguments["min"]?.toIntOrNull() ?: 0
                val max = toolCall.arguments["max"]?.toIntOrNull() ?: 100
                val random = Random.nextInt(min, max + 1)
                "Random number between $min and $max: $random"
            }

            else -> "Unknown tool: ${toolCall.name}"
        }
    }

    /**
     * Simple expression evaluator for demo
     * Only handles basic arithmetic
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
        _state.value = ToolCallingState()
    }
}
