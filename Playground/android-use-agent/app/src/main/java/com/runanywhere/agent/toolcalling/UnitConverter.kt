package com.runanywhere.agent.toolcalling

object UnitConverter {
    fun convert(value: Double, from: String, to: String): String {
        val result = when {
            // Temperature
            from == "celsius" && to == "fahrenheit" -> value * 9.0 / 5.0 + 32
            from == "fahrenheit" && to == "celsius" -> (value - 32) * 5.0 / 9.0
            from == "celsius" && to == "kelvin" -> value + 273.15
            from == "kelvin" && to == "celsius" -> value - 273.15
            from == "fahrenheit" && to == "kelvin" -> (value - 32) * 5.0 / 9.0 + 273.15
            from == "kelvin" && to == "fahrenheit" -> (value - 273.15) * 9.0 / 5.0 + 32
            // Length
            from == "km" && to == "miles" -> value * 0.621371
            from == "miles" && to == "km" -> value / 0.621371
            from == "m" && to == "feet" -> value * 3.28084
            from == "feet" && to == "m" -> value / 3.28084
            from == "cm" && to == "inches" -> value / 2.54
            from == "inches" && to == "cm" -> value * 2.54
            // Weight
            from == "kg" && to == "lbs" -> value * 2.20462
            from == "lbs" && to == "kg" -> value / 2.20462
            from == "g" && to == "oz" -> value / 28.3495
            from == "oz" && to == "g" -> value * 28.3495
            // Same unit
            from == to -> value
            else -> return "Unsupported conversion: $from -> $to"
        }
        return "%.4f %s = %.4f %s".format(value, from, result, to)
    }
}
