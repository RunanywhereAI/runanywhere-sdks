package com.runanywhere.runanywhereai.presentation.settings

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolParameter
import com.runanywhere.sdk.public.extensions.LLM.ToolParameterType
import com.runanywhere.sdk.public.extensions.LLM.ToolValue
import com.runanywhere.sdk.public.extensions.LLM.ToolCallFormatName
import com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Tool Settings UI State
 */
data class ToolSettingsUiState(
    val toolCallingEnabled: Boolean = false,
    val registeredTools: List<ToolDefinition> = emptyList(),
    val isLoading: Boolean = false,
)

/**
 * Tool Settings ViewModel
 *
 * Manages tool calling configuration and demo tool registration.
 * Mirrors iOS ToolSettingsViewModel.swift functionality.
 */
class ToolSettingsViewModel private constructor(application: Application) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(ToolSettingsUiState())
    val uiState: StateFlow<ToolSettingsUiState> = _uiState.asStateFlow()

    private val prefs = application.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    val toolCallingEnabled: Boolean
        get() = _uiState.value.toolCallingEnabled

    companion object {
        private const val TAG = "ToolSettingsVM"
        private const val PREFS_NAME = "tool_settings"
        private const val KEY_TOOL_CALLING_ENABLED = "tool_calling_enabled"

        @Volatile
        private var instance: ToolSettingsViewModel? = null

        fun getInstance(application: Application): ToolSettingsViewModel {
            return instance ?: synchronized(this) {
                instance ?: ToolSettingsViewModel(application).also { instance = it }
            }
        }
    }

    init {
        // Load saved preference
        val enabled = prefs.getBoolean(KEY_TOOL_CALLING_ENABLED, false)
        _uiState.update { it.copy(toolCallingEnabled = enabled) }

        // Refresh registered tools
        viewModelScope.launch {
            refreshRegisteredTools()
        }
    }

    fun setToolCallingEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_TOOL_CALLING_ENABLED, enabled).apply()
        _uiState.update { it.copy(toolCallingEnabled = enabled) }
    }

    suspend fun refreshRegisteredTools() {
        val tools = RunAnywhereToolCalling.getRegisteredTools()
        _uiState.update { it.copy(registeredTools = tools) }
    }

    /**
     * Register demo tools matching iOS implementation:
     * - get_weather: Uses Open-Meteo API (free, no API key)
     * - get_current_time: Returns system time with timezone
     * - calculate: Evaluates math expressions
     */
    fun registerDemoTools() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            try {
                // Weather Tool - Uses Open-Meteo API (free, no API key required)
                RunAnywhereToolCalling.registerTool(
                    definition = ToolDefinition(
                        name = "get_weather",
                        description = "Gets the current weather for a given location using Open-Meteo API",
                        parameters = listOf(
                            ToolParameter(
                                name = "location",
                                type = ToolParameterType.STRING,
                                description = "City name (e.g., 'San Francisco', 'London', 'Tokyo')",
                                required = true
                            )
                        ),
                        category = "Utility"
                    ),
                    executor = { args: Map<String, ToolValue> ->
                        fetchWeather((args["location"] as? ToolValue.StringValue)?.value ?: "San Francisco")
                    }
                )

                // Time Tool - Real system time with timezone
                RunAnywhereToolCalling.registerTool(
                    definition = ToolDefinition(
                        name = "get_current_time",
                        description = "Gets the current date, time, and timezone information",
                        parameters = emptyList(),
                        category = "Utility"
                    ),
                    executor = { _: Map<String, ToolValue> ->
                        val now = Date()
                        val dateFormatter = SimpleDateFormat("EEEE, MMMM d, yyyy 'at' h:mm:ss a", Locale.getDefault())
                        val timeFormatter = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
                        val isoFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.getDefault()).apply {
                            timeZone = TimeZone.getTimeZone("UTC")
                        }
                        val tz = TimeZone.getDefault()

                        mapOf(
                            "datetime" to ToolValue.StringValue(dateFormatter.format(now)),
                            "time" to ToolValue.StringValue(timeFormatter.format(now)),
                            "timestamp" to ToolValue.StringValue(isoFormatter.format(now)),
                            "timezone" to ToolValue.StringValue(tz.id),
                            "utc_offset" to ToolValue.StringValue(tz.getDisplayName(false, TimeZone.SHORT))
                        )
                    }
                )

                // Calculator Tool - Math evaluation
                RunAnywhereToolCalling.registerTool(
                    definition = ToolDefinition(
                        name = "calculate",
                        description = "Performs math calculations. Supports +, -, *, /, and parentheses",
                        parameters = listOf(
                            ToolParameter(
                                name = "expression",
                                type = ToolParameterType.STRING,
                                description = "Math expression (e.g., '2 + 2 * 3', '(10 + 5) / 3')",
                                required = true
                            )
                        ),
                        category = "Utility"
                    ),
                    executor = { args: Map<String, ToolValue> ->
                        val expression = (args["expression"] as? ToolValue.StringValue)?.value
                            ?: (args["input"] as? ToolValue.StringValue)?.value
                            ?: "0"
                        evaluateMathExpression(expression)
                    }
                )

                Log.i(TAG, "✅ Demo tools registered")
                refreshRegisteredTools()

            } catch (e: Exception) {
                Log.e(TAG, "Failed to register demo tools", e)
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    fun clearAllTools() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                RunAnywhereToolCalling.clearTools()
                refreshRegisteredTools()
                Log.i(TAG, "✅ All tools cleared")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear tools", e)
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    /**
     * Detect the appropriate tool call format based on model name.
     * LFM2-Tool models use the lfm2 format, others use default JSON format.
     */
    fun detectToolCallFormat(modelName: String?): String {
        val name = modelName?.lowercase() ?: return ToolCallFormatName.DEFAULT
        return if (name.contains("lfm2") && name.contains("tool")) {
            ToolCallFormatName.LFM2
        } else {
            ToolCallFormatName.DEFAULT
        }
    }

    // ========================================================================
    // Tool Executor Implementations
    // ========================================================================

    /**
     * Fetch weather using Open-Meteo API (free, no API key required)
     */
    private suspend fun fetchWeather(location: String): Map<String, ToolValue> {
        return withContext(Dispatchers.IO) {
            try {
                // First, geocode the location
                val geocodeUrl = "https://geocoding-api.open-meteo.com/v1/search?name=${URLEncoder.encode(location, "UTF-8")}&count=1"
                val geocodeResponse = fetchUrl(geocodeUrl)

            // Parse geocode response (simple JSON parsing)
            val latMatch = Regex("\"latitude\":\\s*(-?\\d+\\.?\\d*)").find(geocodeResponse)
            val lonMatch = Regex("\"longitude\":\\s*(-?\\d+\\.?\\d*)").find(geocodeResponse)
            val nameMatch = Regex("\"name\":\\s*\"([^\"]+)\"").find(geocodeResponse)

            if (latMatch == null || lonMatch == null) {
                return@withContext mapOf(
                    "error" to ToolValue.StringValue("Location not found: $location"),
                    "location" to ToolValue.StringValue(location)
                )
            }

            val lat = latMatch.groupValues[1]
            val lon = lonMatch.groupValues[1]
            val resolvedName = nameMatch?.groupValues?.get(1) ?: location

            // Fetch weather
            val weatherUrl = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
            val weatherResponse = fetchUrl(weatherUrl)

            // Parse weather response
            val tempMatch = Regex("\"temperature_2m\":\\s*(-?\\d+\\.?\\d*)").find(weatherResponse)
            val humidityMatch = Regex("\"relative_humidity_2m\":\\s*(\\d+)").find(weatherResponse)
            val windMatch = Regex("\"wind_speed_10m\":\\s*(-?\\d+\\.?\\d*)").find(weatherResponse)
            val codeMatch = Regex("\"weather_code\":\\s*(\\d+)").find(weatherResponse)

            val temperature = tempMatch?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0
            val humidity = humidityMatch?.groupValues?.get(1)?.toIntOrNull() ?: 0
            val windSpeed = windMatch?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0
            val weatherCode = codeMatch?.groupValues?.get(1)?.toIntOrNull() ?: 0

            val condition = when (weatherCode) {
                0 -> "Clear sky"
                1, 2, 3 -> "Partly cloudy"
                45, 48 -> "Foggy"
                51, 53, 55 -> "Drizzle"
                61, 63, 65 -> "Rain"
                71, 73, 75 -> "Snow"
                80, 81, 82 -> "Rain showers"
                95, 96, 99 -> "Thunderstorm"
                else -> "Unknown"
            }

            mapOf(
                "location" to ToolValue.StringValue(resolvedName),
                "temperature_celsius" to ToolValue.NumberValue(temperature),
                "temperature_fahrenheit" to ToolValue.NumberValue(temperature * 9/5 + 32),
                "humidity_percent" to ToolValue.NumberValue(humidity.toDouble()),
                "wind_speed_kmh" to ToolValue.NumberValue(windSpeed),
                "condition" to ToolValue.StringValue(condition)
            )
            } catch (e: Exception) {
                Log.e(TAG, "Weather fetch failed", e)
                mapOf(
                    "error" to ToolValue.StringValue("Failed to fetch weather: ${e.message}"),
                    "location" to ToolValue.StringValue(location)
                )
            }
        }
    }

    private fun fetchUrl(urlString: String): String {
        val url = URL(urlString)
        val connection = url.openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 10000
        connection.readTimeout = 10000

        return try {
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Evaluate a math expression
     */
    private fun evaluateMathExpression(expression: String): Map<String, ToolValue> {
        return try {
            // Clean the expression
            val cleaned = expression
                .replace("=", "")
                .replace("x", "*")
                .replace("×", "*")
                .replace("÷", "/")
                .trim()

            // Simple expression evaluator (handles basic math)
            val result = evaluateSimpleExpression(cleaned)

            mapOf(
                "result" to ToolValue.NumberValue(result),
                "expression" to ToolValue.StringValue(expression)
            )
        } catch (e: Exception) {
            mapOf(
                "error" to ToolValue.StringValue("Could not evaluate expression: $expression"),
                "expression" to ToolValue.StringValue(expression)
            )
        }
    }

    /**
     * Token parser with index-based iteration supporting peek operations.
     * Enables lookahead for recursive descent parsing without consuming tokens.
     */
    private class TokenParser(private val tokens: List<String>) {
        private var index = 0

        /** Returns true if there are more tokens to consume */
        fun hasNext(): Boolean = index < tokens.size

        /** Returns and consumes the next token */
        fun next(): String {
            if (!hasNext()) throw NoSuchElementException("No more tokens")
            return tokens[index++]
        }

        /** Returns the next token without consuming it, or null if no more tokens */
        fun peek(): String? = if (hasNext()) tokens[index] else null
    }

    /**
     * Simple recursive descent parser for math expressions
     */
    private fun evaluateSimpleExpression(expr: String): Double {
        val tokens = tokenize(expr)
        val parser = TokenParser(tokens)
        return parseExpression(parser)
    }

    private fun tokenize(expr: String): List<String> {
        val tokens = mutableListOf<String>()
        var current = StringBuilder()

        for (char in expr) {
            when {
                char.isDigit() || char == '.' -> current.append(char)
                char in "+-*/()" -> {
                    if (current.isNotEmpty()) {
                        tokens.add(current.toString())
                        current = StringBuilder()
                    }
                    tokens.add(char.toString())
                }
                char.isWhitespace() -> {
                    if (current.isNotEmpty()) {
                        tokens.add(current.toString())
                        current = StringBuilder()
                    }
                }
            }
        }
        if (current.isNotEmpty()) {
            tokens.add(current.toString())
        }
        return tokens
    }

    private fun parseExpression(parser: TokenParser): Double {
        var left = parseTerm(parser)
        while (parser.hasNext()) {
            val op = parser.peek() ?: break
            if (op != "+" && op != "-") break
            parser.next() // consume the operator
            val right = parseTerm(parser)
            left = if (op == "+") left + right else left - right
        }
        return left
    }

    private fun parseTerm(parser: TokenParser): Double {
        var left = parseFactor(parser)
        while (parser.hasNext()) {
            val op = parser.peek() ?: break
            if (op != "*" && op != "/") break
            parser.next() // consume the operator
            val right = parseFactor(parser)
            left = if (op == "*") left * right else left / right
        }
        return left
    }

    private fun parseFactor(parser: TokenParser): Double {
        if (!parser.hasNext()) return 0.0
        val token = parser.next()
        return when {
            token == "(" -> {
                val result = parseExpression(parser)
                if (parser.hasNext()) parser.next() // consume ')'
                result
            }
            token == "-" -> -parseFactor(parser)
            else -> token.toDoubleOrNull() ?: 0.0
        }
    }
}
