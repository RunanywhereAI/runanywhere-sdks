package com.runanywhere.runanywhereai.data

import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.hybrid.Cloud
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.lora
import com.runanywhere.sdk.public.extensions.refreshModelRegistry
import kotlin.coroutines.cancellation.CancellationException

// Seeds the native registry on launch (cloud backend + curated catalog + LoRA), then refreshes
// it. Without this the model picker is empty: dev fetch returns nothing and rescan_local has no
// fs callbacks. Core backends (LlamaCPP/ONNX) are registered earlier, in RunAnywhereApplication,
// before RunAnywhere.initialize().
object ModelBootstrap {

    suspend fun setupModels() {
        registerRemoteBackends()
        seedCatalog(skipHfAuthModels = SettingsRepository.settings.hfToken.isBlank())
        seedLora()
        RunAnywhere.refreshModelRegistry()
    }

    private fun registerRemoteBackends() {
        try {
            Cloud.register()
        } catch (e: Exception) {
            RACLog.e("remote backends failed", e)
        }
    }

    // Re-registered on every launch, mirroring iOS ModelCatalogBootstrap: the commons registry
    // merges on re-save, preserving runtime fields (is_downloaded, per-file local paths,
    // checksums), so catalog metadata fixes reach existing installs without losing downloads.
    private suspend fun seedCatalog(skipHfAuthModels: Boolean) {
        var ok = 0
        var fail = 0
        var skipped = 0
        for (model in ModelCatalog.models + ModelCatalog.npuModels()) {
            if (skipHfAuthModels && model.requiresHfAuth) {
                skipped++
                continue
            }
            try {
                model.register()
                ok++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                fail++
                RACLog.e("catalog: ${model.id} failed", e)
            }
        }
        RACLog.i("catalog seeded: ok=$ok failed=$fail skippedHfAuth=$skipped")
    }

    suspend fun refreshNpuCatalog() {
        var ok = 0
        var fail = 0
        var skipped = 0
        val skipHfAuthModels = SettingsRepository.settings.hfToken.isBlank()
        for (model in ModelCatalog.npuModels()) {
            if (skipHfAuthModels && model.requiresHfAuth) {
                skipped++
                continue
            }
            try {
                model.register()
                ok++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                fail++
                RACLog.e("npu catalog: ${model.id} failed", e)
            }
        }
        val registryRefreshed = try {
            RunAnywhere.refreshModelRegistry()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("npu catalog registry refresh failed", e)
            false
        }
        RACLog.i(
            "npu catalog refreshed: ok=$ok failed=$fail skippedHfAuth=$skipped " +
                "registryRefreshed=$registryRefreshed",
        )
    }

    private suspend fun seedLora() {
        for (adapter in ModelCatalog.loraAdapters) {
            try {
                RunAnywhere.lora.register(adapter)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("lora: ${adapter.id} failed", e)
            }
        }
    }
}
