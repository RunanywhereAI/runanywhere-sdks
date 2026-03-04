package com.runanywhere.agent.toolcalling

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.provider.Settings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

object BuiltInTools {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    fun registerAll(registry: ToolRegistry, context: Context) {
        registerGetCurrentTime(registry)
        registerGetCurrentDate(registry)
        registerGetBatteryLevel(registry, context)
        registerGetDeviceInfo(registry, context)
        registerMathCalculate(registry)
        registerGetWeather(registry)
        registerUnitConvert(registry)
        registerGetClipboard(registry, context)
    }

    private fun registerGetCurrentTime(registry: ToolRegistry) {
        registry.register(
            ToolDefinition(
                name = "get_current_time",
                description = "Get the current time in a specified timezone",
                parameters = listOf(
                    ToolParameter(
                        name = "timezone",
                        type = ToolParameterType.STRING,
                        description = "Timezone ID (e.g. 'America/New_York', 'Asia/Tokyo', 'UTC'). Defaults to device timezone.",
                        required = false
                    )
                )
            )
        ) { args ->
            val tzId = args["timezone"]?.toString()
            val tz = if (!tzId.isNullOrBlank()) TimeZone.getTimeZone(tzId) else TimeZone.getDefault()
            val sdf = SimpleDateFormat("hh:mm:ss a z", Locale.getDefault())
            sdf.timeZone = tz
            sdf.format(Date())
        }
    }

    private fun registerGetCurrentDate(registry: ToolRegistry) {
        registry.register(
            ToolDefinition(
                name = "get_current_date",
                description = "Get the current date",
                parameters = emptyList()
            )
        ) { _ ->
            val sdf = SimpleDateFormat("EEEE, MMMM d, yyyy", Locale.getDefault())
            sdf.format(Date())
        }
    }

    private fun registerGetBatteryLevel(registry: ToolRegistry, context: Context) {
        registry.register(
            ToolDefinition(
                name = "get_battery_level",
                description = "Get the current battery level and charging status of the device",
                parameters = emptyList()
            )
        ) { _ ->
            val batteryIntent = context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
            val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val pct = (level * 100) / scale
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
            "Battery: $pct%, ${if (charging) "charging" else "not charging"}"
        }
    }

    private fun registerGetDeviceInfo(registry: ToolRegistry, context: Context) {
        registry.register(
            ToolDefinition(
                name = "get_device_info",
                description = "Get device information including model, Android version, and screen brightness",
                parameters = emptyList()
            )
        ) { _ ->
            val brightness = try {
                val raw = Settings.System.getInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS
                )
                "${(raw * 100) / 255}%"
            } catch (_: Exception) {
                "unknown"
            }

            "Device: ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}, " +
                    "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT}), " +
                    "Brightness: $brightness"
        }
    }

    private fun registerMathCalculate(registry: ToolRegistry) {
        registry.register(
            ToolDefinition(
                name = "math_calculate",
                description = "Evaluate a mathematical expression (supports +, -, *, /, parentheses)",
                parameters = listOf(
                    ToolParameter(
                        name = "expression",
                        type = ToolParameterType.STRING,
                        description = "The math expression to evaluate, e.g. '(15 + 27) * 3'",
                        required = true
                    )
                )
            )
        ) { args ->
            val expr = args["expression"]?.toString()
                ?: return@register "Error: no expression provided"
            try {
                val result = SimpleExpressionEvaluator.evaluate(expr)
                "$expr = $result"
            } catch (e: Exception) {
                "Error evaluating '$expr': ${e.message}"
            }
        }
    }

    private fun registerGetWeather(registry: ToolRegistry) {
        registry.register(
            ToolDefinition(
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
                )
            )
        ) { args ->
            val lat = args["latitude"]?.toString()?.toDoubleOrNull()
                ?: return@register "Error: latitude required"
            val lon = args["longitude"]?.toString()?.toDoubleOrNull()
                ?: return@register "Error: longitude required"
            val name = args["location_name"]?.toString() ?: "(%.2f, %.2f)".format(lat, lon)

            withContext(Dispatchers.IO) {
                val url = "https://api.open-meteo.com/v1/forecast" +
                        "?latitude=$lat&longitude=$lon" +
                        "&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code"
                val request = Request.Builder().url(url).build()
                try {
                    val response = httpClient.newCall(request).execute()
                    val body = response.body?.string() ?: return@withContext "No response from weather API"
                    val json = JSONObject(body)
                    val current = json.getJSONObject("current")
                    val temp = current.getDouble("temperature_2m")
                    val humidity = current.getInt("relative_humidity_2m")
                    val wind = current.getDouble("wind_speed_10m")
                    val code = current.getInt("weather_code")
                    val desc = weatherCodeToDescription(code)
                    "Weather in $name: $desc, ${temp}\u00B0C, humidity ${humidity}%, wind ${wind} km/h"
                } catch (e: Exception) {
                    "Weather lookup failed: ${e.message}"
                }
            }
        }
    }

    private fun registerUnitConvert(registry: ToolRegistry) {
        registry.register(
            ToolDefinition(
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
                )
            )
        ) { args ->
            val value = args["value"]?.toString()?.toDoubleOrNull()
                ?: return@register "Error: value required"
            val from = args["from_unit"]?.toString()?.lowercase()
                ?: return@register "Error: from_unit required"
            val to = args["to_unit"]?.toString()?.lowercase()
                ?: return@register "Error: to_unit required"
            UnitConverter.convert(value, from, to)
        }
    }

    private fun registerGetClipboard(registry: ToolRegistry, context: Context) {
        registry.register(
            ToolDefinition(
                name = "get_clipboard",
                description = "Get the current text content of the device clipboard",
                parameters = emptyList()
            )
        ) { _ ->
            withContext(Dispatchers.Main) {
                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
                        as android.content.ClipboardManager
                val clip = clipboard.primaryClip
                if (clip != null && clip.itemCount > 0) {
                    clip.getItemAt(0).text?.toString() ?: "(clipboard empty)"
                } else {
                    "(clipboard empty)"
                }
            }
        }
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
