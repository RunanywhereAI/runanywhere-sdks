package com.runanywhere.runanywhereai.ui.screens.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatGenerationOwnershipTest {
    @Test
    fun `cancellation revokes stale writes and blocks an immediate replacement`() {
        val lifecycle = ChatGenerationOwnership()
        val first = requireNotNull(lifecycle.tryStart())

        assertTrue(lifecycle.owns(first))
        assertTrue(lifecycle.requestCancellation() == first)
        assertFalse(lifecycle.owns(first))
        assertNull(lifecycle.tryStart())
    }

    @Test
    fun `replacement waits for native cancellation and worker termination in either order`() {
        val firstOrder = ChatGenerationOwnership()
        val first = requireNotNull(firstOrder.tryStart())
        firstOrder.requestCancellation()
        firstOrder.finishWorker(first)
        assertFalse(firstOrder.completeCancellation(first))
        assertNull(firstOrder.tryStart())
        firstOrder.markNativeCancellationIssued(first)
        assertTrue(firstOrder.completeCancellation(first))
        assertNotNull(firstOrder.tryStart())

        val secondOrder = ChatGenerationOwnership()
        val second = requireNotNull(secondOrder.tryStart())
        secondOrder.requestCancellation()
        secondOrder.markNativeCancellationIssued(second)
        assertFalse(secondOrder.completeCancellation(second))
        assertNull(secondOrder.tryStart())
        secondOrder.finishWorker(second)
        assertTrue(secondOrder.completeCancellation(second))
        assertNotNull(secondOrder.tryStart())
    }

    @Test
    fun `late finally from an older request cannot finish the newer request`() {
        val lifecycle = ChatGenerationOwnership()
        val first = requireNotNull(lifecycle.tryStart())
        assertTrue(lifecycle.finishWorker(first).ownedAtFinish)
        val second = requireNotNull(lifecycle.tryStart())

        val duplicateOldFinish = lifecycle.finishWorker(first)

        assertFalse(duplicateOldFinish.ownedAtFinish)
        assertTrue(lifecycle.owns(second))
        assertNull(lifecycle.tryStart())
    }
}
