package com.runanywhere.agent.tools

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.provider.Settings
import com.runanywhere.agent.toolcalling.SimpleExpressionEvaluator
import com.runanywhere.agent.toolcalling.UnitConverter
import com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolParameter
import com.runanywhere.sdk.public.extensions.LLM.ToolParameterType
import com.runanywhere.sdk.public.extensions.LLM.ToolValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Registers utility tools with the RunAnywhere SDK's tool calling system.
 *
 * These tools provide factual information (time, weather, math, etc.)
 * so the agent doesn't need to navigate the UI for simple queries.
 * The SDK handles prompt formatting, <tool_call> parsing, auto-execution,
 * and result re-injection — all via the C++ layer.
 */
object UtilityTools {

    suspend fun registerAll(context: Context) {
        registerGetCurrentTime()
        registerGetCurrentDate()
        registerGetBatteryLevel(context)
        registerGetDeviceInfo(context)
        registerMathCalculate()
        registerGetWeather()
        registerUnitConvert()
        registerGetClipboard(context)
    }

    private suspend fun registerGetCurrentTime() {
        RunAnywhereToolCalling.registerTool(
            definition = ToolDefinition(
                name = "get_current_time",
                description = "Get the current time in a specified timezone",
                parameters = listOf(
                    ToolParameter(
                        name = "timezone",
                        type = ToolParameterType.STRING,
                        description = "Timezone ID (e.g. 'America/New_York', 'Asia/Tokyo'). Defaults to device timezone.",
                        required = false
                    )
                ),
                category = "Utility"
            ),
            executor = { args ->
                val tzId = args["timezone"]?.stringValue
                val tz = if (!tzId.isNullOrBlank()) TimeZone.getTimeZone(tzId) else TimeZone.getDefault()
                val sdf = SimpleDateFormat("hh:mm:ss a z", Locale.getDefault())
                sdf.timeZone = tz
                mapOf("time" to ToolValue.string(sdf.format(Date())))
            }
        )
    }

    private suspend fun registerGetCurrentDate() {
        RunAnywhereToolCalling.registerTool(
            definition = ToolDefinition(
                name = "get_current_date",
                description = "Get the current date",
                parameters = emptyList(),
                category = "Utility"
            ),
            executor = {
                val sdf = SimpleDateFormat("EEEE, MMMM d, yyyy", Locale.getDefault())
                mapOf("date" to ToolValue.string(sdf.format(Date())))
            }
        )
    }

    private suspend fun registerGetBatteryLevel(context: Context) {
        RunAnywhereToolCalling.registerTool(
            definition = ToolDefinition(
                name = "get_battery_level",
                description = "Get the current battery level and charging status of the device",
                parameters = emptyList(),
                category = "Utility"
            ),
            executor = {
                val batteryIntent = context.registerReceiver(
                    null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                )
                val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
                val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                val pct = (level * 100) / scale
                val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL
                mapOf(
                    "battery_percent" to ToolValue.number(pct),
                    "charging" to ToolValue.bool(charging)
                )
            }
        )
    }

    private suspend fun registerGetDeviceInfo(context: Context) {
        RunAnywhereToolCalling.registerTool(
            definition = ToolDefinition(
                name = "get_device_info",
                description = "Get device information including model, Android version, and screen brightness",
                parameters = emptyList(),
                category = "Utility"
            ),
            executor = {
                val brightness = try {
                    val raw = Settings.System.getInt(
                        context.contentResolver, Settings.System.SCREEN_BRIGHTNESS
                    )
                    "${(raw * 100) / 255}%"
                } catch (_: Exception) { "unknown" }

                mapOf(
                    "manufacturer" to ToolValue.string(android.os.Build.MANUFACTURER),
                    "model" to ToolValue.string(android.os.Build.MODEL),
                    "android_version" to ToolValue.string(android.os.Build.VERSION.RELEASE),
                    "api_level" to ToolValue.number(android.os.Build.VERSION.SDK_INT),
                    "brightness" to ToolValue.string(brightness)
                )
            }
        )
    }

    private suspend fun registerMathCalculate() {
        RunAnywhereToolCalling.registerTool(
            definition = ToolDefinition(
                name = "math_calculate",
                description = "Evaluate a mathematical expression (supports +, -, *, /, parentheses)",
                parameters = listOf(
                    ToolParameter(
                        name = "expression",
                        type = ToolParameterType.STRING,
                        description = "The math expression to evaluate, e.g. '(15 + 27) * 3'",
                        required = true
                    )
                ),
                category = "Utility"
            ),
            executor = { args ->
                val expr = args["expression"]?.stringValue ?: "0"
                try {
                    val result = SimpleExpressionEvaluator.evaluate(expr)
                    mapOf(
                        "expression" to ToolValue.string(expr),
                        "result" to ToolValue.number(result)
                    )
                } catch (e: Exception) {
                    mapOf("error" to ToolValue.string("Error evaluating '$expr': ${e.message}"))
                }
            }
        )
    }

    private suspend fun registerGetWeather() {
        RunAnywhereToolCalling.registerTool(
            definition = ToolDefinition(
                name = "get_weather",
                description = "Get current weather for a location. Uses Open-Meteo API (no API key needed).",
                parameters = listOf(
                    ToolParameter(
                        name = "latitude",
                        type = ToolParameterType.NUMBER,
                        description = "Latitude of the location",
                        required = true
                    ),
                    ToolParameter(
                        name = "longitude",
                        type = ToolParameterType.NUMBER,
                        description = "Longitude of the location",
                        required = true
                    ),
                    ToolParameter(
                        name = "location_name",
                        type = ToolParameterType.STRING,
                        description = "Human-readable location name for display",
                        required = false
                    )
                ),
                category = "Utility"
            ),
            executor = { args ->
                val lat = args["latitude"]?.numberValue ?: 0.0
                val lon = args["longitude"]?.numberValue ?: 0.0
                val name = args["location_name"]?.stringValue ?: "(%.2f, %.2f)".format(lat, lon)

                withContext(Dispatchers.IO) {
                    try {
                        val urlStr = "https://api.open-meteo.com/v1/forecast" +
                                "?latitude=$lat&longitude=$lon" +
                                "&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code"
                        val url = URL(urlStr)
                        val conn = url.openConnection() as HttpURLConnection
                        conn.connectTimeout = 10_000
                        conn.readTimeout = 10_000
                        try {
                            val body = conn.inputStream.bufferedReader().use { it.readText() }

                            val json = org.json.JSONObject(body)
                            val current = json.getJSONObject("current")
                            val temp = current.getDouble("temperature_2m")
                            val humidity = current.getInt("relative_humidity_2m")
                            val wind = current.getDouble("wind_speed_10m")
                            val code = current.getInt("weather_code")

                            mapOf(
                                "location" to ToolValue.string(name),
                                "temperature_celsius" to ToolValue.number(temp),
                                "humidity_percent" to ToolValue.number(humidity),
                                "wind_speed_kmh" to ToolValue.number(wind),
                                "condition" to ToolValue.string(weatherCodeToDescription(code))
                            )
                        } finally {
                            conn.disconnect()
                        }
                    } catch (e: Exception) {
                        mapOf("error" to ToolValue.string("Weather lookup failed: ${e.message}"))
                    }
                }
            }
        )
    }

    private suspend fun registerUnitConvert() {
        RunAnywhereToolCalling.registerTool(
            definition = ToolDefinition(
                name = "unit_convert",
                description = "Convert between common units (temperature, length, weight)",
                parameters = listOf(
                    ToolParameter(
                        name = "value",
                        type = ToolParameterType.NUMBER,
                        description = "The numeric value to convert",
                        required = true
                    ),
                    ToolParameter(
                        name = "from_unit",
                        type = ToolParameterType.STRING,
                        description = "Source unit (e.g. 'celsius', 'fahrenheit', 'km', 'miles', 'kg', 'lbs')",
                        required = true
                    ),
                    ToolParameter(
                        name = "to_unit",
                        type = ToolParameterType.STRING,
                        description = "Target unit",
                        required = true
                    )
                ),
                category = "Utility"
            ),
            executor = { args ->
                val value = args["value"]?.numberValue ?: 0.0
                val from = args["from_unit"]?.stringValue?.lowercase() ?: ""
                val to = args["to_unit"]?.stringValue?.lowercase() ?: ""
                val result = UnitConverter.convert(value, from, to)
                mapOf("result" to ToolValue.string(result))
            }
        )
    }

    private suspend fun registerGetClipboard(context: Context) {
        RunAnywhereToolCalling.registerTool(
            definition = ToolDefinition(
                name = "get_clipboard",
                description = "Get the current text content of the device clipboard",
                parameters = emptyList(),
                category = "Utility"
            ),
            executor = {
                val text = withContext(Dispatchers.Main) {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
                            as android.content.ClipboardManager
                    val clip = clipboard.primaryClip
                    if (clip != null && clip.itemCount > 0) {
                        clip.getItemAt(0).text?.toString() ?: "(clipboard empty)"
                    } else {
                        "(clipboard empty)"
                    }
                }
                mapOf("clipboard_text" to ToolValue.string(text))
            }
        )
    }

    private fun weatherCodeToDescription(code: Int): String = when (code) {
        0 -> "Clear sky"
        1, 2, 3 -> "Partly cloudy"
        45, 48 -> "Foggy"
        51, 53, 55 -> "Drizzle"
        61, 63, 65 -> "Rain"
        71, 73, 75 -> "Snow"
        80, 81, 82 -> "Rain showers"
        85, 86 -> "Snow showers"
        95 -> "Thunderstorm"
        96, 99 -> "Thunderstorm with hail"
        else -> "Unknown weather (code $code)"
    }
}
