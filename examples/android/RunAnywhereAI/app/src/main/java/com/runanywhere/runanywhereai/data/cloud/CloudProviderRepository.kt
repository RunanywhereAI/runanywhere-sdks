package com.runanywhere.runanywhereai.data.cloud

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.runanywhere.runanywhereai.data.security.SecureStringPreferences
import com.runanywhere.runanywhereai.data.security.migrateSensitiveString
import com.runanywhere.runanywhereai.data.security.securePreferences
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.hybrid.Cloud
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

// Stores developer-registered cloud STT providers and keeps them registered with
// the SDK (Cloud.registerProvider + Cloud.register). The provider name and the
// router registry id are the same per-config unique string.
object CloudProviderRepository {
    private const val LEGACY_PREFS = "cloud_providers"
    private const val SECURE_PREFS = "cloud_secure_providers"
    private const val KEY_LIST = "providers"

    private val json = Json { ignoreUnknownKeys = true }
    private val serializer = ListSerializer(CloudProviderConfig.serializer())
    private var prefs: SecureStringPreferences? = null

    var providers: List<CloudProviderConfig> by mutableStateOf(emptyList())
        private set

    val defaultProviderId: String?
        get() = providers.firstOrNull()?.id

    fun initialize(context: Context) = initialize(context, ::securePreferences)

    internal fun initialize(
        context: Context,
        securePreferencesFactory: (Context, String) -> SecureStringPreferences,
    ) {
        if (prefs != null) return
        val secure = runCatching { securePreferencesFactory(context, SECURE_PREFS) }
            .onFailure { RACLog.w("Secure cloud-provider storage unavailable; providers cannot be loaded or saved") }
            .getOrNull()
        if (secure == null) {
            providers = emptyList()
            return
        }
        val legacy = context.getSharedPreferences(LEGACY_PREFS, Context.MODE_PRIVATE)
        val migration = migrateSensitiveString(
            readSecure = { secure.getString(KEY_LIST) },
            readLegacy = { legacy.getString(KEY_LIST, null) },
            writeSecure = { secure.putString(KEY_LIST, it) },
            removeLegacy = { legacy.edit().remove(KEY_LIST).commit() },
            validate = { encoded ->
                runCatching { json.decodeFromString(serializer, encoded) }.isSuccess
            },
        )
        if (migration.failure != null) {
            RACLog.w("cloud_provider_credential_migration_${migration.failure.name.lowercase()}")
        }
        providers = migration.value?.let { encoded ->
            runCatching { json.decodeFromString(serializer, encoded) }
                .onFailure { RACLog.w("secure_cloud_provider_value_invalid") }
                .getOrDefault(emptyList())
        }.orEmpty()
        prefs = secure
    }

    internal fun resetForTesting() {
        prefs = null
        providers = emptyList()
    }

    // Register every saved provider with the SDK. Call once after RunAnywhere.initialize.
    fun registerAll() {
        providers.forEach { config ->
            register(config).onFailure {
                RACLog.e("cloud provider register failed: ${config.id}", it)
            }
        }
    }

    fun upsert(config: CloudProviderConfig): Result<Unit> {
        val updated = providers.filterNot { it.id == config.id } + config
        persist(updated).onFailure { return Result.failure(it) }
        providers = updated
        return register(config)
    }

    fun remove(id: String): Result<Unit> {
        val updated = providers.filterNot { it.id == id }
        persist(updated).onFailure { return Result.failure(it) }
        providers = updated
        return runCatching {
            Cloud.unregisterProvider(id)
            Cloud.unregisterModel(id)
            Unit
        }.recoverCatching {
            throw IllegalStateException("Provider was removed, but SDK cleanup failed", it)
        }
    }

    fun labelFor(id: String?): String? =
        id?.let { providerId -> providers.firstOrNull { it.id == providerId }?.label ?: providerId }

    private fun register(config: CloudProviderConfig): Result<Unit> =
        runCatching {
            Cloud.registerProvider(config.id) { req -> CloudProviderHandlers.transcribe(config, req) }
            Cloud.register(
                id = config.id,
                provider = config.id,
                model = config.model,
                apiKey = config.apiKey,
                baseUrl = config.baseUrl.ifBlank { config.preset.defaultBaseUrl },
            )
        }.recoverCatching {
            throw IllegalStateException("Provider was saved securely, but SDK registration failed", it)
        }

    private fun persist(updated: List<CloudProviderConfig>): Result<Unit> {
        val secure = prefs
            ?: return Result.failure(IllegalStateException("Secure cloud-provider storage is unavailable"))
        val encoded = runCatching { json.encodeToString(serializer, updated) }
            .getOrElse { return Result.failure(IllegalStateException("Could not encode cloud providers", it)) }
        val committed = runCatching {
            secure.putString(KEY_LIST, encoded)
        }.getOrElse {
            return Result.failure(IllegalStateException("Could not write secure cloud-provider storage", it))
        }
        return if (committed) {
            Result.success(Unit)
        } else {
            Result.failure(IllegalStateException("Could not commit secure cloud-provider storage"))
        }
    }
}
