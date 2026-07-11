package com.runanywhere.runanywhereai.data

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

    private val npuCatalogState = NpuCatalogState()

    /** QHexRT rows accepted by the native device-aware catalog facade this run. */
    internal val registeredNpuModelIds: Set<String>
        get() = npuCatalogState.snapshots.value.registeredModelIds

    /** Emits after every completed native catalog seed/refresh. */
    internal val npuCatalogSnapshots
        get() = npuCatalogState.snapshots

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
        val regular = registerCatalogRows(ModelCatalog.models, "catalog")
        val npu = registerCatalogRows(ModelCatalog.npuCatalog, "npu catalog")
        npuCatalogState.publish(npu.registeredIds)
        RACLog.i(
            "catalog seeded: ok=${regular.registered + npu.registered} " +
                "failed=${regular.failed + npu.failed} " +
                "skippedNative=${regular.skippedNative + npu.skippedNative}",
        )
    }

    suspend fun refreshNpuCatalog() {
        val npu = registerCatalogRows(ModelCatalog.npuCatalog, "npu catalog")
        val registryRefreshed = try {
            RunAnywhere.refreshModelRegistry()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("npu catalog registry refresh failed", e)
            false
        }
        // Publish after the registry operation so retained pickers always read
        // the completed refresh, never an intermediate catalog snapshot.
        npuCatalogState.publish(npu.registeredIds)
        RACLog.i(
            "npu catalog refreshed: ok=${npu.registered} failed=${npu.failed} " +
                "skippedNative=${npu.skippedNative} " +
                "registryRefreshed=$registryRefreshed",
        )
    }

    private suspend fun registerCatalogRows(
        models: List<CatalogModel>,
        logLabel: String,
    ): CatalogSeedResult {
        var registered = 0
        var failed = 0
        var skippedNative = 0
        val registeredIds = mutableSetOf<String>()
        for (model in models) {
            try {
                val saved = model.register()
                if (saved == null) {
                    skippedNative++
                } else {
                    registered++
                    registeredIds += saved.id
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed++
                RACLog.e("$logLabel: ${model.id} failed", e)
            }
        }
        return CatalogSeedResult(
            registered = registered,
            failed = failed,
            skippedNative = skippedNative,
            registeredIds = registeredIds,
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

private data class CatalogSeedResult(
    val registered: Int,
    val failed: Int,
    val skippedNative: Int,
    val registeredIds: Set<String>,
)
