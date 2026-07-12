package com.runanywhere.runanywhereai.tools

import ai.runanywhere.proto.v1.ToolParameter
import ai.runanywhere.proto.v1.ToolParameterType
import android.content.Context
import android.os.BatteryManager
import android.os.Build
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.RAToolValue
import com.runanywhere.sdk.public.extensions.LLM.string
import com.runanywhere.sdk.public.extensions.registerTool
import com.runanywhere.sdk.public.types.RAToolDefinition
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object BuiltInTools {

    suspend fun register(context: Context) {
        val app = context.applicationContext
        runCatching {
            RunAnywhere.registerTool(
                RAToolDefinition(
                    name = "get_current_time",
                    description = "Returns the current date, time and timezone on the device.",
                    parameters = emptyList(),
                    category = "Utility",
                ),
            ) { currentTime() }

            RunAnywhere.registerTool(
                RAToolDefinition(
                    name = "get_device_info",
                    description = "Returns details about the device: manufacturer, model and Android version.",
                    parameters = emptyList(),
                    category = "Utility",
                ),
            ) { deviceInfo() }

            RunAnywhere.registerTool(
                RAToolDefinition(
                    name = "get_battery_level",
                    description = "Returns the current battery charge level as a percentage.",
                    parameters = emptyList(),
                    category = "Utility",
                ),
            ) { batteryLevel(app) }

            RunAnywhere.registerTool(
                RAToolDefinition(
                    name = "calculate",
                    description = "Evaluates a math expression with + - * / and parentheses.",
                    parameters = listOf(
                        ToolParameter(
                            name = "expression",
                            type = ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
                            description = "The expression to evaluate, e.g. '(3 + 4) * 2'.",
                            required = true,
                        ),
                    ),
                    category = "Utility",
                ),
            ) { args -> calculate(args["expression"]?.string.orEmpty()) }

            RunAnywhere.registerTool(WebSearchTool.definition, WebSearchTool::execute)
        }.onFailure { RACLog.w("tool registration failed: ${it.message}") }
    }

    private fun currentTime(): Map<String, RAToolValue> {
        val now = Date()
        val timeZone = TimeZone.getDefault()
        val displayFormatter = SimpleDateFormat("EEEE, d MMMM yyyy, h:mm a", Locale.getDefault()).apply {
            this.timeZone = timeZone
        }
        val isoFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
            this.timeZone = timeZone
        }
        return mapOf(
            "datetime" to RAToolValue.string(displayFormatter.format(now)),
            "iso8601" to RAToolValue.string(isoFormatter.format(now)),
            "timezone" to RAToolValue.string(timeZone.id),
        )
    }

    private fun deviceInfo(): Map<String, RAToolValue> = mapOf(
        "manufacturer" to RAToolValue.string(Build.MANUFACTURER),
        "model" to RAToolValue.string(Build.MODEL),
        "android_version" to RAToolValue.string(Build.VERSION.RELEASE),
        "sdk_int" to RAToolValue.string(Build.VERSION.SDK_INT.toString()),
    )

    private fun batteryLevel(context: Context): Map<String, RAToolValue> {
        val manager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val level = manager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        return mapOf(
            "battery_percent" to RAToolValue.string(if (level in 0..100) "$level%" else "unknown"),
        )
    }

    private fun calculate(expression: String): Map<String, RAToolValue> = runCatching {
        val value = ExpressionEvaluator(expression).evaluate()
        val formatted = if (value % 1.0 == 0.0) value.toLong().toString() else value.toString()
        mapOf("result" to RAToolValue.string(formatted))
    }.getOrElse {
        mapOf("error" to RAToolValue.string("Could not evaluate '$expression'"))
    }
}

private class ExpressionEvaluator(private val input: String) {
    private var pos = 0

    fun evaluate(): Double {
        val result = parseExpression()
        require(pos >= input.length) { "unexpected character at $pos" }
        return result
    }

    private fun parseExpression(): Double {
        var value = parseTerm()
        while (true) {
            when (peek()) {
                '+' -> { pos++; value += parseTerm() }
                '-' -> { pos++; value -= parseTerm() }
                else -> return value
            }
        }
    }

    private fun parseTerm(): Double {
        var value = parseFactor()
        while (true) {
            when (peek()) {
                '*' -> { pos++; value *= parseFactor() }
                '/' -> { pos++; value /= parseFactor() }
                else -> return value
            }
        }
    }

    private fun parseFactor(): Double {
        skipSpaces()
        when (peek()) {
            '(' -> {
                pos++
                val value = parseExpression()
                skipSpaces()
                require(peek() == ')') { "missing ')'" }
                pos++
                return value
            }
            '-' -> { pos++; return -parseFactor() }
            '+' -> { pos++; return parseFactor() }
        }
        val start = pos
        while (pos < input.length && (input[pos].isDigit() || input[pos] == '.')) pos++
        require(pos > start) { "expected number at $pos" }
        return input.substring(start, pos).toDouble()
    }

    private fun peek(): Char {
        skipSpaces()
        return if (pos < input.length) input[pos] else ' '
    }

    private fun skipSpaces() {
        while (pos < input.length && input[pos] == ' ') pos++
    }
}
