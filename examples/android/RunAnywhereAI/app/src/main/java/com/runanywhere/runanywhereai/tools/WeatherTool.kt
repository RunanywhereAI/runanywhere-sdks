package com.runanywhere.runanywhereai.tools

import com.runanywhere.sdk.public.extensions.LLM.RAToolValue
import com.runanywhere.sdk.public.extensions.LLM.string
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder

internal object WeatherTool {
    private const val TIMEOUT_MS = 15_000L
    private val client = OkHttpClient()

    suspend fun fetch(location: String): Map<String, RAToolValue> = withContext(Dispatchers.IO) {
        if (location.isBlank()) return@withContext error("No location provided")
        runCatching {
            withTimeout(TIMEOUT_MS) {
                val place = geocode(location) ?: return@withTimeout error("Could not find '$location'")
                val (temperature, conditions) = currentWeather(place.lat, place.lon)
                mapOf(
                    "location" to RAToolValue.string(place.label),
                    "temperature" to RAToolValue.string("$temperature°C"),
                    "conditions" to RAToolValue.string(conditions),
                )
            }
        }.getOrElse { error("Weather lookup failed: ${it.message}") }
    }

    private fun error(message: String) = mapOf("error" to RAToolValue.string(message))

    private data class Place(val lat: Double, val lon: Double, val label: String)

    private fun geocode(name: String): Place? {
        val url = "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" +
            URLEncoder.encode(name, "UTF-8")
        val results = get(url)?.let { JSONObject(it).optJSONArray("results") } ?: return null
        if (results.length() == 0) return null
        val first = results.getJSONObject(0)
        val label = listOfNotNull(
            first.optString("name").ifBlank { null },
            first.optString("country").ifBlank { null },
        ).joinToString(", ").ifBlank { name }
        return Place(first.getDouble("latitude"), first.getDouble("longitude"), label)
    }

    private fun currentWeather(lat: Double, lon: Double): Pair<Double, String> {
        val url = "https://api.open-meteo.com/v1/forecast?current=temperature_2m,weather_code" +
            "&latitude=$lat&longitude=$lon"
        val body = get(url) ?: throw IllegalStateException("no response")
        val current = JSONObject(body).getJSONObject("current")
        return current.getDouble("temperature_2m") to describe(current.optInt("weather_code", -1))
    }

    private fun get(url: String): String? {
        val request = Request.Builder().url(url).build()
        client.newCall(request).execute().use { response ->
            return if (response.isSuccessful) response.body.string() else null
        }
    }

    private fun describe(code: Int): String = when (code) {
        0 -> "Clear sky"
        1, 2, 3 -> "Partly cloudy"
        45, 48 -> "Fog"
        51, 53, 55 -> "Drizzle"
        61, 63, 65 -> "Rain"
        66, 67 -> "Freezing rain"
        71, 73, 75, 77 -> "Snow"
        80, 81, 82 -> "Rain showers"
        85, 86 -> "Snow showers"
        95, 96, 99 -> "Thunderstorm"
        else -> "Unknown"
    }
}
