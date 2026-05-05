package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.llm.genie.Genie
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.refreshModelRegistry
import timber.log.Timber

object ModelBootstrap {
    suspend fun setupModels() {
        Timber.i("Registering backends and refreshing native model catalog...")
        registerBackends()
        refreshNativeCatalog()
    }

    private fun registerBackends() {
        try {
            LlamaCPP.register(priority = 100)
            ONNX.register(priority = 100)
            Timber.i("Core backends registered")
        } catch (e: Exception) {
            Timber.e(e, "Failed to register core backends")
        }

        try {
            Genie.register(priority = 200)
            Timber.i("Genie NPU backend registered")
        } catch (e: Exception) {
            Timber.w(e, "Genie backend unavailable")
        }
    }

    private suspend fun refreshNativeCatalog() {
        try {
            val result =
                RunAnywhere.refreshModelRegistry(
                    ModelRegistryRefreshRequest(
                        include_remote_catalog = true,
                        rescan_local = true,
                        prune_orphans = false,
                        include_downloaded_state = true,
                    ),
                )
            if (result.success) {
                Timber.i(
                    "Native model catalog refreshed: registered=${result.registered_count}, " +
                        "downloaded=${result.downloaded_count}, available=${result.available_count}",
                )
            } else {
                Timber.w(
                    "Native model catalog refresh returned an error: " +
                        result.error_message.ifBlank { "unknown error" },
                )
            }
            result.warnings.forEach { warning ->
                Timber.w("Native model catalog refresh warning: $warning")
            }
        } catch (e: SDKException) {
            Timber.w(
                e,
                "Native model catalog refresh unavailable: ${e.error.message}",
            )
        }
    }
}
