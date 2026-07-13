package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Keep ordinary rows and the QHexRT rows that are either accepted by native
 * registration OR already downloaded on disk.
 *
 * Native re-registration is device- and network-dependent (it consults the
 * remote product-policy facade), so a QHexRT row that was registered on a prior
 * launch can be absent from [registeredNpuIds] when the app is offline. Keeping
 * an on-disk bundle visible lets the user still select and run it with no
 * network, instead of watching a downloaded model silently disappear.
 */
internal fun ModelInfo.isVisibleForNativeNpuCatalog(registeredNpuIds: Set<String>): Boolean =
    framework != InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT ||
        id in registeredNpuIds ||
        isDownloadedOnDisk

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
        // Wrap back to 1 (never 0, the initial value) at Long.MAX_VALUE so the
        // counter stays monotonic within its range and a wrapped revision still
        // differs from the fresh default. Reaching this bound is not physically
        // possible (~2^63 refreshes), but the guard keeps the invariant explicit.
        val nextRevision = if (previous.revision == Long.MAX_VALUE) 1L else previous.revision + 1
        mutableSnapshots.value = NpuCatalogSnapshot(
            registeredModelIds = registeredModelIds.toSet(),
            revision = nextRevision,
        )
    }
}
