package com.runanywhere.runanywhereai.viewmodels

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.models.GenerationSettings
import com.runanywhere.runanywhereai.models.SettingsDialogState
import com.runanywhere.runanywhereai.models.SettingsEvent
import com.runanywhere.runanywhereai.models.SettingsUiState
import com.runanywhere.runanywhereai.models.StoredModelInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling
import com.runanywhere.sdk.public.extensions.LLM.ToolCallFormat
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolParameter
import com.runanywhere.sdk.public.extensions.LLM.ToolParameterType
import com.runanywhere.sdk.public.extensions.LLM.ToolValue
import com.runanywhere.sdk.public.extensions.clearCache
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.storageInfo
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class SettingsViewModel(application: Application) : AndroidViewModel(application) {

    // Start in Ready immediately with defaults — no loading spinner needed
    private val _uiState = MutableStateFlow<SettingsUiState>(SettingsUiState.Ready())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    private val _dialogState = MutableStateFlow<SettingsDialogState>(SettingsDialogState.None)
    val dialogState: StateFlow<SettingsDialogState> = _dialogState.asStateFlow()

    // Mutable fields for the API config dialog — not part of the sealed state
    private val _apiKey = MutableStateFlow("")
    val apiKey: StateFlow<String> = _apiKey.asStateFlow()

    private val _baseURL = MutableStateFlow("")
    val baseURL: StateFlow<String> = _baseURL.asStateFlow()

    private val _events = Channel<SettingsEvent>(Channel.BUFFERED)
    val events: Flow<SettingsEvent> = _events.receiveAsFlow()

    // SharedPreferences
    private val settingsPrefs by lazy {
        application.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
    }
    private val generationPrefs by lazy {
        application.getSharedPreferences(GENERATION_PREFS, Context.MODE_PRIVATE)
    }
    private val toolPrefs by lazy {
        application.getSharedPreferences(TOOL_PREFS, Context.MODE_PRIVATE)
    }

    init {
        // Load settings eagerly — SDK is almost always ready by the time user reaches Settings
        loadAllSettings()
        subscribeToModelEvents()
    }

    private fun subscribeToModelEvents() {
        viewModelScope.launch {
            EventBus.events
                .filterIsInstance<ModelEvent>()
                .collect { event ->
                    when (event.eventType) {
                        ModelEvent.ModelEventType.DOWNLOAD_COMPLETED,
                        ModelEvent.ModelEventType.DELETED -> refreshStorage()
                        else -> { /* no-op */ }
                    }
                }
        }
    }

    // =========================================================================
    // Initial load
    // =========================================================================

    private fun loadAllSettings() {
        viewModelScope.launch {
            val temperature = generationPrefs.getFloat(KEY_TEMPERATURE, 0.7f)
            val maxTokens = generationPrefs.getInt(KEY_MAX_TOKENS, 1000)
            val systemPrompt = generationPrefs.getString(KEY_SYSTEM_PROMPT, "") ?: ""
            val toolEnabled = toolPrefs.getBoolean(KEY_TOOL_CALLING_ENABLED, false)
            val analyticsLocal = settingsPrefs.getBoolean(KEY_ANALYTICS_LOG_LOCAL, false)

            // Check API config status
            val apiKeyConfigured = settingsPrefs.getString(KEY_API_KEY, null)?.isNotEmpty() == true
            val baseURLConfigured = settingsPrefs.getString(KEY_BASE_URL, null)?.isNotEmpty() == true

            // Load stored api key / url into dialog fields
            _apiKey.value = settingsPrefs.getString(KEY_API_KEY, "") ?: ""
            _baseURL.value = settingsPrefs.getString(KEY_BASE_URL, "") ?: ""

            // Load tool names
            val toolNames = try {
                RunAnywhereToolCalling.getRegisteredTools().map { it.name }
            } catch (e: Exception) {
                emptyList()
            }

            _uiState.value = SettingsUiState.Ready(
                temperature = temperature,
                maxTokens = maxTokens,
                systemPrompt = systemPrompt,
                toolCallingEnabled = toolEnabled,
                registeredToolNames = toolNames.toImmutableList(),
                analyticsLogToLocal = analyticsLocal,
                isApiKeyConfigured = apiKeyConfigured,
                isBaseURLConfigured = baseURLConfigured,
            )

            // Load storage in background
            refreshStorage()
        }
    }

    // =========================================================================
    // Generation settings
    // =========================================================================

    fun updateTemperature(value: Float) = updateReady { copy(temperature = value) }
    fun updateMaxTokens(value: Int) = updateReady { copy(maxTokens = value) }
    fun updateSystemPrompt(value: String) = updateReady { copy(systemPrompt = value) }

    fun saveGenerationSettings() {
        val state = (_uiState.value as? SettingsUiState.Ready) ?: return
        viewModelScope.launch {
            generationPrefs.edit()
                .putFloat(KEY_TEMPERATURE, state.temperature)
                .putInt(KEY_MAX_TOKENS, state.maxTokens)
                .putString(KEY_SYSTEM_PROMPT, state.systemPrompt)
                .apply()
            _events.send(SettingsEvent.ShowSnackbar("Generation settings saved"))
        }
    }

    // =========================================================================
    // Tool calling
    // =========================================================================

    fun setToolCallingEnabled(enabled: Boolean) {
        toolPrefs.edit().putBoolean(KEY_TOOL_CALLING_ENABLED, enabled).apply()
        updateReady { copy(toolCallingEnabled = enabled) }
    }

    fun registerDemoTools() {
        viewModelScope.launch {
            updateReady { copy(isToolLoading = true) }
            try {
                // Weather
                RunAnywhereToolCalling.registerTool(
                    definition = ToolDefinition(
                        name = "get_weather",
                        description = "Gets the current weather for a given location using Open-Meteo API",
                        parameters = listOf(
                            ToolParameter(
                                name = "location",
                                type = ToolParameterType.STRING,
                                description = "City name (e.g., 'San Francisco', 'London', 'Tokyo')",
                                required = true,
                            ),
                        ),
                        category = "Utility",
                    ),
                    executor = { args ->
                        fetchWeather((args["location"] as? ToolValue.StringValue)?.value ?: "San Francisco")
                    },
                )

                // Time
                RunAnywhereToolCalling.registerTool(
                    definition = ToolDefinition(
                        name = "get_current_time",
                        description = "Gets the current date, time, and timezone information",
                        parameters = emptyList(),
                        category = "Utility",
                    ),
                    executor = { _ ->
                        val now = Date()
                        val dateFmt = SimpleDateFormat("EEEE, MMMM d, yyyy 'at' h:mm:ss a", Locale.getDefault())
                        val timeFmt = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
                        val isoFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.getDefault()).apply {
                            timeZone = TimeZone.getTimeZone("UTC")
                        }
                        val tz = TimeZone.getDefault()
                        mapOf(
                            "datetime" to ToolValue.StringValue(dateFmt.format(now)),
                            "time" to ToolValue.StringValue(timeFmt.format(now)),
                            "timestamp" to ToolValue.StringValue(isoFmt.format(now)),
                            "timezone" to ToolValue.StringValue(tz.id),
                            "utc_offset" to ToolValue.StringValue(tz.getDisplayName(false, TimeZone.SHORT)),
                        )
                    },
                )

                // Calculator
                RunAnywhereToolCalling.registerTool(
                    definition = ToolDefinition(
                        name = "calculate",
                        description = "Performs math calculations. Supports +, -, *, /, and parentheses",
                        parameters = listOf(
                            ToolParameter(
                                name = "expression",
                                type = ToolParameterType.STRING,
                                description = "Math expression (e.g., '2 + 2 * 3', '(10 + 5) / 3')",
                                required = true,
                            ),
                        ),
                        category = "Utility",
                    ),
                    executor = { args ->
                        val expr = (args["expression"] as? ToolValue.StringValue)?.value
                            ?: (args["input"] as? ToolValue.StringValue)?.value
                            ?: "0"
                        evaluateMathExpression(expr)
                    },
                )

                refreshToolNames()
                _events.send(SettingsEvent.ShowSnackbar("Demo tools registered"))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to register demo tools", e)
            } finally {
                updateReady { copy(isToolLoading = false) }
            }
        }
    }

    fun clearAllTools() {
        viewModelScope.launch {
            updateReady { copy(isToolLoading = true) }
            try {
                RunAnywhereToolCalling.clearTools()
                refreshToolNames()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear tools", e)
            } finally {
                updateReady { copy(isToolLoading = false) }
            }
        }
    }

    /**
     * Detect the appropriate tool call format based on model name.
     */
    fun detectToolCallFormat(modelName: String?): ToolCallFormat {
        val name = modelName?.lowercase() ?: return ToolCallFormat.Default
        return if (name.contains("lfm2") && name.contains("tool")) {
            ToolCallFormat.LFM2
        } else {
            ToolCallFormat.Default
        }
    }

    private suspend fun refreshToolNames() {
        try {
            val names = RunAnywhereToolCalling.getRegisteredTools().map { it.name }
            updateReady { copy(registeredToolNames = names.toImmutableList()) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to refresh tool names", e)
        }
    }

    // =========================================================================
    // Storage
    // =========================================================================

    fun refreshStorage() {
        viewModelScope.launch {
            try {
                val info = withContext(Dispatchers.IO) { RunAnywhere.storageInfo() }
                val models = info.storedModels.map { m ->
                    StoredModelInfo(id = m.id, name = m.name, size = m.size)
                }
                updateReady {
                    copy(
                        totalStorageSize = info.deviceStorage.totalSpace,
                        availableSpace = info.deviceStorage.freeSpace,
                        modelStorageSize = info.totalModelsSize,
                        downloadedModels = models.toImmutableList(),
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load storage info", e)
            }
        }
    }

    fun deleteModel(modelId: String) {
        viewModelScope.launch {
            try {
                RunAnywhere.deleteModel(modelId)
                refreshStorage()
                _events.send(SettingsEvent.ShowSnackbar("Model deleted"))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete model: $modelId", e)
            }
        }
        _dialogState.value = SettingsDialogState.None
    }

    fun clearCache() {
        viewModelScope.launch {
            try {
                RunAnywhere.clearCache()
                refreshStorage()
                _events.send(SettingsEvent.ShowSnackbar("Cache cleared"))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear cache", e)
            }
        }
    }

    fun cleanTempFiles() {
        viewModelScope.launch {
            try {
                RunAnywhere.clearCache()
                refreshStorage()
                _events.send(SettingsEvent.ShowSnackbar("Temporary files cleaned"))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clean temp files", e)
            }
        }
    }

    // =========================================================================
    // Logging
    // =========================================================================

    fun updateAnalyticsLogToLocal(value: Boolean) {
        settingsPrefs.edit().putBoolean(KEY_ANALYTICS_LOG_LOCAL, value).apply()
        updateReady { copy(analyticsLogToLocal = value) }
    }

    // =========================================================================
    // API configuration
    // =========================================================================

    fun updateApiKey(value: String) { _apiKey.value = value }
    fun updateBaseURL(value: String) { _baseURL.value = value }

    fun showApiConfigDialog() { _dialogState.value = SettingsDialogState.ApiConfiguration }
    fun showDeleteModelDialog(model: StoredModelInfo) { _dialogState.value = SettingsDialogState.DeleteModel(model) }
    fun dismissDialog() { _dialogState.value = SettingsDialogState.None }

    fun saveApiConfiguration() {
        val key = _apiKey.value
        val rawUrl = _baseURL.value.trim()
        val normalizedUrl = if (rawUrl.isNotEmpty() && !rawUrl.startsWith("http://") && !rawUrl.startsWith("https://")) {
            "https://$rawUrl"
        } else {
            rawUrl
        }

        settingsPrefs.edit()
            .putString(KEY_API_KEY, key)
            .putString(KEY_BASE_URL, normalizedUrl)
            .apply()

        _baseURL.value = normalizedUrl
        updateReady {
            copy(
                isApiKeyConfigured = key.isNotEmpty(),
                isBaseURLConfigured = normalizedUrl.isNotEmpty(),
            )
        }
        _dialogState.value = SettingsDialogState.RestartRequired
    }

    fun clearApiConfiguration() {
        settingsPrefs.edit()
            .remove(KEY_API_KEY)
            .remove(KEY_BASE_URL)
            .apply()

        // Clear device registration so it re-registers
        getApplication<Application>()
            .getSharedPreferences("runanywhere_sdk", Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_DEVICE_REGISTERED)
            .apply()

        _apiKey.value = ""
        _baseURL.value = ""
        updateReady {
            copy(isApiKeyConfigured = false, isBaseURLConfigured = false)
        }
        _dialogState.value = SettingsDialogState.RestartRequired
    }

    // =========================================================================
    // Static helpers
    // =========================================================================

    companion object {
        private const val TAG = "SettingsViewModel"

        private const val SETTINGS_PREFS = "runanywhere_settings"
        private const val GENERATION_PREFS = "generation_settings"
        private const val TOOL_PREFS = "tool_settings"

        private const val KEY_API_KEY = "runanywhere_api_key"
        private const val KEY_BASE_URL = "runanywhere_base_url"
        private const val KEY_DEVICE_REGISTERED = "com.runanywhere.sdk.deviceRegistered"
        private const val KEY_ANALYTICS_LOG_LOCAL = "analyticsLogToLocal"

        private const val KEY_TEMPERATURE = "defaultTemperature"
        private const val KEY_MAX_TOKENS = "defaultMaxTokens"
        private const val KEY_SYSTEM_PROMPT = "defaultSystemPrompt"
        private const val KEY_TOOL_CALLING_ENABLED = "tool_calling_enabled"

        private const val WEATHER_API_TIMEOUT_MS = 15_000L

        /** Retrieve generation settings from prefs (for use by ChatViewModel). */
        fun getGenerationSettings(context: Context): GenerationSettings {
            val prefs = context.getSharedPreferences(GENERATION_PREFS, Context.MODE_PRIVATE)
            return GenerationSettings(
                temperature = prefs.getFloat(KEY_TEMPERATURE, 0.7f),
                maxTokens = prefs.getInt(KEY_MAX_TOKENS, 1000),
                systemPrompt = prefs.getString(KEY_SYSTEM_PROMPT, "").takeIf { !it.isNullOrEmpty() },
            )
        }

        fun getStoredApiKey(context: Context): String? {
            return context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_API_KEY, null)?.takeIf { it.isNotEmpty() }
        }

        fun getStoredBaseURL(context: Context): String? {
            val value = context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_BASE_URL, null) ?: return null
            if (value.isEmpty()) return null
            val trimmed = value.trim()
            return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) trimmed else "https://$trimmed"
        }

        fun hasCustomConfiguration(context: Context): Boolean =
            getStoredApiKey(context) != null && getStoredBaseURL(context) != null

        fun isToolCallingEnabled(context: Context): Boolean =
            context.getSharedPreferences(TOOL_PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_TOOL_CALLING_ENABLED, false)
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private inline fun updateReady(crossinline transform: SettingsUiState.Ready.() -> SettingsUiState.Ready) {
        _uiState.update { current ->
            when (current) {
                is SettingsUiState.Ready -> current.transform()
                else -> current
            }
        }
    }

    // -- Weather fetch -----------------------------------------------------------

    private suspend fun fetchWeather(location: String): Map<String, ToolValue> =
        withContext(Dispatchers.IO) {
            try {
                withTimeout(WEATHER_API_TIMEOUT_MS) {
                    val geoUrl = "https://geocoding-api.open-meteo.com/v1/search?name=${URLEncoder.encode(location, "UTF-8")}&count=1"
                    val geoResp = fetchUrl(geoUrl)

                    val latMatch = Regex("\"latitude\":\\s*(-?\\d+\\.?\\d*)").find(geoResp)
                    val lonMatch = Regex("\"longitude\":\\s*(-?\\d+\\.?\\d*)").find(geoResp)
                    val nameMatch = Regex("\"name\":\\s*\"([^\"]+)\"").find(geoResp)

                    if (latMatch == null || lonMatch == null) {
                        return@withTimeout mapOf(
                            "error" to ToolValue.StringValue("Location not found: $location"),
                            "location" to ToolValue.StringValue(location),
                        )
                    }

                    val lat = latMatch.groupValues[1]
                    val lon = lonMatch.groupValues[1]
                    val resolvedName = nameMatch?.groupValues?.get(1) ?: location

                    val weatherUrl = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
                    val weatherResp = fetchUrl(weatherUrl)

                    val temp = Regex("\"temperature_2m\":\\s*(-?\\d+\\.?\\d*)").find(weatherResp)?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0
                    val humidity = Regex("\"relative_humidity_2m\":\\s*(\\d+)").find(weatherResp)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                    val wind = Regex("\"wind_speed_10m\":\\s*(-?\\d+\\.?\\d*)").find(weatherResp)?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0
                    val code = Regex("\"weather_code\":\\s*(\\d+)").find(weatherResp)?.groupValues?.get(1)?.toIntOrNull() ?: 0

                    val condition = when (code) {
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
                        "temperature_celsius" to ToolValue.NumberValue(temp),
                        "temperature_fahrenheit" to ToolValue.NumberValue(temp * 9 / 5 + 32),
                        "humidity_percent" to ToolValue.NumberValue(humidity.toDouble()),
                        "wind_speed_kmh" to ToolValue.NumberValue(wind),
                        "condition" to ToolValue.StringValue(condition),
                    )
                }
            } catch (e: TimeoutCancellationException) {
                mapOf(
                    "error" to ToolValue.StringValue("Weather API request timed out. Please try again."),
                    "location" to ToolValue.StringValue(location),
                )
            } catch (e: Exception) {
                mapOf(
                    "error" to ToolValue.StringValue("Failed to fetch weather: ${e.message}"),
                    "location" to ToolValue.StringValue(location),
                )
            }
        }

    private fun fetchUrl(urlString: String): String {
        val connection = URL(urlString).openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        return try {
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    // -- Math expression evaluator -----------------------------------------------

    private fun evaluateMathExpression(expression: String): Map<String, ToolValue> {
        return try {
            val cleaned = expression.replace("=", "").replace("x", "*").replace("\u00d7", "*").replace("\u00f7", "/").trim()
            val result = evalExpr(tokenize(cleaned))
            mapOf(
                "result" to ToolValue.NumberValue(result),
                "expression" to ToolValue.StringValue(expression),
            )
        } catch (e: Exception) {
            mapOf(
                "error" to ToolValue.StringValue("Could not evaluate expression: $expression"),
                "expression" to ToolValue.StringValue(expression),
            )
        }
    }

    private class TokenStream(private val tokens: List<String>) {
        private var idx = 0
        fun hasNext(): Boolean = idx < tokens.size
        fun next(): String { if (!hasNext()) throw NoSuchElementException(); return tokens[idx++] }
        fun peek(): String? = if (hasNext()) tokens[idx] else null
    }

    private fun tokenize(expr: String): TokenStream {
        val tokens = mutableListOf<String>()
        val buf = StringBuilder()
        for (c in expr) {
            when {
                c.isDigit() || c == '.' -> buf.append(c)
                c in "+-*/()" -> { if (buf.isNotEmpty()) { tokens.add(buf.toString()); buf.clear() }; tokens.add(c.toString()) }
                c.isWhitespace() -> { if (buf.isNotEmpty()) { tokens.add(buf.toString()); buf.clear() } }
            }
        }
        if (buf.isNotEmpty()) tokens.add(buf.toString())
        return TokenStream(tokens)
    }

    private fun evalExpr(ts: TokenStream): Double {
        var left = evalTerm(ts)
        while (ts.hasNext()) {
            val op = ts.peek() ?: break
            if (op != "+" && op != "-") break
            ts.next()
            val right = evalTerm(ts)
            left = if (op == "+") left + right else left - right
        }
        return left
    }

    private fun evalTerm(ts: TokenStream): Double {
        var left = evalFactor(ts)
        while (ts.hasNext()) {
            val op = ts.peek() ?: break
            if (op != "*" && op != "/") break
            ts.next()
            val right = evalFactor(ts)
            left = if (op == "*") left * right else left / right
        }
        return left
    }

    private fun evalFactor(ts: TokenStream): Double {
        if (!ts.hasNext()) return 0.0
        val token = ts.next()
        return when {
            token == "(" -> { val r = evalExpr(ts); if (ts.hasNext()) ts.next(); r }
            token == "-" -> -evalFactor(ts)
            else -> token.toDoubleOrNull() ?: 0.0
        }
    }
}
