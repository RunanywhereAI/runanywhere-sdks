package com.runanywhere.runanywhereai.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Test

class NpuCatalogStateTest {
    @Test
    fun everyPublishAdvancesRevisionEvenWhenAcceptedIdsAreUnchanged() {
        val state = NpuCatalogState()
        val ids = mutableSetOf("lfm2_5_230m", "internvl3_5_1b")

        state.publish(ids)
        val first = state.snapshots.value
        state.publish(ids)
        val second = state.snapshots.value

        assertEquals(1L, first.revision)
        assertEquals(2L, second.revision)
        assertEquals(first.registeredModelIds, second.registeredModelIds)
        assertNotSame(first, second)
    }

    @Test
    fun publishedIdsAreAnImmutableSnapshotOfTheRegistrationPass() {
        val state = NpuCatalogState()
        val ids = mutableSetOf("lfm2_5_230m")

        state.publish(ids)
        ids += "not-published"

        assertEquals(setOf("lfm2_5_230m"), state.snapshots.value.registeredModelIds)
    }
}
