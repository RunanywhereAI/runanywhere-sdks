package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ModelListRequest
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.features.TTS.System.SystemTTSModule
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.hybrid.Cloud
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.lora
import kotlin.coroutines.cancellation.CancellationException

// Seeds the native registry on launch (backends + curated catalog + LoRA). Without this the
// model picker is empty: dev fetch returns nothing and rescan_local has no fs callbacks.
object ModelBootstrap {

    suspend fun setupModels() {
        registerCoreBackends()
        registerRemoteBackends()
        seedCatalog()
        seedLora()
    }

    private suspend fun registerCoreBackends() {
        try {
            LlamaCPP.register()
            ONNX.register()
            SystemTTSModule.register()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("core backends failed", e)
        }
    }

    private fun registerRemoteBackends() {
        try {
            Cloud.register()
        } catch (e: Exception) {
            RACLog.e("remote backends failed", e)
        }
    }

    // Skip ids already in the registry — re-saving clobbers downloaded local_path / is_downloaded.
    private suspend fun seedCatalog() {
        val known = existingIds()
        var ok = 0
        var skip = 0
        var fail = 0
        for (model in ModelCatalog.models) {
            if (model.id in known) {
                skip++
                continue
            }
            try {
                CppBridgeModelRegistry.save(model.toModelInfo())
                ok++
            } catch (e: Exception) {
                fail++
                RACLog.e("catalog: ${model.id} failed", e)
            }
        }
        RACLog.i("catalog seeded: ok=$ok skipped=$skip failed=$fail")
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

    private suspend fun existingIds(): Set<String> = try {
        RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
            .mapTo(mutableSetOf()) { it.id }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        RACLog.w("registry snapshot failed", e)
        emptySet()
    }
}
