package com.runanywhere.runanywhereai.ui.navigation

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TopLevelNavigationPolicyTest {
    @Test
    fun `ordinary vision navigation never restores a saved live-camera argument`() {
        assertFalse(shouldRestoreTopLevelState(Vision()))
        assertFalse(shouldRestoreTopLevelState(Vision(openLiveCamera = true)))
    }

    @Test
    fun `non-camera top-level routes preserve their saved state`() {
        assertTrue(shouldRestoreTopLevelState(Chat))
        assertTrue(shouldRestoreTopLevelState(Voice))
        assertTrue(shouldRestoreTopLevelState(Settings))
    }
}
