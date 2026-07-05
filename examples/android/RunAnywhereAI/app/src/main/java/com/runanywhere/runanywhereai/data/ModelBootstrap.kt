package com.runanywhere.runanywhereai.data

import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.hybrid.Cloud
import com.runanywhere.sdk.npu.qhexrt.QHexRT
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
        seedCatalog()
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
    private suspend fun seedCatalog() {
        // Register NPU bundles only for the probed Hexagon arch (context binaries are
        // arch-exact); unsupported devices get none, keeping every picker naturally clean.
        val npuArch = runCatching {
            QHexRT.probeNpu().takeIf { it.qhexrt_supported }?.arch_name
        }.getOrNull()
        var ok = 0
        var fail = 0
        for (model in ModelCatalog.models + ModelCatalog.npuModels(npuArch)) {
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
        RACLog.i("catalog seeded: ok=$ok failed=$fail")
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
