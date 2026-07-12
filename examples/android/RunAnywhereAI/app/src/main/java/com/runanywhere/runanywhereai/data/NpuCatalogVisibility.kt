package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Keep ordinary rows and only the QHexRT rows accepted by native registration. */
internal fun ModelInfo.isVisibleForNativeNpuCatalog(registeredNpuIds: Set<String>): Boolean =
    framework != InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT || id in registeredNpuIds

/**
 * Versioned native-catalog result shared with retained model pickers.
 *
 * [revision] advances for every completed seed/refresh, even when the accepted
 * ID set is unchanged. This matters when the registry was re-populated after a
 * token or transport update: `StateFlow<Set<String>>` alone would suppress that
 * refresh and leave an activity-scoped picker showing its old snapshot.
 */
internal data class NpuCatalogSnapshot(
    val registeredModelIds: Set<String> = emptySet(),
    val revision: Long = 0,
)

internal class NpuCatalogState {
    private val mutableSnapshots = MutableStateFlow(NpuCatalogSnapshot())

    val snapshots: StateFlow<NpuCatalogSnapshot> = mutableSnapshots

    fun publish(registeredModelIds: Set<String>) {
        val previous = mutableSnapshots.value
        mutableSnapshots.value = NpuCatalogSnapshot(
            registeredModelIds = registeredModelIds.toSet(),
            revision = previous.revision + 1,
        )
    }
}
