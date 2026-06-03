package com.runanywhere.runanywhereai.data.cloud

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.hybrid.BACKEND
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

// Stores developer-registered cloud STT providers and keeps them registered with
// the SDK (BACKEND.CLOUD.registerProvider + register). The provider name and the
// router registry id are the same per-config unique string.
object CloudProviderRepository {
    private const val PREFS = "cloud_providers"
    private const val KEY_LIST = "providers"

    // The built-in Sarvam entry seeded by ModelBootstrap (static native adapter);
    // it isn't managed here, but the UI offers it as the default online backend.
    const val BUILTIN_SARVAM_ID = "saaras"

    private val json = Json { ignoreUnknownKeys = true }
    private val serializer = ListSerializer(CloudProviderConfig.serializer())
    private var prefs: SharedPreferences? = null

    var providers: List<CloudProviderConfig> by mutableStateOf(emptyList())
        private set

    fun initialize(context: Context) {
        if (prefs != null) return
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs = p
        providers = runCatching {
            p.getString(KEY_LIST, null)?.let { json.decodeFromString(serializer, it) }
        }.getOrNull().orEmpty()
    }

    // Register every saved provider with the SDK. Call once after RunAnywhere.initialize.
    fun registerAll() {
        providers.forEach { register(it) }
    }

    fun upsert(config: CloudProviderConfig) {
        providers = providers.filterNot { it.id == config.id } + config
        persist()
        register(config)
    }

    fun remove(id: String) {
        providers = providers.filterNot { it.id == id }
        persist()
        runCatching {
            BACKEND.CLOUD.unregisterProvider(id)
            BACKEND.CLOUD.unregister(id)
        }.onFailure { RACLog.w("cloud provider unregister failed: ${it.message}") }
    }

    private fun register(config: CloudProviderConfig) {
        runCatching {
            BACKEND.CLOUD.registerProvider(config.id) { req -> CloudProviderHandlers.transcribe(config, req) }
            BACKEND.CLOUD.register(
                id = config.id,
                model = config.model,
                apiKey = config.apiKey,
                provider = config.id,
                baseUrl = config.baseUrl.ifBlank { config.preset.defaultBaseUrl },
            )
        }.onFailure { RACLog.e("cloud provider register failed: ${config.id}", it) }
    }

    private fun persist() {
        prefs?.edit()?.putString(KEY_LIST, json.encodeToString(serializer, providers))?.apply()
    }
}
