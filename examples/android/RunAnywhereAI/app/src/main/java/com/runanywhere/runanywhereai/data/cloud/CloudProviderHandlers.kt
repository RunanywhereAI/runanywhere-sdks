package com.runanywhere.runanywhereai.data.cloud

import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.hybrid.CloudSttRequest
import com.runanywhere.sdk.hybrid.CloudSttResult
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

// Performs the actual cloud HTTP call for a registered provider, picking the wire
// format from its preset. Runs on the router's request thread (off the main
// thread), so the blocking OkHttp call is fine here. The audio handed in is the
// WAV the hybrid pipeline produced.
object CloudProviderHandlers {

    private val client = OkHttpClient.Builder()
        .callTimeout(60, TimeUnit.SECONDS)
        .build()

    private val WAV = "audio/wav".toMediaType()

    fun transcribe(config: CloudProviderConfig, request: CloudSttRequest): CloudSttResult =
        when (config.preset) {
            CloudPreset.SARVAM -> sarvam(config, request)
            CloudPreset.OPENAI -> openAiStyle(config, request, "/v1/audio/transcriptions")
            CloudPreset.OPENROUTER -> openAiStyle(config, request, "/audio/transcriptions")
        }

    private fun sarvam(config: CloudProviderConfig, req: CloudSttRequest): CloudSttResult {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("file", "audio.wav", req.audio.toRequestBody(WAV))
            .addFormDataPart("model", config.model)
            .apply { req.languageCode?.let { addFormDataPart("language_code", it) } }
            .build()
        val http = Request.Builder()
            .url(base(config) + "/speech-to-text")
            .header("api-subscription-key", config.apiKey)
            .post(body)
            .build()
        return exec(http) { it.optString("transcript") to it.optString("language_code").ifBlank { null } }
    }

    // OpenAI-compatible multipart transcription (OpenAI + OpenRouter): same body and
    // Bearer auth; the path differs because OpenRouter's base already carries /api/v1.
    private fun openAiStyle(config: CloudProviderConfig, req: CloudSttRequest, path: String): CloudSttResult {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("file", "audio.wav", req.audio.toRequestBody(WAV))
            .addFormDataPart("model", config.model)
            .build()
        val http = Request.Builder()
            .url(base(config) + path)
            .header("Authorization", "Bearer ${config.apiKey}")
            .post(body)
            .build()
        return exec(http) { it.optString("text") to null }
    }

    private fun base(config: CloudProviderConfig): String =
        config.baseUrl.ifBlank { config.preset.defaultBaseUrl }.trimEnd('/')

    private inline fun exec(request: Request, parse: (JSONObject) -> Pair<String, String?>): CloudSttResult {
        client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (!resp.isSuccessful) {
                RACLog.w("cloud provider HTTP ${resp.code}: ${raw.take(300)}")
                throw IllegalStateException("HTTP ${resp.code}")
            }
            val (text, language) = parse(JSONObject(raw))
            return CloudSttResult(text = text.trim(), languageCode = language)
        }
    }
}
